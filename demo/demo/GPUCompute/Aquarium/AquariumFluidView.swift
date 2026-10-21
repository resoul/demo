//
//  AquariumFluidView.swift
//  demo
//

import UIKit
import Metal
import CoreMotion

/// Mirrors `PBFParams` in Aquarium.metal (80 bytes).
private struct PBFParams {
    var domain: SIMD2<Float>
    var gravity: SIMD2<Float>
    var deltaTime: Float
    var restDensity: Float
    var relaxation: Float
    var viscosity: Float
    var finger: SIMD2<Float>
    var fingerRadius: Float
    var partitionX: Float
    var rockCenter: SIMD2<Float>
    var rockRadius: Float
    var count: UInt32
    var maxSpeed: Float
    var splatRadius: Float
    var fieldPixelsPerUnit: SIMD2<Float>
}

/// "Aquarium in the phone": thousands of water particles (Position Based Fluids) that collide,
/// build up pressure, flow around a rock and the finger, slosh with device tilt and burst out
/// when the partition is removed. Every substep runs a grid build and several neighbour passes on
/// the GPU; the CPU only encodes dispatches.
final class AquariumFluidView: MetalAnimationView, MetalLabEffectView {
    static let countRange: ClosedRange<Float> = 2_048...65_536
    private static let capacity = Int(countRange.upperBound)
    private static let cellCapacity = 90_000
    private static let substeps = 3
    private static let spacing: Float = 0.5

    private var particleCount = 16_384
    private var iterations = 3
    private var hasPartition = true
    private var needsReset = true

    private var domain: SIMD2<Float> = SIMD2(1, 1)
    private let restDensity = AquariumFluidView.latticeDensity(spacing: spacing)

    private let motion = CMMotionManager()
    private var lastCommandBuffer: MTLCommandBuffer?
    private lazy var pairCounter = MetalEffectContext.shared.flatMap { GPUCounterRing(device: $0.device) }
    private let grid = SpatialGrid(particleCapacity: capacity, cellCapacity: cellCapacity)

    private lazy var positions = makeBuffer(shared: true)
    private lazy var velocities = makeBuffer(shared: true)
    private lazy var predicted = [makeBuffer(shared: false), makeBuffer(shared: false)]
    private lazy var velocityScratch = makeBuffer(shared: false)
    private lazy var lambdas = MetalEffectContext.shared?.device.makeBuffer(
        length: Self.capacity * MemoryLayout<Float>.stride,
        options: .storageModePrivate
    )
    private var field: MTLTexture?

    private let predictPipeline = MetalEffectContext.shared?.computePipeline(function: "pbf_predict")
    private let lambdaPipeline = MetalEffectContext.shared?.computePipeline(function: "pbf_lambda")
    private let deltaPipeline = MetalEffectContext.shared?.computePipeline(function: "pbf_delta")
    private let velocityPipeline = MetalEffectContext.shared?.computePipeline(function: "pbf_velocity")
    private let viscosityPipeline = MetalEffectContext.shared?.computePipeline(function: "pbf_viscosity")
    private let splatPipeline = MetalEffectContext.shared?.renderPipeline(
        vertex: "aquarium_splat_vertex",
        fragment: "aquarium_splat_fragment",
        blending: .additive,
        pixelFormat: .rg16Float
    )
    private let compositePipeline = MetalEffectContext.shared?.renderPipeline(vertex: "fullscreen_vertex", fragment: "aquarium_fragment")
    private var frames = RateMeter()

    var activeEntityDescription: String {
        "\(particleCount.formatted()) частиц · \(Self.substeps)×\(iterations)"
    }

    var throughputDescription: String? {
        let pairs = Double(pairCounter?.value ?? 0)
        return "\(compactCount(pairs)) пар/кадр · \(compactCount(pairs * frames.framesPerSecond))/с"
    }

    var controls: [LabControl] {
        [
            .segments(items: ["С перегородкой", "Убрать перегородку"], selected: hasPartition ? 0 : 1) { [weak self] index in
                self?.hasPartition = index == 0
            },
            .slider(
                title: "Частиц",
                range: Self.countRange,
                value: Float(particleCount),
                isLogarithmic: true,
                format: { compactCount(Double(Self.roundedCount($0))) },
                onChange: { [weak self] value in
                    self?.particleCount = Self.roundedCount(value)
                    self?.needsReset = true
                }
            ),
            .slider(
                title: "Итераций",
                range: 1...6,
                value: Float(iterations),
                format: { "\(Int($0.rounded()))" },
                onChange: { [weak self] value in self?.iterations = Int(value.rounded()) }
            ),
            .button(title: "Налить заново") { [weak self] in
                self?.hasPartition = true
                self?.needsReset = true
            },
        ]
    }

    private static func roundedCount(_ value: Float) -> Int {
        max(1, Int((value / 1_024).rounded())) * 1_024
    }

    private func makeBuffer(shared: Bool) -> MTLBuffer? {
        MetalEffectContext.shared?.device.makeBuffer(
            length: Self.capacity * MemoryLayout<SIMD2<Float>>.stride,
            options: shared ? .storageModeShared : .storageModePrivate
        )
    }

    override func startAnimation() {
        super.startAnimation()
        if motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 1.0 / 60
            motion.startDeviceMotionUpdates()
        }
    }

    override func stopAnimation() {
        super.stopAnimation()
        motion.stopDeviceMotionUpdates()
    }

    // MARK: - Frame

    override func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        guard let grid, let pairCounter, let positions, let velocities, let velocityScratch, let lambdas,
              let first = predicted[0], let second = predicted[1],
              let predictPipeline, let lambdaPipeline, let deltaPipeline, let velocityPipeline,
              let viscosityPipeline, let splatPipeline, let compositePipeline else { return }

        let aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1)
        if needsReset {
            needsReset = false
            reset(aspect: aspect)
        }
        let pixelsPerUnit = uniforms.resolution.y / domain.y
        var params = makeParams(uniforms: uniforms, pixelsPerUnit: pixelsPerUnit)
        var gridParams = GridParams(
            origin: .zero,
            cellSize: 1,
            dims: SIMD2(UInt32(ceil(domain.x)), UInt32(ceil(domain.y))),
            count: UInt32(particleCount)
        )
        let counter = pairCounter.next(in: commandBuffer)
        var buffers = [first, second]
        let paramsSize = MemoryLayout<PBFParams>.stride

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            for _ in 0..<Self.substeps {
                compute.setBuffer(positions, offset: 0, index: 0)
                compute.setBuffer(velocities, offset: 0, index: 1)
                compute.setBuffer(buffers[0], offset: 0, index: 2)
                compute.setBytes(&params, length: paramsSize, index: 3)
                compute.dispatch(predictPipeline, count: particleCount)

                grid.build(with: compute, positions: buffers[0], params: gridParams)

                for _ in 0..<iterations {
                    bindGrid(compute, grid: grid, gridParams: &gridParams, params: &params, counter: counter)
                    compute.setBuffer(buffers[0], offset: 0, index: 0)
                    compute.setBuffer(lambdas, offset: 0, index: 1)
                    compute.dispatch(lambdaPipeline, count: particleCount)

                    compute.setBuffer(buffers[1], offset: 0, index: 8)
                    compute.setBuffer(positions, offset: 0, index: 9)
                    compute.dispatch(deltaPipeline, count: particleCount)
                    buffers.swapAt(0, 1)
                }

                compute.setBuffer(positions, offset: 0, index: 0)
                compute.setBuffer(buffers[0], offset: 0, index: 1)
                compute.setBuffer(velocityScratch, offset: 0, index: 2)
                compute.setBytes(&params, length: paramsSize, index: 3)
                compute.dispatch(velocityPipeline, count: particleCount)

                bindGrid(compute, grid: grid, gridParams: &gridParams, params: &params, counter: counter)
                compute.setBuffer(buffers[0], offset: 0, index: 0)
                compute.setBuffer(velocityScratch, offset: 0, index: 1)
                compute.setBuffer(velocities, offset: 0, index: 8)
                compute.setBuffer(positions, offset: 0, index: 9)
                compute.dispatch(viscosityPipeline, count: particleCount)
            }
            compute.endEncoding()
        }
        frames.tick(at: CACurrentMediaTime())

        // Splat the particles into the half-resolution water field.
        let fieldWidth = Int(uniforms.resolution.x) / 2, fieldHeight = Int(uniforms.resolution.y) / 2
        if field?.width != fieldWidth || field?.height != fieldHeight {
            field = MetalEffectContext.shared?.makeTexture(
                width: fieldWidth, height: fieldHeight, format: .rg16Float, usage: [.shaderRead, .renderTarget]
            )
        }
        guard let field else { return }
        params.fieldPixelsPerUnit = SIMD2(repeating: pixelsPerUnit / 2)
        params.splatRadius = 0.9 * pixelsPerUnit / 2
        let splatPass = MTLRenderPassDescriptor()
        splatPass.colorAttachments[0].texture = field
        splatPass.colorAttachments[0].loadAction = .clear
        splatPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        splatPass.colorAttachments[0].storeAction = .store
        if let splat = commandBuffer.makeRenderCommandEncoder(descriptor: splatPass) {
            splat.setRenderPipelineState(splatPipeline)
            splat.setVertexBuffer(positions, offset: 0, index: 0)
            splat.setVertexBuffer(velocities, offset: 0, index: 1)
            splat.setVertexBytes(&params, length: paramsSize, index: 2)
            splat.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
            splat.endEncoding()
        }

        // Tank overlay geometry for the composite pass, in drawable pixels.
        let partitionPixels = hasPartition ? params.partitionX * pixelsPerUnit : -1
        uniforms.setCustom(0, SIMD4(partitionPixels, params.rockCenter.x * pixelsPerUnit, params.rockCenter.y * pixelsPerUnit, params.rockRadius * pixelsPerUnit))
        uniforms.setCustom(1, SIMD4(params.fingerRadius * pixelsPerUnit, 0.5 * pixelsPerUnit, 0, 0))
        encodeFullscreen(compositePipeline, into: commandBuffer, pass: pass, uniforms: &uniforms, textures: [field])
        lastCommandBuffer = commandBuffer
    }

    private func bindGrid(
        _ compute: MTLComputeCommandEncoder,
        grid: SpatialGrid,
        gridParams: inout GridParams,
        params: inout PBFParams,
        counter: MTLBuffer
    ) {
        compute.setBuffer(grid.cellStart, offset: 0, index: 2)
        compute.setBuffer(grid.cellCounts, offset: 0, index: 3)
        compute.setBuffer(grid.sortedIndices, offset: 0, index: 4)
        compute.setBytes(&gridParams, length: MemoryLayout<GridParams>.stride, index: 5)
        compute.setBytes(&params, length: MemoryLayout<PBFParams>.stride, index: 6)
        compute.setBuffer(counter, offset: 0, index: 7)
    }

    private func makeParams(uniforms: EffectUniforms, pixelsPerUnit: Float) -> PBFParams {
        // Gravity follows the device; without a motion sensor it points down the screen.
        var down = SIMD2<Float>(0, 1)
        if let gravity = motion.deviceMotion?.gravity {
            let screen = SIMD2(Float(gravity.x), Float(-gravity.y))
            if (screen * screen).sum() > 0.01 {
                down = screen / (screen * screen).sum().squareRoot()
            }
        }
        let touching = touch.isActive
        return PBFParams(
            domain: domain,
            gravity: down * domain.y * 0.45,
            deltaTime: 1.0 / Float(60 * Self.substeps),
            restDensity: restDensity,
            relaxation: 2,
            viscosity: 0.02,
            finger: uniforms.touch / pixelsPerUnit,
            fingerRadius: touching ? domain.y * 0.07 : 0,
            partitionX: hasPartition ? domain.x * 0.45 : -1,
            rockCenter: SIMD2(domain.x * 0.72, domain.y * 0.86),
            rockRadius: domain.x * 0.1,
            count: UInt32(particleCount),
            maxSpeed: 0.45 / (1.0 / Float(60 * Self.substeps)),
            splatRadius: 0,
            fieldPixelsPerUnit: .zero
        )
    }

    /// Sizes the tank so the particles fill ~80% of its height left of the partition, then stacks
    /// them there on a jittered lattice at rest spacing.
    private func reset(aspect: Float) {
        lastCommandBuffer?.waitUntilCompleted()
        let height = (Float(particleCount) * Self.spacing * Self.spacing / (0.36 * aspect)).squareRoot()
        domain = SIMD2(height * aspect, height)
        hasPartition = true

        guard let positions, let velocities else { return }
        let partitionX = domain.x * 0.45
        let columns = max(Int((partitionX - 1.2) / Self.spacing), 1)
        let points = positions.contents().bindMemory(to: SIMD2<Float>.self, capacity: particleCount)
        for index in 0..<particleCount {
            let column = index % columns, row = index / columns
            points[index] = SIMD2(
                0.6 + Float(column) * Self.spacing + Float.random(in: -0.01...0.01),
                domain.y - 0.6 - Float(row) * Self.spacing
            )
        }
        memset(velocities.contents(), 0, particleCount * MemoryLayout<SIMD2<Float>>.stride)
    }

    /// Rest density = kernel sum over a perfect lattice at the initial spacing (h = 1).
    private static func latticeDensity(spacing: Float) -> Float {
        var density: Float = 0
        for i in -3...3 {
            for j in -3...3 {
                let r2 = (Float(i * i + j * j)) * spacing * spacing
                if r2 < 1 {
                    let x = 1 - r2
                    density += 4 / .pi * x * x * x
                }
            }
        }
        return density
    }
}
