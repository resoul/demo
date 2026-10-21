//
//  NBodyView.swift
//  demo
//

import UIKit
import Metal
import os
import Accelerate

/// Mirrors `NBodyParams` in NBody.metal (48 bytes).
nonisolated struct NBodyParams {
    var count: UInt32
    var deltaTime: Float
    var softening2: Float
    var gravity: Float
    var attractor: SIMD2<Float>
    var attractorMass: Float
    var pointSize: Float
    var viewScale: SIMD2<Float>
    var brightness: Float
    var galaxySplit: UInt32
}

/// Two colliding galaxies with direct O(n²) gravity, simulated either by a tiled compute kernel or
/// by the same algorithm on every CPU core. The CPU runs on a background thread, so the UI stays
/// responsive and the difference shows up as simulation steps per second.
final class NBodyView: MetalAnimationView, MetalLabEffectView {
    enum Engine: Int {
        case gpu
        case cpu
    }

    static let countRange: ClosedRange<Float> = 1_024...65_536
    /// Flops per interaction by the usual N-body convention (GPU Gems 3, ch. 31).
    private static let flopsPerInteraction = 20.0
    private static let stepTime: Float = 0.0035
    private static let ringSize = 3

    private var bodyCount = 8_192
    /// Launch argument `-nbodyEngine 1` starts on the CPU.
    private var engine: Engine = Engine(rawValue: UserDefaults.standard.integer(forKey: "nbodyEngine")) ?? .gpu

    private let stepPipeline = MetalEffectContext.shared?.computePipeline(function: "nbody_step")
    private let renderPipeline = MetalEffectContext.shared?.renderPipeline(
        vertex: "nbody_vertex",
        fragment: "nbody_fragment",
        blending: .additive
    )
    /// Shared memory, so the CPU engine can read and write the same bodies the GPU draws.
    private let ring: [MTLBuffer] = (0..<ringSize).compactMap { _ in
        MetalEffectContext.shared?.device.makeBuffer(
            length: Int(countRange.upperBound) * MemoryLayout<SIMD4<Float>>.stride,
            options: .storageModeShared
        )
    }
    private var current = 0
    private var needsReset = true
    private var lastCommandBuffer: MTLCommandBuffer?
    private let cpu = CPUNBodySimulator()
    private var cpuVersion = 0
    private var stepRate = StepRate()
    private var attractor: SIMD2<Float> = .zero
    private var attractorMass: Float = 0

    var activeEntityDescription: String {
        "\(bodyCount.formatted()) тел · \(engine == .gpu ? "GPU" : "CPU")"
    }

    var throughputDescription: String? {
        let steps = stepRate.stepsPerSecond
        let interactions = Double(bodyCount) * Double(bodyCount) * steps
        let gflops = interactions * Self.flopsPerInteraction / 1e9
        return String(format: steps < 10 ? "%.1f GFLOPS · %.2f шаг/с" : "%.0f GFLOPS · %.0f шаг/с", gflops, steps)
    }

    var controls: [LabControl] {
        [
            .segments(items: ["GPU · compute", "CPU · Accelerate"], selected: engine.rawValue) { [weak self] index in
                self?.switchEngine(to: Engine(rawValue: index) ?? .gpu)
            },
            .slider(
                title: "Тел",
                range: Self.countRange,
                value: Float(bodyCount),
                isLogarithmic: true,
                format: { compactCount(Double(Self.roundedCount($0))) },
                onChange: { [weak self] value in
                    self?.bodyCount = Self.roundedCount(value)
                    self?.needsReset = true
                }
            ),
            .button(title: "Столкнуть галактики заново") { [weak self] in
                self?.needsReset = true
            },
        ]
    }

    private static func roundedCount(_ value: Float) -> Int {
        max(1, Int((value / 1_024).rounded())) * 1_024
    }

    override func stopAnimation() {
        super.stopAnimation()
        cpu.stop()
    }

    override func startAnimation() {
        super.startAnimation()
        if engine == .cpu {
            needsReset = true
        }
    }

    // MARK: - Simulation

    override func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {
        let viewScale = Self.viewScale(for: uniforms.resolution)
        // Finger → world: a heavy attractor while touching.
        let clip = uniforms.touch / uniforms.resolution * 2 - 1
        attractor = SIMD2(clip.x, -clip.y) / viewScale
        attractorMass = touch.isActive ? 1.5 : 0

        guard ring.count == Self.ringSize else { return }
        if needsReset {
            needsReset = false
            resetGalaxies()
        }
        if engine == .cpu {
            cpu.setAttractor(attractor, mass: attractorMass)
            // Show the newest CPU result, if one arrived since the last frame.
            if let result = cpu.latest(newerThan: cpuVersion) {
                cpuVersion = result.version
                let next = (current + 1) % Self.ringSize
                result.bodies.withUnsafeBytes { bytes in
                    ring[next].contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
                }
                current = next
                stepRate.record(totalSteps: result.version, at: CACurrentMediaTime())
            }
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        guard ring.count == Self.ringSize, let stepPipeline, let renderPipeline else { return }
        var params = makeParams(resolution: uniforms.resolution)

        if engine == .gpu, let compute = commandBuffer.makeComputeCommandEncoder() {
            let next = (current + 1) % Self.ringSize
            compute.setBuffer(ring[current], offset: 0, index: 0)
            compute.setBuffer(ring[next], offset: 0, index: 1)
            compute.setBytes(&params, length: MemoryLayout<NBodyParams>.stride, index: 2)
            compute.dispatch(stepPipeline, count: bodyCount)
            compute.endEncoding()
            current = next
            gpuSteps += 1
            stepRate.record(totalSteps: gpuSteps, at: CACurrentMediaTime())
        }

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0.015, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBuffer(ring[current], offset: 0, index: 0)
        encoder.setVertexBytes(&params, length: MemoryLayout<NBodyParams>.stride, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: bodyCount)
        encoder.endEncoding()
        lastCommandBuffer = commandBuffer
    }

    private var gpuSteps = 0

    private func makeParams(resolution: SIMD2<Float>) -> NBodyParams {
        NBodyParams(
            count: UInt32(bodyCount),
            deltaTime: Self.stepTime,
            softening2: 0.0004,
            gravity: 1,
            attractor: attractor,
            attractorMass: attractorMass,
            pointSize: bodyCount > 16_384 ? 2 : 3,
            viewScale: Self.viewScale(for: resolution),
            brightness: min(max(6_000 / Float(bodyCount), 0.15), 1),
            galaxySplit: UInt32(bodyCount / 2)
        )
    }

    /// Fits a world 2.6 units tall into the view.
    private static func viewScale(for resolution: SIMD2<Float>) -> SIMD2<Float> {
        let y: Float = 2 / 2.6
        return SIMD2(y * resolution.y / max(resolution.x, 1), y)
    }

    private func switchEngine(to newEngine: Engine) {
        guard newEngine != engine else { return }
        // Continue from whatever the previous engine produced last.
        lastCommandBuffer?.waitUntilCompleted()
        engine = newEngine
        stepRate = StepRate()
        if newEngine == .cpu {
            cpuVersion = 0
            cpu.start(bodies: readBodies(), params: makeParams(resolution: SIMD2(1, 1)))
        } else {
            cpu.stop()
            gpuSteps = 0
        }
    }

    private func readBodies() -> [SIMD4<Float>] {
        let pointer = ring[current].contents().bindMemory(to: SIMD4<Float>.self, capacity: bodyCount)
        return Array(UnsafeBufferPointer(start: pointer, count: bodyCount))
    }

    private func resetGalaxies() {
        lastCommandBuffer?.waitUntilCompleted()
        let bodies = Self.makeGalaxies(count: bodyCount)
        bodies.withUnsafeBytes { bytes in
            ring[current].contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
        stepRate = StepRate()
        gpuSteps = 0
        if engine == .cpu {
            cpuVersion = 0
            cpu.start(bodies: bodies, params: makeParams(resolution: SIMD2(1, 1)))
        }
    }

    /// Two rotating disks on a collision course; each body starts on a circular orbit.
    private static func makeGalaxies(count: Int) -> [SIMD4<Float>] {
        var generator = SystemRandomNumberGenerator()
        let half = count / 2
        let radius: Float = 0.35
        let galaxyMass: Float = 0.5    // G × mass of one galaxy (total G × M = 1)
        let centers: [SIMD2<Float>] = [SIMD2(-0.55, -0.35), SIMD2(0.55, 0.35)]
        let drift: [SIMD2<Float>] = [SIMD2(0.12, 0.08), SIMD2(-0.12, -0.08)]
        let spin: [Float] = [1, -1]

        return (0..<count).map { index in
            let galaxy = index < half ? 0 : 1
            // r = R·u puts enclosed mass ∝ r, which gives a flat rotation curve v = √(G·M / R)
            // like real disk galaxies (and keeps the dense core from flinging stars out).
            let r = radius * Float.random(in: 0.03...1, using: &generator)
            let angle = Float.random(in: 0..<(2 * .pi), using: &generator)
            let offset = SIMD2(cos(angle), sin(angle)) * r
            let speed = sqrt(galaxyMass / radius)
            let tangent = SIMD2(-sin(angle), cos(angle)) * speed * spin[galaxy]
            let position = centers[galaxy] + offset
            let velocity = tangent + drift[galaxy]
            return SIMD4(position.x, position.y, velocity.x, velocity.y)
        }
    }
}

/// Steps per second over the last second, from (time, total steps) samples.
private struct StepRate {
    private var samples: [(time: CFTimeInterval, steps: Int)] = []

    mutating func record(totalSteps: Int, at time: CFTimeInterval) {
        samples.append((time, totalSteps))
        // A long window, so even a CPU taking seconds per step reports a rate.
        samples.removeAll { time - $0.time > 6 }
    }

    var stepsPerSecond: Double {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
        return Double(last.steps - first.steps) / (last.time - first.time)
    }
}

/// The same N-body step on the CPU, as fast as the CPU reasonably gets: every core via
/// `concurrentPerform`, and the inner loop over all bodies as Accelerate vector operations
/// (vDSP / vForce), which are optimized and vectorized regardless of the app's build settings.
/// Runs back-to-back steps on its own thread and publishes results.
nonisolated private final class CPUNBodySimulator: @unchecked Sendable {
    struct Result {
        let bodies: [SIMD4<Float>]
        let version: Int
    }

    private struct State {
        var generation = 0
        var latest: Result?
        var attractor: SIMD2<Float> = .zero
        var attractorMass: Float = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "demo.nbody.cpu", qos: .userInitiated)

    func start(bodies: [SIMD4<Float>], params: NBodyParams) {
        let generation = state.withLock { state -> Int in
            state.generation += 1
            state.latest = nil
            return state.generation
        }
        queue.async { [self] in
            run(generation: generation, bodies: bodies, params: params)
        }
    }

    func stop() {
        state.withLock { $0.generation += 1 }
    }

    func setAttractor(_ position: SIMD2<Float>, mass: Float) {
        state.withLock {
            $0.attractor = position
            $0.attractorMass = mass
        }
    }

    func latest(newerThan version: Int) -> Result? {
        state.withLock { state in
            guard let latest = state.latest, latest.version > version else { return nil }
            return latest
        }
    }

    private func run(generation: Int, bodies initial: [SIMD4<Float>], params: NBodyParams) {
        var current = initial
        var next = initial
        var version = 0
        while true {
            let (isCurrent, attractor, mass) = state.withLock {
                ($0.generation == generation, $0.attractor, $0.attractorMass)
            }
            guard isCurrent else { return }
            current.withUnsafeBufferPointer { input in
                next.withUnsafeMutableBufferPointer { output in
                    Self.step(input: input, output: output, params: params, attractor: attractor, attractorMass: mass)
                }
            }
            swap(&current, &next)
            version += 1
            let result = Result(bodies: current, version: version)
            state.withLock {
                if $0.generation == generation {
                    $0.latest = result
                }
            }
        }
    }

    private static func step(
        input: UnsafeBufferPointer<SIMD4<Float>>,
        output: UnsafeMutableBufferPointer<SIMD4<Float>>,
        params: NBodyParams,
        attractor: SIMD2<Float>,
        attractorMass: Float
    ) {
        let count = input.count
        // Structure of arrays, so vDSP can stream through all x and all y.
        var xs = [Float](repeating: 0, count: count)
        var ys = [Float](repeating: 0, count: count)
        for index in 0..<count {
            xs[index] = input[index].x
            ys[index] = input[index].y
        }
        let chunks = ProcessInfo.processInfo.activeProcessorCount * 2
        let chunkSize = (count + chunks - 1) / chunks
        // Each worker reads all bodies and writes only its own chunk, so sharing is safe.
        nonisolated(unsafe) let input = input
        nonisolated(unsafe) let output = output

        xs.withUnsafeBufferPointer { xs in
            ys.withUnsafeBufferPointer { ys in
                nonisolated(unsafe) let xs = xs
                nonisolated(unsafe) let ys = ys
                DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                    let start = chunk * chunkSize
                    let end = min(start + chunkSize, count)
                    guard start < end else { return }
                    stepChunk(
                        start..<end, xs: xs, ys: ys, input: input, output: output,
                        params: params, attractor: attractor, attractorMass: attractorMass
                    )
                }
            }
        }
    }

    private static func stepChunk(
        _ range: Range<Int>,
        xs: UnsafeBufferPointer<Float>,
        ys: UnsafeBufferPointer<Float>,
        input: UnsafeBufferPointer<SIMD4<Float>>,
        output: UnsafeMutableBufferPointer<SIMD4<Float>>,
        params: NBodyParams,
        attractor: SIMD2<Float>,
        attractorMass: Float
    ) {
        let count = input.count
        let n = vDSP_Length(count)
        var vectorCount = Int32(count)
        let dx = UnsafeMutablePointer<Float>.allocate(capacity: count)
        let dy = UnsafeMutablePointer<Float>.allocate(capacity: count)
        let r2 = UnsafeMutablePointer<Float>.allocate(capacity: count)
        let inverse = UnsafeMutablePointer<Float>.allocate(capacity: count)
        let inverse3 = UnsafeMutablePointer<Float>.allocate(capacity: count)
        defer {
            [dx, dy, r2, inverse, inverse3].forEach { $0.deallocate() }
        }
        guard let x = xs.baseAddress, let y = ys.baseAddress else { return }
        let massScale = params.gravity / Float(count)
        var softening2 = params.softening2

        for i in range {
            let body = input[i]
            var negativeX = -body.x, negativeY = -body.y
            vDSP_vsadd(x, 1, &negativeX, dx, 1, n)                 // dx = x_j - x_i
            vDSP_vsadd(y, 1, &negativeY, dy, 1, n)                 // dy = y_j - y_i
            vDSP_vmma(dx, 1, dx, 1, dy, 1, dy, 1, r2, 1, n)        // r² = dx² + dy²
            vDSP_vsadd(r2, 1, &softening2, r2, 1, n)               // + ε²
            vvrsqrtf(inverse, r2, &vectorCount)                    // 1 / r
            vDSP_vmul(inverse, 1, inverse, 1, inverse3, 1, n)
            vDSP_vmul(inverse3, 1, inverse, 1, inverse3, 1, n)     // 1 / r³
            var ax: Float = 0, ay: Float = 0
            vDSP_dotpr(dx, 1, inverse3, 1, &ax, n)
            vDSP_dotpr(dy, 1, inverse3, 1, &ay, n)

            var acceleration = SIMD2(ax, ay) * massScale
            let position = SIMD2(body.x, body.y)
            let toFinger = attractor - position
            let fingerInverse = 1 / ((toFinger * toFinger).sum() + softening2 * 4).squareRoot()
            acceleration += toFinger * (attractorMass * fingerInverse * fingerInverse * fingerInverse)
            let velocity = SIMD2(body.z, body.w) + acceleration * params.deltaTime
            let newPosition = position + velocity * params.deltaTime
            output[i] = SIMD4(newPosition.x, newPosition.y, velocity.x, velocity.y)
        }
    }
}
