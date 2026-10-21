//
//  RayTracedRoomView.swift
//  demo
//

import UIKit
import Metal
import simd

/// Mirrors `RoomParams` in RayTracedRoom.h (176 bytes).
private struct RoomParams {
    var inverseViewProjection: simd_float4x4
    var cameraPosition: SIMD4<Float>
    var light: SIMD4<Float>
    var spheres: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var size: SIMD2<UInt32>
    var shadowSamples: UInt32
    var maxBounces: UInt32
    var time: Float
    var padding: (Float, Float, Float) = (0, 0, 0)
}

/// Mirrors `RoomPrimitive` in RayTracedRoom.h (32 bytes).
private struct RoomPrimitive {
    var normal: SIMD4<Float>
    var info: SIMD4<UInt32>
}

/// A room with a glass, a mirror and a gold sphere under a moving spherical lamp: reflections,
/// refraction and soft shadows, ray traced per pixel every frame. With hardware support the rays
/// go through a Metal acceleration structure over real triangle geometry; otherwise the same
/// shading runs on exact analytic intersections.
final class RayTracedRoomView: MetalAnimationView, MetalLabEffectView {
    private enum Engine: Int {
        case hardware
        case analytic
    }

    private static let scales: [Float] = [0.5, 0.75, 1]
    private static let spheres: [SIMD4<Float>] = [
        SIMD4(-0.85, 0.6, -0.4, 0.6),
        SIMD4(0.95, 0.6, -1.2, 0.6),
        SIMD4(0.2, 0.35, 0.75, 0.35),
    ]

    private let supportsHardware = MetalEffectContext.shared?.device.supportsRaytracing ?? false
    private lazy var engine: Engine = supportsHardware ? .hardware : .analytic
    private var shadowSamples = 4
    private var scaleIndex = 1
    private var output: MTLTexture?
    private var frames = RateMeter()
    private var lightOffset = SIMD2<Float>.zero

    private lazy var rayCounter = MetalEffectContext.shared.flatMap { GPUCounterRing(device: $0.device) }
    private let analyticPipeline = MetalEffectContext.shared?.computePipeline(function: "room_trace_analytic")
    private lazy var hardwarePipeline = supportsHardware
        ? MetalEffectContext.shared?.computePipeline(function: "room_trace_hardware")
        : nil
    private lazy var scene = supportsHardware ? buildScene() : nil
    private let displayPipeline = MetalEffectContext.shared?.renderPipeline(vertex: "fullscreen_vertex", fragment: "room_display_fragment")

    var activeEntityDescription: String {
        switch engine {
        case .hardware: "BVH: \(compactCount(Double(scene?.triangles ?? 0))) треугольников"
        case .analytic: "5 стен + 3 сферы (аналитически)"
        }
    }

    var throughputDescription: String? {
        let rays = Double(rayCounter?.value ?? 0)
        return "\(compactCount(rays)) лучей/кадр · \(compactCount(rays * frames.framesPerSecond))/с"
    }

    var controls: [LabControl] {
        var items = ["Аналитический"]
        if supportsHardware {
            items.insert("Аппаратный RT", at: 0)
        } else {
            items.append("Аппаратный RT недоступен")
        }
        return [
            .segments(items: items, selected: supportsHardware ? engine.rawValue : 0) { [weak self] index in
                guard let self, self.supportsHardware else { return }
                self.engine = Engine(rawValue: index) ?? .analytic
            },
            .slider(
                title: "Теневых лучей",
                range: 1...16,
                value: Float(shadowSamples),
                format: { "\(Int($0.rounded()))" },
                onChange: { [weak self] value in self?.shadowSamples = Int(value.rounded()) }
            ),
            .segments(items: Self.scales.map { "\(Int($0 * 100))%" }, selected: scaleIndex) { [weak self] index in
                self?.scaleIndex = index
            },
        ]
    }

    // MARK: - Scene

    /// Walls as quads and spheres as tessellated meshes in one primitive acceleration structure.
    private func buildScene() -> (structure: MTLAccelerationStructure, primitives: MTLBuffer, triangles: Int)? {
        guard let context = MetalEffectContext.shared else { return nil }
        let device = context.device
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var primitives: [RoomPrimitive] = []

        func quad(_ corners: [SIMD3<Float>], normal: SIMD3<Float>, material: UInt32) {
            let base = UInt32(vertices.count)
            vertices += corners
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            primitives += Array(repeating: RoomPrimitive(normal: SIMD4(normal, 0), info: SIMD4(material, 3, 0, 0)), count: 2)
        }
        let lo = SIMD3<Float>(-2, 0, -2.5), hi = SIMD3<Float>(2, 3, 4)
        quad([SIMD3(lo.x, lo.y, lo.z), SIMD3(hi.x, lo.y, lo.z), SIMD3(hi.x, lo.y, hi.z), SIMD3(lo.x, lo.y, hi.z)], normal: SIMD3(0, 1, 0), material: 3)
        quad([SIMD3(lo.x, hi.y, lo.z), SIMD3(hi.x, hi.y, lo.z), SIMD3(hi.x, hi.y, hi.z), SIMD3(lo.x, hi.y, hi.z)], normal: SIMD3(0, -1, 0), material: 0)
        quad([SIMD3(lo.x, lo.y, lo.z), SIMD3(hi.x, lo.y, lo.z), SIMD3(hi.x, hi.y, lo.z), SIMD3(lo.x, hi.y, lo.z)], normal: SIMD3(0, 0, 1), material: 0)
        quad([SIMD3(lo.x, lo.y, lo.z), SIMD3(lo.x, hi.y, lo.z), SIMD3(lo.x, hi.y, hi.z), SIMD3(lo.x, lo.y, hi.z)], normal: SIMD3(1, 0, 0), material: 1)
        quad([SIMD3(hi.x, lo.y, lo.z), SIMD3(hi.x, hi.y, lo.z), SIMD3(hi.x, hi.y, hi.z), SIMD3(hi.x, lo.y, hi.z)], normal: SIMD3(-1, 0, 0), material: 2)

        let materials: [UInt32] = [4, 5, 6]
        let sphereMesh = MeshBuilder.sphere(segments: 48, rings: 24)
        for (index, sphere) in Self.spheres.enumerated() {
            let base = UInt32(vertices.count)
            vertices += sphereMesh.vertices.map { SIMD3($0.position.x, $0.position.y, $0.position.z) * sphere.w + SIMD3(sphere.x, sphere.y, sphere.z) }
            indices += sphereMesh.indices.map { UInt32($0) + base }
            primitives += Array(
                repeating: RoomPrimitive(normal: .zero, info: SIMD4(materials[index], UInt32(index), 0, 0)),
                count: sphereMesh.indices.count / 3
            )
        }

        guard let vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<SIMD3<Float>>.stride),
              let indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt32>.stride),
              let primitiveBuffer = device.makeBuffer(bytes: primitives, length: primitives.count * MemoryLayout<RoomPrimitive>.stride) else { return nil }

        let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
        geometry.vertexBuffer = vertexBuffer
        geometry.vertexStride = MemoryLayout<SIMD3<Float>>.stride
        geometry.vertexFormat = .float3
        geometry.indexBuffer = indexBuffer
        geometry.indexType = .uint32
        geometry.triangleCount = indices.count / 3
        let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
        descriptor.geometryDescriptors = [geometry]

        let sizes = device.accelerationStructureSizes(descriptor: descriptor)
        guard let structure = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let scratch = device.makeBuffer(length: sizes.buildScratchBufferSize, options: .storageModePrivate),
              let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeAccelerationStructureCommandEncoder() else { return nil }
        encoder.build(accelerationStructure: structure, descriptor: descriptor, scratchBuffer: scratch, scratchBufferOffset: 0)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return (structure, primitiveBuffer, indices.count / 3)
    }

    // MARK: - Frame

    override func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {
        // Dragging moves the lamp over the room; it drifts back into its orbit afterwards.
        if touch.isActive, bounds.width > 0 {
            let target = SIMD2(Float(touch.location.x / bounds.width) * 3.2 - 1.6, Float(touch.location.y / bounds.height) * 3.5 - 2.2)
            lightOffset += (target - lightOffset) * min(Float(deltaTime) * 10, 1)
        } else {
            lightOffset *= 1 - min(Float(deltaTime) * 0.5, 1)
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        guard let rayCounter, let displayPipeline, let analyticPipeline else { return }
        let scale = Self.scales[scaleIndex]
        let width = max(Int(uniforms.resolution.x * scale), 1)
        let height = max(Int(uniforms.resolution.y * scale), 1)
        if output?.width != width || output?.height != height {
            output = MetalEffectContext.shared?.makeTexture(width: width, height: height, format: .rgba16Float)
        }
        guard let output else { return }

        let eye = SIMD3<Float>(0, 1.6, 3.7)
        let viewProjection = Camera3D.perspective(fovY: 1.05, aspect: Float(width) / Float(height), near: 0.1, far: 50)
            * Camera3D.lookAt(eye: eye, center: SIMD3(0, 1.1, -1))
        let t = uniforms.time
        let orbit = SIMD3(cos(t * 0.6) * 1.2, 2.35, sin(t * 0.6) * 1.0 - 0.4)
        let light = orbit + SIMD3(lightOffset.x, 0, lightOffset.y) * (simd_length(lightOffset) > 0.01 ? 1 : 0)
        var params = RoomParams(
            inverseViewProjection: viewProjection.inverse,
            cameraPosition: SIMD4(eye, 1),
            light: SIMD4(simd_clamp(light, SIMD3(-1.7, 0.5, -2.2), SIMD3(1.7, 2.7, 3)), 0.22),
            spheres: (Self.spheres[0], Self.spheres[1], Self.spheres[2]),
            size: SIMD2(UInt32(width), UInt32(height)),
            shadowSamples: UInt32(shadowSamples),
            maxBounces: 8,
            time: t
        )
        let counter = rayCounter.next(in: commandBuffer)

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setTexture(output, index: 0)
            compute.setBytes(&params, length: MemoryLayout<RoomParams>.stride, index: 0)
            compute.setBuffer(counter, offset: 0, index: 1)
            if engine == .hardware, let hardwarePipeline, let scene {
                compute.setAccelerationStructure(scene.structure, bufferIndex: 2)
                compute.setBuffer(scene.primitives, offset: 0, index: 3)
                compute.dispatch(hardwarePipeline, width: width, height: height)
            } else {
                compute.dispatch(analyticPipeline, width: width, height: height)
            }
            compute.endEncoding()
        }
        frames.tick(at: CACurrentMediaTime())
        encodeFullscreen(displayPipeline, into: commandBuffer, pass: pass, uniforms: &uniforms, textures: [output])
    }
}
