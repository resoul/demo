import MetalKit

struct ParticleSimulationUniforms {
    var touch: SIMD2<Float>
    var deltaTime: Float
    var aspect: Float
    var count: UInt32
    var time: Float
    var force: Float
    var interaction: Float
}

enum MetalLabError: Error { case missingFunction, allocation, encoder }

final class MetalParticlesView: MetalAnimationView {
    static let minimumCount = 10_000
    static let maximumCount = 1_000_000
    var particleCount = 100_000 {
        didSet { particleCount = min(max(particleCount, Self.minimumCount), Self.maximumCount) }
    }
    var repelsTouch = false
    override var vertexFunctionName: String { "particlesVertex" }
    override var fragmentFunctionName: String { "particlesFragment" }
    private(set) var particleBuffer: MTLBuffer?
    private var simulationPipeline: MTLComputePipelineState?
    private var previousSimulationTime: Float?

    override func configurePipeline(_ descriptor: MTLRenderPipelineDescriptor) {
        let color = descriptor.colorAttachments[0]!
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .zero
    }

    override func prepareResources(device: MTLDevice, library: MTLLibrary, queue: MTLCommandQueue) throws {
        guard let initialize = library.makeFunction(name: "initializeParticles"),
              let simulate = library.makeFunction(name: "simulateParticles") else { throw MetalLabError.missingFunction }
        let seedPipeline = try device.makeComputePipelineState(function: initialize)
        simulationPipeline = try device.makeComputePipelineState(function: simulate)
        // One 16 MB GPU-private buffer, no per-frame CPU particle uploads.
        guard let buffer = device.makeBuffer(length: Self.maximumCount * MemoryLayout<SIMD4<Float>>.stride, options: .storageModePrivate),
              let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            throw MetalLabError.allocation
        }
        buffer.label = "1,000,000 particle positions + velocities"
        particleBuffer = buffer
        var count = UInt32(Self.maximumCount)
        encoder.setComputePipelineState(seedPipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.dispatchThreads(MTLSize(width: Self.maximumCount, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(256, seedPipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        encoder.endEncoding()
        command.commit() // Same queue guarantees initialization before simulation/render.
        assert(MemoryLayout<ParticleSimulationUniforms>.stride == 32)
    }

    override func animationDidStart() { previousSimulationTime = nil }

    override func encodeSimulation(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) -> Bool {
        guard let simulationPipeline, let particleBuffer, let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        let delta = previousSimulationTime.map { uniforms.time - $0 } ?? (1 / 60)
        previousSimulationTime = uniforms.time
        var simulation = ParticleSimulationUniforms(touch: uniforms.touch, deltaTime: min(max(delta, 0), 1 / 30),
                                                    aspect: uniforms.resolution.x / max(uniforms.resolution.y, 1),
                                                    count: UInt32(particleCount), time: uniforms.time,
                                                    force: repelsTouch ? -1 : 1, interaction: uniforms.interaction)
        encoder.setComputePipelineState(simulationPipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBytes(&simulation, length: MemoryLayout<ParticleSimulationUniforms>.stride, index: 1)
        encoder.dispatchThreads(MTLSize(width: particleCount, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(256, simulationPipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        encoder.endEncoding()
        return true
    }

    override func encodeRender(encoder: MTLRenderCommandEncoder, uniforms: inout EffectUniforms) {
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        // Brightness adapts to density; vertex/compute counts remain exactly N.
        uniforms.progress = Float(particleCount) / Float(Self.maximumCount)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<EffectUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
    }
}
