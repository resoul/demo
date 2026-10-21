import MetalKit

/// Identical 64-byte layout in ExperimentTypes.h. All simulations use normalized input.
struct ExperimentUniforms {
    var resolution: SIMD2<Float> = .zero
    var touch: SIMD2<Float> = SIMD2(0.5, 0.5)
    var gravity: SIMD2<Float> = SIMD2(0, -1)
    var time: Float = 0
    var dt: Float = 1 / 120
    var count: UInt32 = 0
    var side: UInt32 = 64
    var steps: UInt32 = 1
    var flags: UInt32 = 0
    var parameter: Float = 0.5
    var aspect: Float = 1
    var width: UInt32 = 0
    var height: UInt32 = 0
}

class GPUExperimentView: MetalAnimationView {
    var load: Float = 0.35 { didSet { load = load.isFinite ? min(max(load, 0), 1) : 0; needsReset = true } }
    var simulationSteps: Int = 1
    var alternate = false
    var needsReset = true
    var entityCount: Int { 0 }
    var loadDescription: String { "" }
    var experimentDescription: String { "" }
    var actionTitle: String { "Изменить режим" }
    var actionAvailable: Bool { true }
    var extraMetrics: String { "" }
    var operationsPerFrame: Double { 0 }
    var logicalBytesPerFrame: Double { 0 }
    let throughput = ExperimentThroughput()
    var u = ExperimentUniforms()
    private var previousTime: Float?
    var compute: [String: MTLComputePipelineState] = [:]

    func resetSimulation() { needsReset = true; previousTime = nil }
    func performAction() { alternate.toggle() }
    override func animationDidStart() { previousTime = nil }

    func updateUniforms(_ effect: EffectUniforms) {
        u.resolution = effect.resolution
        u.touch = SIMD2(effect.touch.x, 1 - effect.touch.y)
        u.time = effect.time
        u.dt = min(max(previousTime.map { effect.time - $0 } ?? (1 / 60), 0.001), 1 / 30)
        previousTime = effect.time
        u.aspect = effect.resolution.x / max(effect.resolution.y, 1)
        u.parameter = load
        u.count = UInt32(entityCount)
        u.steps = UInt32(simulationSteps)
        u.flags = (alternate ? 1 : 0) | (effect.interaction > 0.2 ? 2 : 0)
    }

    func makePipelines(_ names: [String], device: MTLDevice, library: MTLLibrary) throws {
        for name in names {
            guard let function = library.makeFunction(name: name) else { throw MetalLabError.missingFunction }
            compute[name] = try device.makeComputePipelineState(function: function)
        }
    }

    @discardableResult
    func dispatch(_ name: String, command: MTLCommandBuffer, size: MTLSize,
                  buffers: [MTLBuffer?] = [], textures: [MTLTexture?] = [], scalar: UInt32 = 0) -> Bool {
        guard let pipeline = compute[name], let encoder = command.makeComputeCommandEncoder() else { return false }
        encoder.label = name
        encoder.setComputePipelineState(pipeline)
        for (index, buffer) in buffers.enumerated() { encoder.setBuffer(buffer, offset: 0, index: index) }
        for (index, texture) in textures.enumerated() { encoder.setTexture(texture, index: index) }
        var uniforms = u
        var scalar = scalar
        encoder.setBytes(&uniforms, length: MemoryLayout<ExperimentUniforms>.stride, index: 8)
        encoder.setBytes(&scalar, length: 4, index: 9)
        let group: MTLSize
        if size.depth > 1 { group = MTLSize(width: 4, height: 4, depth: 4) }
        else if size.height > 1 { group = MTLSize(width: 8, height: 8, depth: 1) }
        else { group = MTLSize(width: min(256, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1) }
        // Full threadgroups also support kernels with threadgroup barriers (N-body).
        encoder.dispatchThreadgroups(MTLSize(width: (size.width + group.width - 1) / group.width,
                                            height: (size.height + group.height - 1) / group.height,
                                            depth: (size.depth + group.depth - 1) / group.depth), threadsPerThreadgroup: group)
        encoder.endEncoding()
        return true
    }

    func buffer(_ device: MTLDevice, bytes: Int, label: String) throws -> MTLBuffer {
        guard let result = device.makeBuffer(length: max(bytes, 16), options: .storageModePrivate) else { throw MetalLabError.allocation }
        result.label = label
        return result
    }

    func texture(_ device: MTLDevice, width: Int, height: Int, depth: Int = 1,
                 format: MTLPixelFormat = .rgba16Float) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = depth == 1 ? .type2D : .type3D
        descriptor.width = width; descriptor.height = height; descriptor.depth = depth
        descriptor.pixelFormat = format
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw MetalLabError.allocation }
        return texture
    }

    func renderUniforms(_ encoder: MTLRenderCommandEncoder) {
        var uniforms = u
        encoder.setVertexBytes(&uniforms, length: 64, index: 8)
        encoder.setFragmentBytes(&uniforms, length: 64, index: 8)
    }

    override func encodePostRender(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) {
        let operations = operationsPerFrame, bytes = logicalBytesPerFrame
        let meter = throughput, generation = measurements.generation
        let measurements = measurements
        commandBuffer.addCompletedHandler { command in
            guard command.status == .completed, generation == measurements.generation,
                  command.gpuStartTime > 0, command.gpuEndTime > command.gpuStartTime else { return }
            meter.record(operations: operations, bytes: bytes, seconds: command.gpuEndTime-command.gpuStartTime)
        }
    }
}

final class ExperimentThroughput: @unchecked Sendable {
    private let lock = NSLock()
    private var operations = 0.0, bytes = 0.0, seconds = 0.0
    func record(operations: Double, bytes: Double, seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        self.operations += operations; self.bytes += bytes; self.seconds += seconds
    }
    func drain() -> (gflops: Double?, gbps: Double?) {
        lock.lock(); defer { lock.unlock() }
        defer { operations = 0; bytes = 0; seconds = 0 }
        return (seconds > 0 && operations > 0 ? operations / seconds / 1e9 : nil,
                seconds > 0 && bytes > 0 ? bytes / seconds / 1e9 : nil)
    }
}
