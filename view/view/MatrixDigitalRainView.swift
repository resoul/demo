import UIKit
import MetalKit

final class MatrixDigitalRainView: MTKView, MTKViewDelegate, MetalSnapshotProviding {
    var speed: Float = 12
    var intensity: Float = 0.9
    private var engine: MetalEngine?
    private var pipeline: MTLRenderPipelineState?
    private var atlas: MTLTexture?
    private var uniformBuffer: MTLBuffer?
    private var lastUniforms = RainUniforms()
    private let inFlight = DispatchSemaphore(value: 3)
    private var slot = 0
    private var time: Float = 0
    private var previousTime: CFTimeInterval?
    private var staticFrameNeeded = true
    private var failure: String?

    init(frame: CGRect = .zero) {
        super.init(frame: frame, device: try? MetalEngine.shared.get().device)
        colorPixelFormat = .bgra8Unorm
        preferredFramesPerSecond = 120
        isPaused = true
        layer.cornerRadius = 22
        clipsToBounds = true
        clearColor = MTLClearColorMake(0.008, 0.025, 0.018, 1)
        isAccessibilityElement = true
        accessibilityLabel = "Цифровой дождь. Зелёные колонки символов."
        accessibilityIdentifier = "matrixDigitalRain"
        do {
            let engine = try MetalEngine.shared.get()
            self.engine = engine
            pipeline = try engine.render(vertex: "matrixRainVertex", fragment: "matrixRainFragment")
            atlas = try Self.makeAtlas(engine: engine)
            uniformBuffer = engine.device.makeBuffer(length: 256 * 3, options: .storageModeShared)
            guard uniformBuffer != nil else { throw MetalEngineError.allocation }
            accessibilityValue = "Атлас готов: 96 глифов"
        } catch {
            failure = error.localizedDescription
            accessibilityValue = "Ошибка атласа: " + error.localizedDescription
            let label = UILabel()
            label.text = failure
            label.numberOfLines = 0
            label.textColor = .white
            label.frame = CGRect(x: 16, y: 16, width: 250, height: 90)
            addSubview(label)
        }
        delegate = self
        for name in [UIApplication.didBecomeActiveNotification, UIAccessibility.reduceMotionStatusDidChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(updateActivity), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(suspend), name: UIApplication.willResignActiveNotification, object: nil)
    }

    required init(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        preferredFramesPerSecond = min(120, window?.screen.maximumFramesPerSecond ?? 60)
        updateActivity()
    }
    @objc private func updateActivity() {
        previousTime = nil
        staticFrameNeeded = true
        isPaused = window == nil || UIApplication.shared.applicationState != .active || failure != nil
    }
    @objc private func suspend() { isPaused = true; previousTime = nil }

    private static func makeAtlas(engine: MetalEngine) throws -> MTLTexture {
        let glyphs = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ<>/{}[]#@アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン")
        // UIKit can optimize a monochrome glyph image to a CGImage format that
        // MTKTextureLoader cannot decode. Explicit RGBA8 avoids that decoder entirely.
        let width = 512, height = 192
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            defer { UIGraphicsPopContext() }
            for index in 0..<96 {
                let glyph = String(glyphs[index % glyphs.count]) as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 23, weight: .medium), .foregroundColor: UIColor.white]
                let size = glyph.size(withAttributes: attributes)
                glyph.draw(at: CGPoint(x: CGFloat(index % 16) * 32 + (32 - size.width) / 2,
                                      y: CGFloat(index / 16) * 32 + (32 - size.height) / 2), withAttributes: attributes)
            }
            return true
        }
        guard drawn, stride(from: 3, to: pixels.count, by: 4).contains(where: { pixels[$0] > 0 }) else {
            throw MetalEngineError.command("Не удалось нарисовать атлас символов")
        }
        let texture = try engine.texture(width: width, height: height, format: .rgba8Unorm,
            usage: .shaderRead, storage: .shared)
        pixels.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        return texture
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { staticFrameNeeded = true }

    private func uniforms() -> RainUniforms {
        let scale = drawableSize.width / max(bounds.width, 1)
        let cell = SIMD2(Float(17 * scale), Float(23 * scale))
        var u = RainUniforms()
        u.viewport = SIMD4(Float(drawableSize.width), Float(drawableSize.height), time, speed)
        u.atlas = SIMD4(16, 6, 96, UInt32(max(1, ceil(drawableSize.width / CGFloat(cell.x)))))
        u.appearance = SIMD4(cell.x, cell.y, 13, intensity)
        return u
    }

    private func encode(_ encoder: MTLRenderCommandEncoder, uniforms: RainUniforms, offset: Int? = nil) {
        guard let pipeline, let atlas else { return }
        var u = uniforms
        encoder.setRenderPipelineState(pipeline)
        if let offset, let uniformBuffer { encoder.setVertexBuffer(uniformBuffer, offset: offset, index: 0) }
        else { encoder.setVertexBytes(&u, length: MemoryLayout<RainUniforms>.stride, index: 0) }
        encoder.setFragmentTexture(atlas, index: 0)
        let rows = Int(ceil(u.viewport.y / u.appearance.y))
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: Int(u.atlas.w) * rows)
    }

    func draw(in view: MTKView) {
        guard canRenderEngine, let engine, let uniformBuffer,
              !UIAccessibility.isReduceMotionEnabled || staticFrameNeeded else { previousTime = nil; return }
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = currentDrawable, let command = engine.queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: MetalEngine.pass(drawable.texture, clear: clearColor)) else {
            inFlight.signal(); return
        }
        let now = CACurrentMediaTime()
        if !UIAccessibility.isReduceMotionEnabled { time += Float(min(now - (previousTime ?? now), 0.05)) }
        previousTime = now
        var u = uniforms()
        let offset = slot % 3 * 256
        withUnsafeBytes(of: &u) { uniformBuffer.contents().advanced(by: offset).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        encode(encoder, uniforms: u, offset: offset)
        encoder.endEncoding()
        let semaphore = inFlight
        command.addCompletedHandler { _ in semaphore.signal() }
        command.present(drawable)
        command.commit()
        slot += 1
        lastUniforms = u
        staticFrameNeeded = false
    }

    func metalSnapshot() -> UIImage? {
        guard let engine else { return nil }
        let u = lastUniforms.atlas.w > 0 ? lastUniforms : uniforms()
        return MetalSnapshot.render(device: engine.device, queue: engine.queue, size: drawableSize) { encode($0, uniforms: u) }
    }
}

/// Reuses the CAMetalLayer fluid renderer and its shared, lifecycle-aware Core Motion clock.
final class FluidMeshGradientView: MetalEffectView {
    init(intensity: Float = 0.8) {
        super.init(effect: .fluid)
        self.intensity = intensity
        accessibilityLabel = "Живой жидкий градиент"
        accessibilityHint = "Проведите пальцем или наклоните устройство."
        accessibilityIdentifier = "fluidMeshGradient"
    }
    required init?(coder: NSCoder) { fatalError("Use init(intensity:)") }
}
