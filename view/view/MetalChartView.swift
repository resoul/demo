import UIKit
import MetalKit
import simd

struct MetalChartMetrics {
    let points: Int
    let vertices: Int
    let renderedFramesPerSecond: Double
    let gpuMilliseconds: Double
    let cpuEncodingMilliseconds: Double
}

private nonisolated struct PreparedChartData: @unchecked Sendable {
    let points: MTLBuffer
    let hierarchy: MTLBuffer
    let count: Int
    let capacity: Int
    let leaves: Int
    let domain: SIMD4<Float>
}

/// Sorted, finite XY samples. Pan/zoom update two matrices, never the sample array.
/// One shared input buffer, a GPU-only min/max hierarchy, and three frame slots.
final class MetalChartView: MTKView, MTKViewDelegate, MetalSnapshotProviding, UIGestureRecognizerDelegate {
    var onMetrics: ((MetalChartMetrics) -> Void)?
    var onError: ((Error) -> Void)?
    var bloomStrength: Float = 0.8
    var allowsVerticalPanning = true
    private(set) var pointCount = 0
    private(set) var pointCapacity = 0
    private(set) var visibleDomain = SIMD4<Float>(0, 1, -1, 1)
    private var fullDomain = SIMD4<Float>(0, 1, -1, 1)
    private var points: MTLBuffer?
    private var hierarchy: MTLBuffer?
    private var leaves = 0
    private var lastX: Float = 0
    private var dirtyRange: Range<Int>?
    private var engine: MetalEngine?
    private var setupError: Error?
    private var leafPipeline: MTLComputePipelineState?
    private var reducePipeline: MTLComputePipelineState?
    private var lodPipeline: MTLComputePipelineState?
    private var linePipeline: MTLRenderPipelineState?
    private var fillPipeline: MTLRenderPipelineState?
    private var compositePipeline: MTLRenderPipelineState?
    private var bloom: GlowBloomShader?
    private var scene: MTLTexture?
    private let inFlight = DispatchSemaphore(value: 3)
    private var frameIndex = 0
    private var uniformsBuffer: MTLBuffer?
    private var lodBuffers: [MTLBuffer] = []
    private var lodWidth = 0
    private var gestureDomain = SIMD4<Float>.zero
    private var lastUniforms = ChartUniforms()
    private var framesSinceReport = 0
    private var reportTime = CACurrentMediaTime()
    private var lastErrorDescription: String?
    private var loadRevision = 0

    init(frame: CGRect = .zero) {
        super.init(frame: frame, device: try? MetalEngine.shared.get().device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        autoResizeDrawable = true
        clearColor = MTLClearColorMake(0.025, 0.04, 0.05, 1)
        preferredFramesPerSecond = 120
        isPaused = true
        enableSetNeedsDisplay = false
        isOpaque = true
        layer.cornerRadius = 22
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityLabel = "График"
        accessibilityHint = "Панорамирование одним пальцем, масштабирование двумя пальцами."
        accessibilityIdentifier = "millionPointChart"
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        do {
            let engine = try MetalEngine.shared.get()
            self.engine = engine
            leafPipeline = try engine.compute("chartWriteLeaves")
            reducePipeline = try engine.compute("chartReduceLevel")
            lodPipeline = try engine.compute("chartPixelLOD")
            linePipeline = try engine.render(vertex: "chartLineVertex", fragment: "chartLineFragment", format: .rgba16Float)
            fillPipeline = try engine.render(vertex: "chartFillVertex", fragment: "chartFillFragment", format: .rgba16Float)
            compositePipeline = try engine.render(vertex: "engineFullscreenVertex", fragment: "chartComposite")
            bloom = try GlowBloomShader(engine: engine)
            uniformsBuffer = engine.device.makeBuffer(length: 256 * 3, options: .storageModeShared)
            guard uniformsBuffer != nil else { throw MetalEngineError.allocation }
        } catch { setupError = error }
        delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(updateActivity),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(suspendRendering),
            name: UIApplication.willResignActiveNotification, object: nil)
    }

    required init(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        preferredFramesPerSecond = min(120, window?.screen.maximumFramesPerSecond ?? 60)
        updateActivity()
    }

    @objc private func updateActivity() {
        isPaused = window == nil || UIApplication.shared.applicationState != .active || setupError != nil
        reportTime = CACurrentMediaTime()
        framesSinceReport = 0
        if let setupError { report(setupError) }
    }
    @objc private func suspendRendering() { isPaused = true }

    /// Validation, allocation and the initial copy run off the main actor. Replacing
    /// the dataset is safe: submitted Metal commands retain the old resources.
    func setPoints(_ input: [SIMD2<Float>], reserveCapacity: Int? = nil) async throws {
        loadRevision += 1
        let revision = loadRevision
        if let setupError { throw setupError }
        guard let device = engine?.device else { throw MetalEngineError.unavailable }
        let capacity = max(input.count, reserveCapacity ?? input.count)
        let task = Task.detached(priority: .userInitiated) {
            try Self.prepare(input, capacity: capacity, device: device)
        }
        let data = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        try Task.checkCancellation()
        guard revision == loadRevision else { throw CancellationError() }
        points = data.points
        hierarchy = data.hierarchy
        pointCount = data.count
        pointCapacity = data.capacity
        leaves = data.leaves
        fullDomain = data.domain
        visibleDomain = data.domain
        lastX = data.domain.y
        dirtyRange = 0..<leaves
        accessibilityValue = "\(pointCount) точек"
    }

    private nonisolated static func prepare(_ input: [SIMD2<Float>], capacity: Int,
                                           device: MTLDevice) throws -> PreparedChartData {
        guard input.count >= 2 else { throw MetalEngineError.invalidPoints }
        // Explicit bounded allocation rather than an unbounded next-power-of-two overflow.
        guard capacity >= input.count, capacity <= 4_194_304 else { throw MetalEngineError.capacity }
        var low = Float.infinity, high = -Float.infinity, previous = -Float.infinity
        for (index, point) in input.enumerated() {
            if index & 4095 == 0 { try Task.checkCancellation() }
            guard point.x.isFinite, point.y.isFinite, point.x >= previous else { throw MetalEngineError.invalidPoints }
            previous = point.x
            low = min(low, point.y); high = max(high, point.y)
        }
        guard input.last!.x > input.first!.x else { throw MetalEngineError.invalidPoints }
        var leaves = 1
        while leaves < capacity { leaves *= 2 }
        let byteCount = capacity * MemoryLayout<SIMD2<Float>>.stride
        guard byteCount <= device.maxBufferLength,
              let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let nodes = device.makeBuffer(length: leaves * 2 * MemoryLayout<ChartRangeNode>.stride, options: .storageModePrivate)
        else { throw MetalEngineError.allocation }
        input.withUnsafeBytes { bytes in buffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count) }
        buffer.label = "Chart / unified XY samples"
        nodes.label = "Chart / GPU min-max hierarchy"
        let padding = max((high - low) * 0.1, 0.01)
        return PreparedChartData(points: buffer, hierarchy: nodes, count: input.count,
            capacity: capacity, leaves: leaves, domain: SIMD4(input.first!.x, input.last!.x, low - padding, high + padding))
    }

    /// Append-only streaming writes exclusively into the unused tail. Earlier GPU
    /// submissions use the previous point count, so CPU and GPU never touch the same samples.
    /// Hierarchy updates execute on the shared serial GPU command queue, not on the CPU.
    func append(_ batch: [SIMD2<Float>], followLatest: Bool = true) throws {
        guard !batch.isEmpty else { return }
        guard let points, pointCount + batch.count <= pointCapacity else { throw MetalEngineError.capacity }
        var previous = lastX
        for point in batch {
            guard point.x.isFinite, point.y.isFinite, point.x >= previous else { throw MetalEngineError.invalidPoints }
            previous = point.x
        }
        let oldCount = pointCount, oldRight = fullDomain.y
        let oldBottom = fullDomain.z, oldTop = fullDomain.w
        for point in batch { fullDomain.z = min(fullDomain.z, point.y); fullDomain.w = max(fullDomain.w, point.y) }
        if visibleDomain.z == oldBottom && visibleDomain.w == oldTop {
            visibleDomain.z = fullDomain.z; visibleDomain.w = fullDomain.w
        }
        batch.withUnsafeBytes { bytes in
            points.contents().advanced(by: oldCount * MemoryLayout<SIMD2<Float>>.stride)
                .copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
        pointCount += batch.count
        lastX = previous
        fullDomain.y = previous
        let wasAtEnd = abs(visibleDomain.y - oldRight) < max(1, (visibleDomain.y - visibleDomain.x) * 0.001)
        if followLatest && wasAtEnd {
            let shift = previous - oldRight
            visibleDomain.x += shift; visibleDomain.y += shift
        }
        if let dirtyRange { self.dirtyRange = min(dirtyRange.lowerBound, oldCount)..<max(dirtyRange.upperBound, pointCount) }
        else { dirtyRange = oldCount..<pointCount }
        accessibilityValue = "\(pointCount) точек"
    }

    func resetViewport() { visibleDomain = fullDomain }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, !allowsVerticalPanning else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y)
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { gestureDomain = visibleDomain }
        guard gesture.state == .changed else { return }
        let translation = gesture.translation(in: self)
        let dx = Float(translation.x / max(bounds.width, 1)) * (gestureDomain.y - gestureDomain.x)
        let dy = allowsVerticalPanning ? Float(translation.y / max(bounds.height, 1)) * (gestureDomain.w - gestureDomain.z) : 0
        visibleDomain = gestureDomain + SIMD4(-dx, -dx, dy, dy)
        constrainDomain()
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { gestureDomain = visibleDomain }
        guard gesture.state == .changed else { return }
        let location = gesture.location(in: self)
        let anchor = SIMD2(Float(location.x / max(bounds.width, 1)), Float(1 - location.y / max(bounds.height, 1)))
        let oldSize = SIMD2(gestureDomain.y - gestureDomain.x, gestureDomain.w - gestureDomain.z)
        let center = SIMD2(gestureDomain.x, gestureDomain.z) + oldSize * anchor
        let size = oldSize / max(Float(gesture.scale), 0.001)
        let origin = center - size * anchor
        visibleDomain = SIMD4(origin.x, origin.x + size.x, origin.y, origin.y + size.y)
        constrainDomain()
    }

    private func constrainDomain() {
        let xWidth = min(max(visibleDomain.y - visibleDomain.x, max((fullDomain.y - fullDomain.x) / 100_000, 0.01)), fullDomain.y - fullDomain.x)
        let yHeight = min(max(visibleDomain.w - visibleDomain.z, (fullDomain.w - fullDomain.z) / 256), fullDomain.w - fullDomain.z)
        let x = min(max(visibleDomain.x, fullDomain.x), fullDomain.y - xWidth)
        let y = min(max(visibleDomain.z, fullDomain.z), fullDomain.w - yHeight)
        visibleDomain = SIMD4(x, x + xWidth, y, y + yHeight)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { /* allocated lazily by draw */ }

    private func resizeResources() throws {
        guard let engine else { throw MetalEngineError.unavailable }
        let width = max(1, Int(drawableSize.width)), height = max(1, Int(drawableSize.height))
        if lodWidth != width {
            let bytes = width * 2 * MemoryLayout<SIMD2<Float>>.stride
            let buffers = (0..<3).compactMap { _ in engine.device.makeBuffer(length: bytes, options: .storageModeShared) }
            guard buffers.count == 3 else { throw MetalEngineError.allocation }
            lodBuffers = buffers
            lodWidth = width
        }
        if scene?.width != width || scene?.height != height {
            scene = try engine.texture(width: width, height: height, format: .rgba16Float, usage: [.renderTarget, .shaderRead])
            try bloom?.resize(width: width, height: height)
        }
    }

    private func makeUniforms(width: Int) -> ChartUniforms {
        var u = ChartUniforms()
        u.projection = simd_float4x4(columns: (SIMD4(2, 0, 0, 0), SIMD4(0, 2, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(-1, -1, 0, 1)))
        let sx = 1 / max(visibleDomain.y - visibleDomain.x, 0.00001)
        let sy = 1 / max(visibleDomain.w - visibleDomain.z, 0.00001)
        u.view = simd_float4x4(columns: (SIMD4(sx, 0, 0, 0), SIMD4(0, sy, 0, 0), SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)))
        u.viewport = SIMD4(Float(drawableSize.width), Float(drawableSize.height), Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 3600)), bloomStrength)
        u.domain = visibleDomain
        u.counts = SIMD4(UInt32(pointCount), UInt32(leaves), UInt32(width * 2), 0)
        return u
    }

    private func encodeHierarchy(_ command: MTLCommandBuffer) throws {
        guard let dirtyRange, let points, let hierarchy, let leafPipeline, let reducePipeline else { return }
        guard let encoder = command.makeComputeCommandEncoder() else { throw MetalEngineError.allocation }
        encoder.label = "Chart / incremental hierarchy"
        var u = ChartReductionUniforms()
        u.range = SIMD4(UInt32(dirtyRange.lowerBound), UInt32(dirtyRange.upperBound), UInt32(leaves), UInt32(pointCount))
        encoder.setBuffer(hierarchy, offset: 0, index: 0)
        encoder.setBytes(&u, length: MemoryLayout<ChartReductionUniforms>.stride, index: 1)
        MetalEngine.dispatch(encoder, pipeline: leafPipeline, count: dirtyRange.count)
        encoder.memoryBarrier(scope: .buffers)
        var start = leaves + dirtyRange.lowerBound, end = leaves + dirtyRange.upperBound
        while start > 1 {
            start /= 2; end = (end + 1) / 2
            u.range = SIMD4(UInt32(start), UInt32(end), UInt32(leaves), UInt32(pointCount))
            encoder.setBuffer(points, offset: 0, index: 0)
            encoder.setBuffer(hierarchy, offset: 0, index: 1)
            encoder.setBytes(&u, length: MemoryLayout<ChartReductionUniforms>.stride, index: 2)
            MetalEngine.dispatch(encoder, pipeline: reducePipeline, count: end - start)
            encoder.memoryBarrier(scope: .buffers)
        }
        encoder.endEncoding()
    }

    private func encodeLOD(_ command: MTLCommandBuffer, output: MTLBuffer, uniforms: MTLBuffer, offset: Int, width: Int) throws {
        guard let points, let hierarchy, let lodPipeline, let encoder = command.makeComputeCommandEncoder() else {
            throw MetalEngineError.allocation
        }
        encoder.label = "Chart / per-pixel min-max LOD"
        encoder.setBuffer(points, offset: 0, index: 0)
        encoder.setBuffer(hierarchy, offset: 0, index: 1)
        encoder.setBuffer(output, offset: 0, index: 2)
        encoder.setBuffer(uniforms, offset: offset, index: 3)
        MetalEngine.dispatch(encoder, pipeline: lodPipeline, count: width)
        encoder.endEncoding()
    }

    func draw(in view: MTKView) {
        guard canRenderEngine else { reportTime = CACurrentMediaTime(); framesSinceReport = 0; return }
        guard pointCount >= 2, let engine, let uniformsBuffer,
              let linePipeline, let fillPipeline,
              inFlight.wait(timeout: .now()) == .success else { return }
        let cpuStart = CACurrentMediaTime()
        do {
            try resizeResources()
            guard let scene, let bloom, let drawable = currentDrawable, let command = engine.queue.makeCommandBuffer() else {
                inFlight.signal(); return
            }
            let slot = frameIndex % 3, offset = slot * 256, lod = lodBuffers[slot]
            var u = makeUniforms(width: lodWidth)
            withUnsafeBytes(of: &u) { uniformsBuffer.contents().advanced(by: offset).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            try encodeHierarchy(command)
            try encodeLOD(command, output: lod, uniforms: uniformsBuffer, offset: offset, width: lodWidth)
            guard let encoder = command.makeRenderCommandEncoder(descriptor: MetalEngine.pass(scene)) else { throw MetalEngineError.allocation }
            encoder.label = "Chart / triangle fill + line strip"
            encoder.setVertexBuffer(lod, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformsBuffer, offset: offset, index: 1)
            encoder.setRenderPipelineState(fillPipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: lodWidth * 4)
            encoder.setRenderPipelineState(linePipeline)
            encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: lodWidth * 2)
            encoder.endEncoding()
            try bloom.encode(command: command, source: scene)
            guard let composite = command.makeRenderCommandEncoder(descriptor: MetalEngine.pass(drawable.texture)) else { throw MetalEngineError.allocation }
            encodeComposite(composite, uniforms: u)
            composite.endEncoding()
            let now = CACurrentMediaTime(), cpuMS = (now - cpuStart) * 1000
            framesSinceReport += 1
            let elapsed = now - reportTime
            let shouldReport = elapsed >= 1
            let fps = Double(framesSinceReport) / max(elapsed, 0.001)
            let sampleCount = pointCount, vertices = lodWidth * 2, semaphore = inFlight
            command.addCompletedHandler { [weak self] completed in
                semaphore.signal()
                if let message = completed.error?.localizedDescription {
                    DispatchQueue.main.async { [weak self] in
                        self?.isPaused = true
                        self?.report(MetalEngineError.command(message))
                    }
                }
                if shouldReport {
                    let gpuMS = max(0, completed.gpuEndTime - completed.gpuStartTime) * 1000
                    DispatchQueue.main.async { [weak self] in
                        self?.onMetrics?(MetalChartMetrics(points: sampleCount, vertices: vertices,
                            renderedFramesPerSecond: fps, gpuMilliseconds: gpuMS, cpuEncodingMilliseconds: cpuMS))
                    }
                }
            }
            command.present(drawable)
            command.commit()
            dirtyRange = nil
            lastUniforms = u
            frameIndex += 1
            if shouldReport { framesSinceReport = 0; reportTime = now }
        } catch {
            inFlight.signal()
            isPaused = true
            report(error)
        }
    }

    private func encodeComposite(_ encoder: MTLRenderCommandEncoder, uniforms: ChartUniforms) {
        guard let compositePipeline, let scene, let blurred = bloom?.output else { return }
        var u = uniforms
        encoder.setRenderPipelineState(compositePipeline)
        encoder.setFragmentTexture(scene, index: 0)
        encoder.setFragmentTexture(blurred, index: 1)
        encoder.setFragmentBytes(&u, length: MemoryLayout<ChartUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    func metalSnapshot() -> UIImage? {
        guard let engine, scene != nil else { return nil }
        return MetalSnapshot.render(device: engine.device, queue: engine.queue, size: drawableSize) { encoder in
            encodeComposite(encoder, uniforms: lastUniforms)
        }
    }

    /// Blocking diagnostic readback, deliberately separate from the render loop.
    /// Useful for verifying that LOD preserves spikes and newly appended extrema.
    func diagnosticLOD(pixelWidth: Int) throws -> [SIMD2<Float>] {
        guard pixelWidth > 0, pixelWidth <= 8192, let engine, pointCount >= 2,
              let output = engine.device.makeBuffer(length: pixelWidth * 2 * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared),
              let uniform = engine.device.makeBuffer(length: MemoryLayout<ChartUniforms>.stride, options: .storageModeShared),
              let command = engine.queue.makeCommandBuffer() else { throw MetalEngineError.allocation }
        var u = makeUniforms(width: pixelWidth)
        withUnsafeBytes(of: &u) { uniform.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        try encodeHierarchy(command)
        try encodeLOD(command, output: output, uniforms: uniform, offset: 0, width: pixelWidth)
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { throw MetalEngineError.command(command.error?.localizedDescription ?? "GPU command failed") }
        dirtyRange = nil
        return Array(UnsafeBufferPointer(start: output.contents().bindMemory(to: SIMD2<Float>.self, capacity: pixelWidth * 2), count: pixelWidth * 2))
    }

    private func report(_ error: Error) {
        guard error.localizedDescription != lastErrorDescription else { return }
        lastErrorDescription = error.localizedDescription
        accessibilityValue = error.localizedDescription
        onError?(error)
    }
}

extension UIView {
    var canRenderEngine: Bool {
        guard let window, UIApplication.shared.applicationState == .active, !isHidden, alpha > 0 else { return false }
        var rect = convert(bounds, to: window)
        var ancestor = superview
        while let parent = ancestor {
            if parent.isHidden || parent.alpha <= 0 { return false }
            if parent.clipsToBounds { rect = rect.intersection(parent.convert(parent.bounds, to: window)) }
            ancestor = parent.superview
        }
        return !rect.isNull && !rect.isEmpty && rect.intersects(window.bounds)
    }
}
