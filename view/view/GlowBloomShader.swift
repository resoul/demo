import Metal

/// Two separable Gaussian compute passes over a half-resolution HDR texture.
final class GlowBloomShader {
    private let engine: MetalEngine
    private let horizontal: MTLComputePipelineState
    private let vertical: MTLComputePipelineState
    private var ping: MTLTexture?
    private(set) var output: MTLTexture?

    init(engine: MetalEngine) throws {
        self.engine = engine
        horizontal = try engine.compute("bloomHorizontal")
        vertical = try engine.compute("bloomVertical")
    }

    func resize(width: Int, height: Int) throws {
        let w = max(1, width / 2), h = max(1, height / 2)
        guard ping?.width != w || ping?.height != h else { return }
        ping = try engine.texture(width: w, height: h, format: .rgba16Float, usage: [.shaderRead, .shaderWrite])
        output = try engine.texture(width: w, height: h, format: .rgba16Float, usage: [.shaderRead, .shaderWrite])
    }

    func encode(command: MTLCommandBuffer, source: MTLTexture) throws {
        guard let ping, let output else { throw MetalEngineError.allocation }
        for (pipeline, input, target) in [(horizontal, source, ping), (vertical, ping, output)] {
            guard let encoder = command.makeComputeCommandEncoder() else { throw MetalEngineError.allocation }
            encoder.label = pipeline === horizontal ? "Bloom / horizontal" : "Bloom / vertical"
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(input, index: 0)
            encoder.setTexture(target, index: 1)
            encoder.dispatchThreads(MTLSize(width: target.width, height: target.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            encoder.endEncoding()
        }
    }
}
