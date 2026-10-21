import MetalKit

final class MetalClothView: GPUExperimentView {
    var side: Int { 32 + Int(load * 4) * 24 }
    override var entityCount: Int { side * side }
    override var vertexFunctionName: String { "clothVertex" }
    override var fragmentFunctionName: String { "clothFragment" }
    override var loadDescription: String { "\(side) × \(side) · \(entityCount.formatted()) узлов" }
    override var experimentDescription: String { "Position-based dynamics · \(simulationSteps) итераций ограничений" }
    override var actionTitle: String { alternate ? "Режим: тянуть" : "Режим: разрывать" }
    private var states: [MTLBuffer] = []
    private var old: MTLBuffer!
    private var current = 0
    override func prepareResources(device: MTLDevice, library: MTLLibrary, queue: MTLCommandQueue) throws {
        simulationSteps = 8
        try makePipelines(["clothSeed", "clothPredict", "clothRelax", "clothVelocity"], device: device, library: library)
        states = try (0..<2).map { try buffer(device, bytes: 128 * 128 * 32, label: "Cloth positions \($0)") }
        old = try buffer(device, bytes: 128 * 128 * 32, label: "Cloth previous positions")
    }
    override func encodeSimulation(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) -> Bool {
        updateUniforms(uniforms); u.side = UInt32(side)
        let size = MTLSize(width: entityCount, height: 1, depth: 1)
        if needsReset {
            guard dispatch("clothSeed", command: commandBuffer, size: size, buffers: [states[current]]) else { return false }
            needsReset = false
        }
        guard dispatch("clothPredict", command: commandBuffer, size: size, buffers: [states[current], states[1-current], old]) else { return false }
        current = 1-current
        for _ in 0..<simulationSteps {
            guard dispatch("clothRelax", command: commandBuffer, size: size, buffers: [states[current], states[1-current]]) else { return false }
            current = 1-current
        }
        return dispatch("clothVelocity", command: commandBuffer, size: size, buffers: [states[current], old])
    }
    override func encodeRender(encoder: MTLRenderCommandEncoder, uniforms: inout EffectUniforms) {
        renderUniforms(encoder)
        encoder.setVertexBuffer(states[current], offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: (side-1)*(side-1)*6)
    }
}
