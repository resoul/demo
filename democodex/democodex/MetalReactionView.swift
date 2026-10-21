import MetalKit

final class MetalReactionView: GPUExperimentView {
    override var vertexFunctionName: String { "experimentFullscreen" }
    override var fragmentFunctionName: String { "reactionFragment" }
    override var entityCount: Int { fields.first.map { $0.width * $0.height } ?? 0 }
    override var loadDescription: String { "\(Int((0.25 + load * 0.75)*100))% native screen · \(entityCount.formatted()) ячеек" }
    override var experimentDescription: String { "Gray–Scott · \(simulationSteps) шагов / кадр · 2 × RG32Float" }
    override var actionTitle: String { alternate ? "Узор: кораллы" : "Узор: лабиринт" }
    // Nine RG32Float reads + one RG32Float write per simulated cell/step.
    // Logical traffic, NOT measured physical DRAM traffic (cache reuse is substantial).
    override var logicalBytesPerFrame: Double { Double(entityCount) * Double(simulationSteps) * 80 }
    override var extraMetrics: String { "Оценка трафика: 80 B / ячейку / шаг; кеши и draw не вычитаются" }
    private var device: MTLDevice?
    private var fields: [MTLTexture] = []
    private var current = 0
    override func prepareResources(device: MTLDevice, library: MTLLibrary, queue: MTLCommandQueue) throws {
        self.device = device; simulationSteps = 10
        try makePipelines(["reactionSeed", "reactionStep"], device: device, library: library)
    }
    override func encodeSimulation(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) -> Bool {
        updateUniforms(uniforms)
        let scale = 0.25 + load * 0.75
        // Stress the complete native screen grid, even though UI occupies part of it.
        var extent = uniforms.resolution
        if let screen = window?.windowScene?.screen {
            let native = screen.nativeBounds.size
            let landscape = window?.windowScene?.interfaceOrientation.isLandscape == true
            extent = SIMD2(Float(landscape ? native.height : native.width),Float(landscape ? native.width : native.height))
        }
        let width = max(16, Int(extent.x * scale)), height = max(16, Int(extent.y * scale))
        if fields.first?.width != width || fields.first?.height != height {
            guard let device else { return false }
            do { fields = try (0..<2).map { _ in try texture(device, width: width, height: height, format: .rg32Float) }; needsReset = true }
            catch { return false }
        }
        u.width = UInt32(width); u.height = UInt32(height); u.count = UInt32(entityCount)
        let size = MTLSize(width: width, height: height, depth: 1)
        if needsReset {
            guard dispatch("reactionSeed", command: commandBuffer, size: size, textures: [fields[current]]) else { return false }
            needsReset = false
        }
        for _ in 0..<simulationSteps {
            guard dispatch("reactionStep", command: commandBuffer, size: size, textures: [fields[current], fields[1-current]]) else { return false }
            current = 1-current
        }
        return true
    }
    override func encodeRender(encoder: MTLRenderCommandEncoder, uniforms: inout EffectUniforms) {
        renderUniforms(encoder); encoder.setFragmentTexture(fields.first == nil ? nil : fields[current], index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
