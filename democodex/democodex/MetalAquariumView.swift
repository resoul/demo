import MetalKit
import CoreMotion

/// Counting-sort spatial grid: histogram -> parallel prefix sum -> scatter -> neighbors.
/// Positions are ping-ponged; no thread reads a neighbor being updated in place.
class MetalAquariumView: GPUExperimentView {
    var stressRange = false { didSet { needsReset = true } }
    var isFlock: Bool { false }
    override var entityCount: Int {
        let maximum = isFlock ? 32_768 : (stressRange ? 100_000 : 16_384)
        if load >= 1 { return maximum }
        return 1_024 + Int(load * Float(maximum - 1_024)) / 256 * 256
    }
    override var vertexFunctionName: String { "neighborVertex" }
    override var fragmentFunctionName: String { "neighborFragment" }
    override var loadDescription: String { "\(entityCount.formatted()) \(isFlock ? "агентов" : "частиц SPH")" }
    override var experimentDescription: String { isFlock ? "Boids · separation / alignment / cohesion · GPU grid" : "SPH · плотность / давление / вязкость · GPU counting sort" }
    override var actionTitle: String { isFlock ? (alternate ? "Притягивать" : "Отпугивать") : (alternate ? "Вернуть перегородку" : "Убрать перегородку") }
    var motionEnabled = false { didSet { updateMotion() } }
    var motionAvailable: Bool { motion.isDeviceMotionAvailable && !isFlock }
    private let motion = CMMotionManager()
    private var states: [MTLBuffer] = []
    private var counts: MTLBuffer!
    private var cursors: MTLBuffer!
    private var prefix: [MTLBuffer] = []
    private var sorted: MTLBuffer!
    private var density: MTLBuffer!
    private var current = 0

    override func prepareResources(device: MTLDevice, library: MTLLibrary, queue: MTLCommandQueue) throws {
        try makePipelines(["neighborSeed", "gridClear", "gridHistogram", "gridScan", "gridScatter", "sphDensity", "sphIntegrate", "boidsIntegrate"], device: device, library: library)
        states = try (0..<2).map { try buffer(device, bytes: 100_000 * 32, label: "SPH / boids state \($0)") }
        counts = try buffer(device, bytes: 128 * 128 * 4, label: "Grid histogram")
        cursors = try buffer(device, bytes: 128 * 128 * 4, label: "Grid cursors")
        prefix = try (0..<2).map { try buffer(device, bytes: 128 * 128 * 4, label: "Grid prefix \($0)") }
        sorted = try buffer(device, bytes: 100_000 * 4, label: "Particle IDs sorted by cell")
        density = try buffer(device, bytes: 100_000 * 8, label: "SPH density + pressure")
    }

    override func animationDidStart() { super.animationDidStart(); updateMotion() }
    override func animationDidStop() { motion.stopDeviceMotionUpdates() }
    private func updateMotion() {
        if motionEnabled, motionAvailable, isAnimating, window != nil {
            motion.deviceMotionUpdateInterval = 1 / 30
            if !motion.isDeviceMotionActive { motion.startDeviceMotionUpdates() }
        } else { motion.stopDeviceMotionUpdates() }
    }

    override func encodeSimulation(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) -> Bool {
        updateUniforms(uniforms)
        u.side = isFlock ? 32 : UInt32(min(128, max(16, Int(sqrt(Float(entityCount)) / 2.6))))
        if isFlock { u.flags |= 4 }
        if motionEnabled, let g = motion.deviceMotion?.gravity {
            switch window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: u.gravity = SIMD2(-Float(g.y), Float(g.x))
            case .landscapeRight: u.gravity = SIMD2(Float(g.y), -Float(g.x))
            case .portraitUpsideDown: u.gravity = SIMD2(-Float(g.x), -Float(g.y))
            default: u.gravity = SIMD2(Float(g.x), Float(g.y))
            }
        } else { u.gravity = SIMD2(0, -1) }
        let n = MTLSize(width: entityCount, height: 1, depth: 1)
        let cells = Int(u.side * u.side)
        let grid = MTLSize(width: cells, height: 1, depth: 1)
        if needsReset {
            guard dispatch("neighborSeed", command: commandBuffer, size: n, buffers: [states[current]]) else { return false }
            needsReset = false
        }
        let substeps = isFlock ? 1 : 2
        u.dt /= Float(substeps)
        for _ in 0..<substeps {
            guard dispatch("gridClear", command: commandBuffer, size: grid, buffers: [counts, cursors]),
                  dispatch("gridHistogram", command: commandBuffer, size: n, buffers: [states[current], counts]),
                  dispatch("gridScan", command: commandBuffer, size: grid, buffers: [counts, prefix[0]], scalar: 0) else { return false }
            var index = 0
            var stride: UInt32 = 1
            while stride < cells {
                guard dispatch("gridScan", command: commandBuffer, size: grid, buffers: [prefix[index], prefix[1 - index]], scalar: stride) else { return false }
                index = 1 - index
                stride *= 2
            }
            guard dispatch("gridScatter", command: commandBuffer, size: n, buffers: [states[current], counts, prefix[index], cursors, sorted]) else { return false }
            if !isFlock {
                guard dispatch("sphDensity", command: commandBuffer, size: n, buffers: [states[current], counts, prefix[index], sorted, density]) else { return false }
            }
            guard dispatch(isFlock ? "boidsIntegrate" : "sphIntegrate", command: commandBuffer, size: n,
                           buffers: [states[current], counts, prefix[index], sorted, density, states[1 - current]]) else { return false }
            current = 1 - current
        }
        return true
    }

    override func configurePipeline(_ descriptor: MTLRenderPipelineDescriptor) {
        let color = descriptor.colorAttachments[0]!
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .sourceAlpha
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
    }
    override func encodeRender(encoder: MTLRenderCommandEncoder, uniforms: inout EffectUniforms) {
        renderUniforms(encoder)
        encoder.setVertexBuffer(states[current], offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: entityCount + (!isFlock && !alternate ? 1 : 0))
    }
}

final class MetalBoidsView: MetalAquariumView {
    override var isFlock: Bool { true }
}
