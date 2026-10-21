//
//  ClothView.swift
//  demo
//

import UIKit
import Metal
import simd

/// Mirrors `ClothParams` in Cloth.metal (160 bytes).
private struct ClothParams {
    var viewProjection: simd_float4x4
    var sphere: SIMD4<Float>
    var grabTarget: SIMD4<Float>
    var lightDirection: SIMD4<Float>
    var cameraPosition: SIMD4<Float>
    var gridSize: SIMD2<UInt32>
    var grabIndex: UInt32
    var pinned: UInt32
    var spacing: Float
    var deltaTime: Float
    var tearFactor: Float
    var relaxation: Float
}

/// A sheet of cloth from 32×32 up to 256×256 nodes that falls onto a sphere, drapes and can be
/// grabbed and torn. Simulation, normals and even the index buffer are produced by compute
/// kernels every frame; the CPU only picks the grabbed node and encodes dispatches.
final class ClothView: MetalAnimationView, MetalLabEffectView {
    override class var depthPixelFormat: MTLPixelFormat { .depth32Float }

    private static let maxSide = 256
    private static let capacity = maxSide * maxSide
    /// More substeps with fewer iterations keep the cloth stiffer than the reverse ("small steps").
    private static let substeps = 4
    private static let clothSize: Float = 2.2

    private var side = 96
    private var iterations = 10
    private var pinned = false
    private var tearing = true
    private var needsReset = true

    private var yaw: Float = 0.6
    private var pitch: Float = 0.42
    private var grabIndex: Int?
    private var grabDepth: Float = 0
    private var wasTouching = false
    private var lastTouch: CGPoint = .zero
    private var viewProjection = matrix_identity_float4x4
    private var lastCommandBuffer: MTLCommandBuffer?
    private var frames = RateMeter()

    private lazy var positions = makeBuffer(MemoryLayout<SIMD4<Float>>.stride, shared: true)
    private lazy var velocities = makeBuffer(MemoryLayout<SIMD4<Float>>.stride, shared: true)
    private lazy var predicted = [makeBuffer(MemoryLayout<SIMD4<Float>>.stride), makeBuffer(MemoryLayout<SIMD4<Float>>.stride)]
    private lazy var normals = makeBuffer(MemoryLayout<SIMD4<Float>>.stride)
    private lazy var edges = makeBuffer(MemoryLayout<UInt32>.stride, shared: true)
    private lazy var indices = makeBuffer(MemoryLayout<UInt32>.stride * 6)
    private lazy var solveCounter = MetalEffectContext.shared.flatMap { GPUCounterRing(device: $0.device) }

    private lazy var sphereMesh = makeMesh(MeshBuilder.sphere())
    private lazy var groundMesh = makeMesh((
        [SIMD3<Float>(-1, 0, -1), SIMD3(1, 0, -1), SIMD3(1, 0, 1), SIMD3(-1, 0, 1)].map {
            MeshVertex(position: SIMD4($0, 1), normal: SIMD4(0, 1, 0, 0))
        },
        [0, 1, 2, 0, 2, 3]
    ))

    private let predictPipeline = MetalEffectContext.shared?.computePipeline(function: "cloth_predict")
    private let constraintPipeline = MetalEffectContext.shared?.computePipeline(function: "cloth_constraints")
    private let finishPipeline = MetalEffectContext.shared?.computePipeline(function: "cloth_finish")
    private let normalsPipeline = MetalEffectContext.shared?.computePipeline(function: "cloth_normals")
    private let indicesPipeline = MetalEffectContext.shared?.computePipeline(function: "cloth_indices")
    private let clothPipeline = MetalEffectContext.shared?.renderPipeline(
        vertex: "cloth_vertex", fragment: "cloth_scene_fragment", depthFormat: .depth32Float
    )
    private let meshPipeline = MetalEffectContext.shared?.renderPipeline(
        vertex: "cloth_mesh_vertex", fragment: "cloth_scene_fragment", depthFormat: .depth32Float
    )
    private let depthState: MTLDepthStencilState? = {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        return MetalEffectContext.shared?.device.makeDepthStencilState(descriptor: descriptor)
    }()

    private let sphere = SIMD4<Float>(0, 0.55, 0, 0.55)

    var activeEntityDescription: String {
        "\(side)×\(side) = \(compactCount(Double(side * side))) узлов"
    }

    var throughputDescription: String? {
        let solves = Double(solveCounter?.value ?? 0)
        return "\(compactCount(solves)) ограничений/кадр · \(compactCount(solves * frames.framesPerSecond))/с"
    }

    var controls: [LabControl] {
        [
            .segments(items: ["Падает свободно", "Закреплена", "Не рвётся"], selected: pinned ? 1 : (tearing ? 0 : 2)) { [weak self] index in
                self?.pinned = index == 1
                self?.tearing = index != 2
                self?.needsReset = true
            },
            .slider(
                title: "Сетка",
                range: 32...Float(Self.maxSide),
                value: Float(side),
                format: { "\(Self.roundedSide($0))²" },
                onChange: { [weak self] value in
                    self?.side = Self.roundedSide(value)
                    self?.needsReset = true
                }
            ),
            .slider(
                title: "Итераций",
                range: 1...32,
                value: Float(iterations),
                format: { "\(Int($0.rounded()))" },
                onChange: { [weak self] value in self?.iterations = Int(value.rounded()) }
            ),
            .button(title: "Бросить заново") { [weak self] in
                self?.needsReset = true
            },
        ]
    }

    private static func roundedSide(_ value: Float) -> Int {
        Int((value / 16).rounded()) * 16
    }

    private func makeBuffer(_ stride: Int, shared: Bool = false) -> MTLBuffer? {
        MetalEffectContext.shared?.device.makeBuffer(
            length: Self.capacity * stride,
            options: shared ? .storageModeShared : .storageModePrivate
        )
    }

    private func makeMesh(_ mesh: (vertices: [MeshVertex], indices: [UInt16])) -> (vertices: MTLBuffer, indices: MTLBuffer, count: Int)? {
        guard let device = MetalEffectContext.shared?.device,
              let vertices = device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * MemoryLayout<MeshVertex>.stride),
              let indices = device.makeBuffer(bytes: mesh.indices, length: mesh.indices.count * MemoryLayout<UInt16>.stride) else { return nil }
        return (vertices, indices, mesh.indices.count)
    }

    // MARK: - Interaction

    override func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {
        let resolution = uniforms.resolution
        let fingerPixels = uniforms.touch
        if touch.isActive && !wasTouching {
            grabIndex = pickNode(at: fingerPixels, resolution: resolution)
            lastTouch = touch.location
        }
        if touch.isActive && grabIndex == nil {
            // Dragging empty space orbits the camera.
            yaw -= Float(touch.location.x - lastTouch.x) * 0.008
            pitch = min(max(pitch + Float(touch.location.y - lastTouch.y) * 0.006, 0.08), 1.3)
            lastTouch = touch.location
        }
        if !touch.isActive {
            grabIndex = nil
            yaw += Float(deltaTime) * 0.08
        }
        wasTouching = touch.isActive
    }

    /// Nearest cloth node to the finger on screen (within ~40 pt), using last frame's positions.
    private func pickNode(at pixel: SIMD2<Float>, resolution: SIMD2<Float>) -> Int? {
        guard let positions else { return nil }
        lastCommandBuffer?.waitUntilCompleted()
        let nodes = positions.contents().bindMemory(to: SIMD4<Float>.self, capacity: side * side)
        var best: (index: Int, distance: Float, depth: Float)?
        let limit = 40 * Float(pixelsPerPoint)
        for index in 0..<(side * side) {
            let clip = viewProjection * SIMD4(nodes[index].x, nodes[index].y, nodes[index].z, 1)
            guard clip.w > 0 else { continue }
            let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
            let screen = SIMD2((ndc.x + 1) * 0.5 * resolution.x, (1 - ndc.y) * 0.5 * resolution.y)
            let distance = simd_distance(screen, pixel)
            if distance < limit, distance < (best?.distance ?? .infinity) {
                best = (index, distance, ndc.z)
            }
        }
        grabDepth = best?.depth ?? 0
        return best?.index
    }

    // MARK: - Frame

    override func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        guard let positions, let velocities, let normals, let edges, let indices,
              let first = predicted[0], let second = predicted[1], let solveCounter,
              let predictPipeline, let constraintPipeline, let finishPipeline, let normalsPipeline, let indicesPipeline,
              let clothPipeline, let meshPipeline, let depthState, let sphereMesh, let groundMesh else { return }

        if needsReset {
            needsReset = false
            reset()
        }
        let nodeCount = side * side
        let resolution = uniforms.resolution
        let target = SIMD3<Float>(0, 0.6, 0)
        let eye = Camera3D.orbit(target: target, yaw: yaw, pitch: pitch, distance: 4.6)
        viewProjection = Camera3D.perspective(fovY: 0.85, aspect: resolution.x / max(resolution.y, 1), near: 0.1, far: 50)
            * Camera3D.lookAt(eye: eye, center: target)

        var grabTarget = SIMD4<Float>(0, 0, 0, 0)
        if grabIndex != nil, touch.isActive {
            let world = Camera3D.unproject(
                pixel: uniforms.touch, ndcDepth: grabDepth, resolution: resolution,
                inverseViewProjection: viewProjection.inverse
            )
            grabTarget = SIMD4(world, 1)
        }
        var params = ClothParams(
            viewProjection: viewProjection,
            sphere: sphere,
            grabTarget: grabTarget,
            lightDirection: SIMD4(simd_normalize(SIMD3<Float>(0.5, 1, 0.35)), 0),
            cameraPosition: SIMD4(eye, 1),
            gridSize: SIMD2(UInt32(side), UInt32(side)),
            grabIndex: UInt32(grabIndex ?? Int(UInt32.max)),
            pinned: pinned ? 1 : 0,
            spacing: Self.clothSize / Float(side - 1),
            deltaTime: 1.0 / Float(60 * Self.substeps),
            tearFactor: tearing ? 3.2 : 0,
            relaxation: 1.5
        )
        let size = MemoryLayout<ClothParams>.stride
        let counter = solveCounter.next(in: commandBuffer)

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setBytes(&params, length: size, index: 3)
            for _ in 0..<Self.substeps {
                compute.setBuffer(positions, offset: 0, index: 0)
                compute.setBuffer(velocities, offset: 0, index: 1)
                compute.setBuffer(first, offset: 0, index: 2)
                compute.setBytes(&params, length: size, index: 3)
                compute.dispatch(predictPipeline, count: nodeCount)

                var buffers = [first, second]
                for _ in 0..<iterations {
                    compute.setBuffer(buffers[0], offset: 0, index: 0)
                    compute.setBuffer(edges, offset: 0, index: 1)
                    compute.setBuffer(buffers[1], offset: 0, index: 2)
                    compute.setBytes(&params, length: size, index: 3)
                    compute.setBuffer(counter, offset: 0, index: 4)
                    compute.dispatch(constraintPipeline, count: nodeCount)
                    buffers.swapAt(0, 1)
                }

                compute.setBuffer(positions, offset: 0, index: 0)
                compute.setBuffer(buffers[0], offset: 0, index: 1)
                compute.setBuffer(velocities, offset: 0, index: 2)
                compute.setBuffer(edges, offset: 0, index: 3)
                compute.setBytes(&params, length: size, index: 4)
                compute.dispatch(finishPipeline, count: nodeCount)
            }
            compute.setBuffer(positions, offset: 0, index: 0)
            compute.setBuffer(normals, offset: 0, index: 1)
            compute.setBytes(&params, length: size, index: 2)
            compute.dispatch(normalsPipeline, count: nodeCount)

            compute.setBuffer(edges, offset: 0, index: 0)
            compute.setBuffer(indices, offset: 0, index: 1)
            compute.setBytes(&params, length: size, index: 2)
            compute.dispatch(indicesPipeline, count: (side - 1) * (side - 1))
            compute.endEncoding()
        }
        frames.tick(at: CACurrentMediaTime())

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1)
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setDepthStencilState(depthState)
        encoder.setFragmentBytes(&params, length: size, index: 0)

        encoder.setRenderPipelineState(meshPipeline)
        encoder.setVertexBytes(&params, length: size, index: 1)
        for (mesh, transform, material) in [
            (groundMesh, SIMD4<Float>(0, 0, 0, 9), UInt32(2)),
            (sphereMesh, SIMD4<Float>(sphere.x, sphere.y, sphere.z, sphere.w), UInt32(1)),
        ] {
            var transform = transform
            var material = material
            encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
            encoder.setVertexBytes(&transform, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
            encoder.setVertexBytes(&material, length: MemoryLayout<UInt32>.stride, index: 3)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.count, indexType: .uint16, indexBuffer: mesh.indices, indexBufferOffset: 0)
        }

        encoder.setRenderPipelineState(clothPipeline)
        encoder.setVertexBuffer(positions, offset: 0, index: 0)
        encoder.setVertexBuffer(normals, offset: 0, index: 1)
        encoder.setVertexBytes(&params, length: size, index: 2)
        encoder.drawIndexedPrimitives(
            type: .triangle, indexCount: (side - 1) * (side - 1) * 6, indexType: .uint32,
            indexBuffer: indices, indexBufferOffset: 0
        )
        encoder.endEncoding()
        lastCommandBuffer = commandBuffer
    }

    /// A flat sheet above the sphere, all edges intact.
    private func reset() {
        lastCommandBuffer?.waitUntilCompleted()
        guard let positions, let velocities, let edges else { return }
        let nodes = positions.contents().bindMemory(to: SIMD4<Float>.self, capacity: side * side)
        let speeds = velocities.contents().bindMemory(to: SIMD4<Float>.self, capacity: side * side)
        let flags = edges.contents().bindMemory(to: UInt32.self, capacity: side * side)
        let half = Self.clothSize / 2
        for y in 0..<side {
            for x in 0..<side {
                let index = y * side + x
                let u = Float(x) / Float(side - 1), v = Float(y) / Float(side - 1)
                nodes[index] = SIMD4(-half + u * Self.clothSize, 1.7 + Float.random(in: 0...0.002), -half + v * Self.clothSize, 1)
                speeds[index] = .zero
                flags[index] = 0xF
            }
        }
    }
}
