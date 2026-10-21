import MetalKit

class MetalFluidFieldView: GPUExperimentView {
    var volumetric: Bool { true }
    var gridSide: Int { volumetric ? 24 + Int(load * 5) * 8 : 128 + Int(load * 7) * 64 }
    override var entityCount: Int { gridSide * gridSide * (volumetric ? gridSide : 1) }
    override var vertexFunctionName: String { "experimentFullscreen" }
    override var fragmentFunctionName: String { volumetric ? "volumeSmokeFragment" : "fluidInkFragment" }
    override var loadDescription: String { volumetric ? "\(gridSide)³ · \(entityCount.formatted()) вокселей" : "\(gridSide)² · \(entityCount.formatted()) ячеек" }
    override var experimentDescription: String { "Stable Fluids · advection → divergence → \(simulationSteps) Jacobi → projection" }
    override var actionTitle: String { volumetric ? (alternate ? "Остановить камеру" : "Вращать камеру") : (alternate ? "Обычная палитра" : "Сменить палитру") }
    override var extraMetrics: String { "\(simulationSteps + 3) проходов / кадр · \(volumetric ? "3D trilinear sampling" : "2D bilinear sampling")" }
    private var field: [MTLTexture] = []
    private var dye: [MTLTexture] = []
    private var pressure: [MTLTexture] = []
    private var divergence: MTLTexture?
    private var dyeIndex = 0
    private var allocatedSide = 0
    private var device: MTLDevice?
    private var prefix: String { volumetric ? "volume" : "ink" }

    override func prepareResources(device: MTLDevice, library: MTLLibrary, queue: MTLCommandQueue) throws {
        self.device = device
        simulationSteps = 12
        try makePipelines(["Clear", "Advect", "Divergence", "Jacobi", "Project"].map { prefix + $0 }, device: device, library: library)
    }
    override func encodeSimulation(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) -> Bool {
        updateUniforms(uniforms); u.side = UInt32(gridSide)
        let size = MTLSize(width: gridSide, height: gridSide, depth: volumetric ? gridSide : 1)
        if allocatedSide != gridSide {
            guard let device else { return false }
            do {
                let depth = volumetric ? gridSide : 1
                field = try (0..<2).map { _ in try texture(device, width: gridSide, height: gridSide, depth: depth) }
                dye = try (0..<2).map { _ in try texture(device, width: gridSide, height: gridSide, depth: depth) }
                pressure = try (0..<2).map { _ in try texture(device, width: gridSide, height: gridSide, depth: depth, format: .r16Float) }
                divergence = try texture(device, width: gridSide, height: gridSide, depth: depth, format: .r16Float)
                allocatedSide = gridSide; needsReset = true
            } catch { return false }
        }
        if needsReset {
            for i in 0..<2 {
                guard dispatch(prefix+"Clear", command: commandBuffer, size: size, textures: [field[i], dye[i], pressure[i]]) else { return false }
            }
            needsReset = false
        }
        guard dispatch(prefix+"Advect", command: commandBuffer, size: size, textures: [field[0], dye[dyeIndex], field[1], dye[1-dyeIndex]]),
              dispatch(prefix+"Divergence", command: commandBuffer, size: size, textures: [field[1], divergence]) else { return false }
        dyeIndex = 1-dyeIndex
        var index = 0
        for _ in 0..<simulationSteps {
            guard dispatch(prefix+"Jacobi", command: commandBuffer, size: size, textures: [pressure[index], divergence, pressure[1-index]]) else { return false }
            index = 1-index
        }
        if index == 1 { pressure.swapAt(0, 1) }
        return dispatch(prefix+"Project", command: commandBuffer, size: size, textures: [field[1], pressure[0], field[0]])
    }
    override func encodeRender(encoder: MTLRenderCommandEncoder, uniforms: inout EffectUniforms) {
        renderUniforms(encoder)
        encoder.setFragmentTexture(dye.isEmpty ? nil : dye[dyeIndex], index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
final class MetalInkView: MetalFluidFieldView {
    override var volumetric: Bool { false }
}
