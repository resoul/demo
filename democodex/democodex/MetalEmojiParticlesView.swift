import MetalKit
import Metal

enum EmojiParticleMode: UInt32, CaseIterable {
    case fire, rocket, hearts, mixed
    var title: String {
        switch self {
        case .fire: "🔥 Огонь"
        case .rocket: "🚀 Ракета"
        case .hearts: "❤️ Сердца"
        case .mixed: "🎲 Микс"
        }
    }
}

struct EmojiParticleState {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var angle: Float
    var angularVelocity: Float
    var age: Float
    var lifetime: Float
    var emojiIndex: UInt32
    var burstID: UInt32
    var size: Float
    var padding: Float = 0
}

struct EmojiPhysicsUniforms {
    var emitter: SIMD2<Float>
    var touch: SIMD2<Float>
    var deltaTime: Float
    var time: Float
    var aspect: Float
    var interaction: Float
    var count: UInt32
    var mode: UInt32
    var burstID: UInt32
    var atlasCount: UInt32
    var viewportSize: SIMD2<Float>
    var gravity: Float
    var repulsion: Float
    var spriteSize: Float
    var padding0: Float = 0
    var padding1: Float = 0
    var padding2: Float = 0
}

struct EmojiRenderUniforms {
    var resolution: SIMD2<Float>
    var spriteSize: Float
    var atlasCount: UInt32
    var count: UInt32
    var padding0: UInt32 = 0
    var padding1: UInt32 = 0
    var padding2: UInt32 = 0
}

/// Slots are released only after the CPU reads them, independent of GPU-frame
/// semaphore ordering. No in-flight GPU/CPU access to the same readback slot.
private final class EmojiCounterReadbacks: @unchecked Sendable {
    private let lock = NSLock()
    private let slots: [MTLBuffer]
    private var busy = [false, false, false]

    init(device: MTLDevice) throws {
        slots = try (0..<3).map { _ in
            guard let buffer = device.makeBuffer(length: 4, options: .storageModeShared) else { throw MetalLabError.allocation }
            return buffer
        }
    }

    func acquire() -> (Int, MTLBuffer)? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = busy.firstIndex(of: false) else { return nil }
        busy[index] = true
        return (index, slots[index])
    }

    func release(_ index: Int) {
        lock.lock()
        defer { lock.unlock() }
        busy[index] = false
    }
}

/// MTKView renderer using GPU physics and one six-vertex instanced draw call.
final class MetalEmojiParticlesView: MetalAnimationView {
    static let minimumCount = 1_000
    static let maximumCount = 200_000
    static let threadsPerGroup = 256
    var particleCount = 10_000 {
        didSet { particleCount = min(max(particleCount, Self.minimumCount), Self.maximumCount) }
    }
    var mode: EmojiParticleMode = .mixed
    var spriteSizePixels: Float = 32 {
        didSet { spriteSizePixels = spriteSizePixels.isFinite ? min(max(spriteSizePixels, 8), 64) : 32 }
    }
    override var vertexFunctionName: String { "emojiVertex" }
    override var fragmentFunctionName: String { "emojiFragment" }
    override var renderClearColor: MTLClearColor { MTLClearColorMake(0.018, 0.012, 0.04, 1) }
    private(set) var particleBuffer: MTLBuffer?
    private(set) var atlas: EmojiTextureAtlas?
    private var visibleCounter: MTLBuffer?
    private var simulationPipeline: MTLComputePipelineState?
    private var sampling: MTLSamplerState?
    private var readbacks: EmojiCounterReadbacks?
    private var previousSimulationTime: Float?
    private var hasEmitterInteraction = false
    private(set) var burstID: UInt32 = 0

    override func configurePipeline(_ descriptor: MTLRenderPipelineDescriptor) {
        let color = descriptor.colorAttachments[0]!
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    override func prepareResources(device: MTLDevice, library: MTLLibrary, queue: MTLCommandQueue) throws {
        guard let initialize = library.makeFunction(name: "initializeEmojiParticles"),
              let simulate = library.makeFunction(name: "simulateEmojiParticles") else { throw MetalLabError.missingFunction }
        let seedPipeline = try device.makeComputePipelineState(function: initialize)
        let physics = try device.makeComputePipelineState(function: simulate)
        guard physics.maxTotalThreadsPerThreadgroup >= Self.threadsPerGroup else { throw MetalLabError.encoder }
        simulationPipeline = physics
        atlas = try EmojiTextureProvider.atlas(for: device)
        guard let particles = device.makeBuffer(length: Self.maximumCount * MemoryLayout<EmojiParticleState>.stride, options: .storageModePrivate),
              let counter = device.makeBuffer(length: 4, options: .storageModePrivate),
              let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { throw MetalLabError.allocation }
        particleBuffer = particles
        particles.label = "200,000 emoji GPU states"
        visibleCounter = counter
        readbacks = try EmojiCounterReadbacks(device: device)
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear
        sampler.magFilter = .linear
        sampler.mipFilter = .linear
        sampler.sAddressMode = .clampToEdge
        sampler.tAddressMode = .clampToEdge
        guard let sampling = device.makeSamplerState(descriptor: sampler) else { throw MetalLabError.allocation }
        self.sampling = sampling
        var uniforms = physicsUniforms(time: 0, delta: 0, resolution: SIMD2(1000, 1000))
        uniforms.count = UInt32(Self.maximumCount)
        encoder.setComputePipelineState(seedPipeline)
        encoder.setBuffer(particles, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<EmojiPhysicsUniforms>.stride, index: 1)
        encoder.dispatchThreads(MTLSize(width: Self.maximumCount, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(256, seedPipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        assert(MemoryLayout<EmojiParticleState>.stride == 48)
        assert(MemoryLayout<EmojiPhysicsUniforms>.stride == 80)
        assert(MemoryLayout<EmojiRenderUniforms>.stride == 32)
    }

    override func animationDidStart() { previousSimulationTime = nil }
    override func animationDidStop() {
        previousSimulationTime = nil
        hasEmitterInteraction = false
    }

    override func interactionDidChange() {
        hasEmitterInteraction = true
        burstID &+= 1
    }

    private func physicsUniforms(time: Float, delta: Float, resolution: SIMD2<Float>) -> EmojiPhysicsUniforms {
        let point = SIMD2(Float(interactionPoint.x), Float(interactionPoint.y))
        return EmojiPhysicsUniforms(emitter: hasEmitterInteraction ? point : SIMD2(0.5, 0.88), touch: point,
                                    deltaTime: delta, time: time, aspect: resolution.x / max(resolution.y, 1),
                                    interaction: interactionStrength, count: UInt32(particleCount), mode: mode.rawValue,
                                    burstID: burstID, atlasCount: UInt32(atlas?.symbols.count ?? 5),
                                    viewportSize: resolution, gravity: 0.95, repulsion: 0.06, spriteSize: spriteSizePixels)
    }

    override func encodeSimulation(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) -> Bool {
        guard let simulationPipeline, let particleBuffer, let visibleCounter,
              let clear = commandBuffer.makeBlitCommandEncoder() else { return false }
        clear.fill(buffer: visibleCounter, range: 0..<4, value: 0)
        clear.endEncoding()
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        let delta = previousSimulationTime.map { uniforms.time - $0 } ?? (1 / 60)
        previousSimulationTime = uniforms.time
        var physics = physicsUniforms(time: uniforms.time, delta: min(max(delta, 0), 1 / 30), resolution: uniforms.resolution)
        encoder.setComputePipelineState(simulationPipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBytes(&physics, length: MemoryLayout<EmojiPhysicsUniforms>.stride, index: 1)
        encoder.setBuffer(visibleCounter, offset: 0, index: 2)
        encoder.dispatchThreadgroups(MTLSize(width: (particleCount + 255) / 256, height: 1, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: Self.threadsPerGroup, height: 1, depth: 1))
        encoder.endEncoding()
        return true
    }

    override func encodeRender(encoder: MTLRenderCommandEncoder, uniforms: inout EffectUniforms) {
        var render = EmojiRenderUniforms(resolution: uniforms.resolution, spriteSize: spriteSizePixels,
                                         atlasCount: UInt32(atlas?.symbols.count ?? 5), count: UInt32(particleCount))
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&render, length: MemoryLayout<EmojiRenderUniforms>.stride, index: 1)
        encoder.setFragmentTexture(atlas?.texture, index: 0)
        encoder.setFragmentSamplerState(sampling, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: particleCount)
    }

    override func encodePostRender(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) {
        guard let readbacks, let visibleCounter, let (slot, buffer) = readbacks.acquire() else { return }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { readbacks.release(slot); return }
        blit.copy(from: visibleCounter, sourceOffset: 0, to: buffer, destinationOffset: 0, size: 4)
        blit.endEncoding()
        let measurements = measurements
        let generation = measurements.generation
        commandBuffer.addCompletedHandler { command in
            defer { readbacks.release(slot) }
            guard command.status == .completed else { return }
            let visible = buffer.contents().load(as: UInt32.self)
            measurements.recordActiveEntities(Int(visible), generation: generation)
        }
    }
}
