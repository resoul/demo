import MetalKit

final class MetalNBodyView: GPUExperimentView {
    override var entityCount: Int { [512, 1_024, 2_048, 4_096, 8_192, 16_384, 32_768, 65_536][min(7, Int(load*7.999))] }
    override var vertexFunctionName: String { "nbodyVertex" }
    override var fragmentFunctionName: String { "nbodyFragment" }
    override var loadDescription: String { "N = \(entityCount.formatted()) · \((entityCount*entityCount).formatted()) пар / шаг" }
    override var experimentDescription: String { "Слева CPU SIMD + все ядра · справа GPU threadgroup tiling" }
    override var actionTitle: String { alternate ? "Включить CPU" : "Приостановить CPU" }
    override var operationsPerFrame: Double { Double(entityCount) * Double(entityCount) * 20 }
    override var extraMetrics: String {
        let cpu = cpuSeconds.map { String(format: "CPU step %.2f ms · ≈%.2f GFLOPS", $0*1_000, operationsPerFrame/$0/1e9) } ?? "CPU: первый шаг…"
        return cpu + "\nCPU шаг \(cpuStep) / GPU отправлено \(gpuStep) · dt=1/120 · ≈20 FLOP/пару"
    }
    private(set) var cpuSeconds: Double?
    private(set) var cpuStep = 0
    private(set) var gpuStep = 0
    private var states: [MTLBuffer] = []
    private var cpuBuffer: MTLBuffer?
    private var current = 0
    private let worker = NBodyCPUWorker()
    private var device: MTLDevice?
    private var uploadedCount = 0

    override func prepareResources(device: MTLDevice, library: MTLLibrary, queue: MTLCommandQueue) throws {
        self.device = device
        load = 0.14
        try makePipelines(["nbodySeed", "nbodyStep"], device: device, library: library)
        states = try (0..<2).map { try buffer(device, bytes: 65_536*32, label: "N-body state \($0)") }
    }
    override func animationDidStop() { worker.cancel() }
    override func performAction() {
        super.performAction()
        if alternate { worker.cancel() }
    }
    override func encodeSimulation(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) -> Bool {
        updateUniforms(uniforms); u.dt = 1 / 120
        let size = MTLSize(width: entityCount, height: 1, depth: 1)
        if needsReset {
            worker.reset(count: entityCount)
            cpuStep = 0; gpuStep = 0; cpuSeconds = nil
            let initial = (0..<entityCount).map { NBodyState.initial($0, count: entityCount) }
            cpuBuffer = initial.withUnsafeBytes { bytes in device?.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared) }
            // A common bit-identical initial upload avoids CPU/GPU trigonometry differences.
            guard let cpuBuffer, let copy = commandBuffer.makeBlitCommandEncoder() else { return false }
            copy.copy(from: cpuBuffer,sourceOffset: 0,to: states[current],destinationOffset: 0,size: entityCount*32)
            copy.endEncoding()
            uploadedCount = entityCount; needsReset = false
        }
        if let result = worker.takeResult(), result.states.count == entityCount {
            // Each completed CPU step gets a new immutable upload. Submitted GPU draws retain it.
            cpuBuffer = result.states.withUnsafeBytes { bytes in device?.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared) }
            cpuSeconds = result.seconds; cpuStep = result.step
        }
        if !alternate { worker.requestStep() }
        guard dispatch("nbodyStep", command: commandBuffer, size: size, buffers: [states[current], states[1-current]]) else { return false }
        current = 1-current; gpuStep += 1
        return true
    }
    override func configurePipeline(_ descriptor: MTLRenderPipelineDescriptor) {
        let color = descriptor.colorAttachments[0]!
        color.isBlendingEnabled = true; color.sourceRGBBlendFactor = .one; color.destinationRGBBlendFactor = .one
    }
    override func encodeRender(encoder: MTLRenderCommandEncoder, uniforms: inout EffectUniforms) {
        renderUniforms(encoder)
        for panel: UInt32 in 0..<2 {
            var panel = panel
            encoder.setVertexBytes(&panel, length: 4, index: 9)
            encoder.setVertexBuffer(panel == 0 ? cpuBuffer : states[current], offset: 0, index: 0)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: panel == 0 ? uploadedCount : entityCount)
        }
    }
}
