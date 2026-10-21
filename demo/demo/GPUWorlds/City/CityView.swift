//
//  CityView.swift
//  demo
//

import UIKit
import Metal
import simd
import os

/// Mirrors `CityParams` in City.metal (240 bytes).
private struct CityParams {
    var viewProjection: simd_float4x4
    var planes: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var cameraPosition: SIMD4<Float>
    var sunDirection: SIMD4<Float>
    var fogColor: SIMD4<Float>
    var instanceCount: UInt32
    var listCapacity: UInt32
    var lodDistance: Float
    var farDistance: Float
    var time: Float
    var padding: (Float, Float, Float) = (0, 0, 0)
}

/// Mirrors `CityInstance` in City.metal (32 bytes).
private struct CityInstance {
    var placement: SIMD4<Float>
    var style: SIMD4<Float>
}

/// Mirrors `DrawRange` in City.metal (16 bytes).
private struct DrawRange {
    var indexStart: UInt32
    var indexCount: UInt32
    var baseVertex: UInt32
    var padding: UInt32 = 0
}

/// A city of up to 400 000 buildings and trees seen from a camera flying over it at dusk.
/// GPU mode: a kernel culls every instance and picks a LOD, a second kernel writes the draw
/// commands into an indirect command buffer (or, where ICBs are unavailable such as the Simulator,
/// the arguments of four indirect draws). CPU mode: the same culling on the main thread and four
/// ordinary instanced draws — the cost shows up as main-thread time.
final class CityView: MetalAnimationView, MetalLabEffectView {
    override class var depthPixelFormat: MTLPixelFormat { .depth32Float }

    private enum Culling: Int {
        case gpu
        case cpu
    }

    static let countRange: ClosedRange<Float> = 25_000...400_000
    private static let capacity = Int(countRange.upperBound)
    private static let lotSize: Float = 7
    private static let lodDistance: Float = 120
    private static let farDistance: Float = 650
    private static let framesInFlight = 3

    /// Indirect command buffers are not available in the Simulator.
    private let supportsICB: Bool = {
        #if targetEnvironment(simulator)
        false
        #else
        MetalEffectContext.shared?.device.supportsFamily(.apple3) ?? false
        #endif
    }()

    private var instanceCount = 160_000
    private var culling: Culling = .gpu
    private var needsRebuild = true
    private var cityExtent: Float = 1
    private var cpuInstances: [CityInstance] = []

    private var flightAngle: Float = 0
    private var lookYaw: Float = 0
    private var lookPitch: Float = -0.25
    private var lastTouch: CGPoint?
    private var frameIndex = 0
    private var lastCullMilliseconds: Double = 0
    private let stats = VisibleStats()

    private let device = MetalEffectContext.shared?.device
    private lazy var instanceBuffer = device?.makeBuffer(length: Self.capacity * MemoryLayout<CityInstance>.stride, options: .storageModeShared)
    private lazy var gpuVisible = device?.makeBuffer(length: Self.capacity * 4 * MemoryLayout<UInt32>.stride, options: .storageModePrivate)
    private lazy var cpuVisible: [MTLBuffer] = (0..<Self.framesInFlight).compactMap { _ in
        device?.makeBuffer(length: Self.capacity * 4 * MemoryLayout<UInt32>.stride, options: .storageModeShared)
    }
    private lazy var countBuffers: [MTLBuffer] = (0..<Self.framesInFlight).compactMap { _ in
        device?.makeBuffer(length: 4 * MemoryLayout<UInt32>.stride, options: .storageModeShared)
    }
    private lazy var paramsBuffers: [MTLBuffer] = (0..<Self.framesInFlight).compactMap { _ in
        device?.makeBuffer(length: MemoryLayout<CityParams>.stride, options: .storageModeShared)
    }
    private lazy var meshes = makeMeshes()
    private lazy var groundVertices = device.flatMap { device in
        let quad = [SIMD3<Float>(-1, 0, -1), SIMD3(1, 0, -1), SIMD3(1, 0, 1), SIMD3(-1, 0, 1)].map {
            MeshVertex(position: SIMD4($0, 1), normal: SIMD4(0, 1, 0, 0))
        }
        return device.makeBuffer(bytes: quad, length: quad.count * MemoryLayout<MeshVertex>.stride)
    }
    private lazy var groundIndices = device.flatMap { device in
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        return device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride)
    }

    private let cullPipeline = MetalEffectContext.shared?.computePipeline(function: "city_cull")
    private lazy var encodePipeline = supportsICB ? MetalEffectContext.shared?.computePipeline(function: "city_encode_draws") : nil
    private let argumentsPipeline = MetalEffectContext.shared?.computePipeline(function: "city_write_indirect_arguments")
    private lazy var cityPipeline = makeCityPipeline(forIndirectCommands: supportsICB)
    private lazy var indirectArguments = device?.makeBuffer(length: 4 * 5 * MemoryLayout<UInt32>.stride, options: .storageModePrivate)
    private let groundPipeline = MetalEffectContext.shared?.renderPipeline(
        vertex: "city_ground_vertex", fragment: "city_ground_fragment", depthFormat: .depth32Float
    )
    private let depthState: MTLDepthStencilState? = {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        return MetalEffectContext.shared?.device.makeDepthStencilState(descriptor: descriptor)
    }()
    private lazy var indirect = supportsICB ? makeIndirectCommandBuffer() : nil

    var activeEntityDescription: String {
        let counts = stats.counts
        let visible = counts.reduce(0, +)
        return "видно \(compactCount(Double(visible))) из \(compactCount(Double(instanceCount))) · LOD0 \(compactCount(Double(counts[0] + counts[2])))"
    }

    var throughputDescription: String? {
        switch culling {
        case .gpu where supportsICB: "отбор на GPU · ICB: 4 команды пишет GPU"
        case .gpu: "отбор на GPU · 4 indirect draw (ICB нет в симуляторе)"
        case .cpu: String(format: "отбор на CPU: %.1f мс/кадр · 4 вызова", lastCullMilliseconds)
        }
    }

    var controls: [LabControl] {
        [
            .segments(items: [supportsICB ? "Отбор на GPU (ICB)" : "Отбор на GPU (indirect)", "Отбор на CPU"], selected: culling.rawValue) { [weak self] index in
                self?.culling = Culling(rawValue: index) ?? .gpu
            },
            .slider(
                title: "Объектов",
                range: Self.countRange,
                value: Float(instanceCount),
                isLogarithmic: true,
                format: { compactCount(Double(Self.rounded($0))) },
                onChange: { [weak self] value in
                    self?.instanceCount = Self.rounded(value)
                    self?.needsRebuild = true
                }
            ),
        ]
    }

    private static func rounded(_ value: Float) -> Int {
        max(1, Int((value / 5_000).rounded())) * 5_000
    }

    // MARK: - Setup

    private func makeCityPipeline(forIndirectCommands: Bool) -> MTLRenderPipelineState? {
        guard let context = MetalEffectContext.shared else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = context.makeFunction(name: "city_vertex")
        descriptor.fragmentFunction = context.makeFunction(name: "city_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        // Required for pipelines whose draws come from an indirect command buffer.
        descriptor.supportIndirectCommandBuffers = forIndirectCommands
        return try? context.device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// The ICB (4 draw commands that inherit pipeline and buffers) and the argument buffer through
    /// which the encode kernel writes into it.
    private func makeIndirectCommandBuffer() -> (commands: MTLIndirectCommandBuffer, arguments: MTLBuffer)? {
        guard let context = MetalEffectContext.shared,
              let function = context.makeFunction(name: "city_encode_draws") else { return nil }
        let descriptor = MTLIndirectCommandBufferDescriptor()
        descriptor.commandTypes = .drawIndexed
        descriptor.inheritBuffers = true
        descriptor.inheritPipelineState = true
        descriptor.maxVertexBufferBindCount = 0
        descriptor.maxFragmentBufferBindCount = 0
        guard let commands = context.device.makeIndirectCommandBuffer(descriptor: descriptor, maxCommandCount: 4) else { return nil }
        let encoder = function.makeArgumentEncoder(bufferIndex: 0)
        guard let arguments = context.device.makeBuffer(length: encoder.encodedLength) else { return nil }
        encoder.setArgumentBuffer(arguments, offset: 0)
        encoder.setIndirectCommandBuffer(commands, index: 0)
        return (commands, arguments)
    }

    /// Building and tree meshes at two levels of detail, in one vertex and one index buffer.
    private func makeMeshes() -> (vertices: MTLBuffer, indices: MTLBuffer, ranges: MTLBuffer, rangeList: [DrawRange])? {
        guard let device else { return nil }
        var vertices: [MeshVertex] = []
        var indices: [UInt16] = []
        var ranges: [DrawRange] = []

        func append(_ parts: [(vertices: [MeshVertex], indices: [UInt16])]) {
            let baseVertex = UInt32(vertices.count)
            let indexStart = UInt32(indices.count)
            var localVertexCount = 0
            for part in parts {
                vertices += part.vertices
                indices += part.indices.map { $0 + UInt16(localVertexCount) }
                localVertexCount += part.vertices.count
            }
            ranges.append(DrawRange(indexStart: indexStart, indexCount: UInt32(indices.count) - indexStart, baseVertex: baseVertex))
        }

        // Order matches the visible lists: building LOD0, building LOD1, tree LOD0, tree LOD1.
        append([
            MeshBuilder.box(min: SIMD3(-0.5, 0, -0.5), max: SIMD3(0.5, 0.86, 0.5)),
            MeshBuilder.box(min: SIMD3(-0.32, 0.86, -0.32), max: SIMD3(0.32, 1, 0.32)),
            MeshBuilder.box(min: SIMD3(-0.52, 0.84, -0.52), max: SIMD3(0.52, 0.87, 0.52)),
        ])
        append([MeshBuilder.box(min: SIMD3(-0.5, 0, -0.5), max: SIMD3(0.5, 1, 0.5))])
        append([MeshBuilder.box(min: SIMD3(-0.06, 0, -0.06), max: SIMD3(0.06, 0.35, 0.06)), Self.cone(segments: 10, base: 0.25)])
        append([Self.cone(segments: 4, base: 0.15)])

        guard let vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<MeshVertex>.stride),
              let indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride),
              let rangeBuffer = device.makeBuffer(bytes: ranges, length: ranges.count * MemoryLayout<DrawRange>.stride) else { return nil }
        return (vertexBuffer, indexBuffer, rangeBuffer, ranges)
    }

    /// A crown: cone from y = `base` (radius 0.5) to the tip at y = 1.
    private static func cone(segments: Int, base: Float) -> (vertices: [MeshVertex], indices: [UInt16]) {
        var vertices: [MeshVertex] = []
        var indices: [UInt16] = []
        for segment in 0..<segments {
            let a0 = Float(segment) / Float(segments) * 2 * .pi
            let a1 = Float(segment + 1) / Float(segments) * 2 * .pi
            let p0 = SIMD3(cos(a0) * 0.5, base, sin(a0) * 0.5)
            let p1 = SIMD3(cos(a1) * 0.5, base, sin(a1) * 0.5)
            let tip = SIMD3<Float>(0, 1, 0)
            let normal = simd_normalize(simd_cross(tip - p0, p1 - p0)) * -1
            let start = UInt16(vertices.count)
            vertices += [p0, p1, tip].map { MeshVertex(position: SIMD4($0, 1), normal: SIMD4(normal, 0)) }
            indices += [start, start + 1, start + 2]
        }
        return (vertices, indices)
    }

    /// Lays the instances on a grid: tall towers downtown, low blocks further out, parks of trees.
    private func rebuildCity() {
        let side = Int(Float(instanceCount).squareRoot().rounded(.up))
        cityExtent = Float(side) * Self.lotSize
        let half = cityExtent / 2
        var generator = SystemRandomNumberGenerator()
        cpuInstances = (0..<instanceCount).map { index in
            let gx = index % side, gz = index / side
            // Every 8th lot is a road.
            let x = (Float(gx) + 0.5) * Self.lotSize - half
            let z = (Float(gz) + 0.5) * Self.lotSize - half
            let downtown = max(0, 1 - simd_length(SIMD2(x, z)) / (half * 0.6))
            let park = sin(x * 0.011) * cos(z * 0.013) > 0.55
            let isTree = park || Float.random(in: 0...1, using: &generator) > 0.35 + 0.6 * downtown
            if isTree {
                let height = Float.random(in: 4...10, using: &generator)
                let green = SIMD3<Float>(0.12, Float.random(in: 0.3...0.45, using: &generator), 0.14)
                return CityInstance(placement: SIMD4(x, z, height * 0.55, height), style: SIMD4(green, 1))
            }
            let height = Float.random(in: 6...18, using: &generator) + downtown * downtown * Float.random(in: 20...110, using: &generator)
            let width = Float.random(in: 3.8...5.6, using: &generator)
            let shade = Float.random(in: 0.35...0.6, using: &generator)
            let tint = SIMD3(shade, shade * 1.02, shade * Float.random(in: 1.0...1.15, using: &generator))
            return CityInstance(placement: SIMD4(x, z, width, height), style: SIMD4(tint, 0))
        }
        cpuInstances.withUnsafeBytes { bytes in
            instanceBuffer?.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
    }

    // MARK: - Frame

    override func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {
        flightAngle += Float(deltaTime) * 0.08
        // Dragging looks around; the look relaxes back to straight ahead when released.
        if touch.isActive, let last = lastTouch {
            lookYaw -= Float(touch.location.x - last.x) * 0.006
            lookPitch = min(max(lookPitch - Float(touch.location.y - last.y) * 0.004, -1.2), 0.4)
        } else if !touch.isActive {
            lookYaw *= 0.98
        }
        lastTouch = touch.isActive ? touch.location : nil
    }

    override func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        if needsRebuild {
            needsRebuild = false
            rebuildCity()
        }
        guard let instanceBuffer, let gpuVisible, let meshes, let cityPipeline, let groundPipeline,
              let depthState, let cullPipeline, let argumentsPipeline, let indirectArguments, let groundVertices, let groundIndices,
              cpuVisible.count == Self.framesInFlight, countBuffers.count == Self.framesInFlight,
              paramsBuffers.count == Self.framesInFlight else { return }
        let slot = frameIndex % Self.framesInFlight
        frameIndex += 1

        // Camera: circling the city at rooftop height, looking ahead along the path.
        let radius = cityExtent * 0.28
        let eye = SIMD3(cos(flightAngle) * radius, 38 + 10 * sin(flightAngle * 2.3), sin(flightAngle) * radius)
        let heading = atan2(cos(flightAngle), -sin(flightAngle)) + lookYaw
        let direction = SIMD3(sin(heading) * cos(lookPitch), sin(lookPitch), cos(heading) * cos(lookPitch))
        let aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1)
        let viewProjection = Camera3D.perspective(fovY: 1.0, aspect: aspect, near: 0.5, far: Self.farDistance + 50)
            * Camera3D.lookAt(eye: eye, center: eye + direction)
        let planes = Camera3D.frustumPlanes(viewProjection)

        let params = CityParams(
            viewProjection: viewProjection,
            planes: (planes[0], planes[1], planes[2], planes[3], planes[4], planes[5]),
            cameraPosition: SIMD4(eye, 1),
            sunDirection: SIMD4(simd_normalize(SIMD3<Float>(-0.6, 0.35, -0.4)), 0),
            fogColor: SIMD4(0.32, 0.30, 0.42, 0.0045),
            instanceCount: UInt32(instanceCount),
            listCapacity: UInt32(Self.capacity),
            lodDistance: Self.lodDistance,
            farDistance: Self.farDistance,
            time: uniforms.time
        )
        paramsBuffers[slot].contents().storeBytes(of: params, as: CityParams.self)
        let counts = countBuffers[slot]
        let visible: MTLBuffer

        switch culling {
        case .gpu:
            visible = gpuVisible
            if let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.fill(buffer: counts, range: 0..<counts.length, value: 0)
                blit.endEncoding()
            }
            if let compute = commandBuffer.makeComputeCommandEncoder() {
                compute.setBuffer(instanceBuffer, offset: 0, index: 0)
                compute.setBuffer(paramsBuffers[slot], offset: 0, index: 1)
                compute.setBuffer(counts, offset: 0, index: 2)
                compute.setBuffer(gpuVisible, offset: 0, index: 3)
                compute.dispatch(cullPipeline, count: instanceCount)

                compute.setBuffer(counts, offset: 0, index: 1)
                compute.setBuffer(meshes.ranges, offset: 0, index: 2)
                compute.setBuffer(meshes.indices, offset: 0, index: 3)
                compute.setBuffer(paramsBuffers[slot], offset: 0, index: 4)
                if let indirect, let encodePipeline {
                    compute.setBuffer(indirect.arguments, offset: 0, index: 0)
                    compute.useResource(indirect.commands, usage: .write)
                    compute.dispatch(encodePipeline, count: 4)
                } else {
                    compute.setBuffer(indirectArguments, offset: 0, index: 0)
                    compute.dispatch(argumentsPipeline, count: 4)
                }
                compute.endEncoding()
            }
        case .cpu:
            visible = cpuVisible[slot]
            cullOnCPU(planes: planes, eye: eye, into: visible, counts: counts)
        }
        commandBuffer.addCompletedHandler(Self.statsReader(buffer: counts, into: stats))

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.32, green: 0.30, blue: 0.42, alpha: 1)
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setDepthStencilState(depthState)
        encoder.setFragmentBuffer(paramsBuffers[slot], offset: 0, index: 0)

        var ground = SIMD4<Float>(0, 0, 0, cityExtent)
        encoder.setRenderPipelineState(groundPipeline)
        encoder.setVertexBuffer(groundVertices, offset: 0, index: 0)
        encoder.setVertexBuffer(paramsBuffers[slot], offset: 0, index: 1)
        encoder.setVertexBytes(&ground, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint16, indexBuffer: groundIndices, indexBufferOffset: 0)

        encoder.setRenderPipelineState(cityPipeline)
        encoder.setVertexBuffer(meshes.vertices, offset: 0, index: 0)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(visible, offset: 0, index: 2)
        encoder.setVertexBuffer(paramsBuffers[slot], offset: 0, index: 3)
        switch culling {
        case .gpu:
            if let indirect {
                // The commands reference the index buffer directly, so make it resident explicitly.
                encoder.useResource(meshes.indices, usage: .read, stages: .vertex)
                encoder.executeCommandsInBuffer(indirect.commands, range: 0..<4)
            } else {
                let stride = 5 * MemoryLayout<UInt32>.stride
                for list in 0..<4 {
                    encoder.drawIndexedPrimitives(
                        type: .triangle, indexType: .uint16, indexBuffer: meshes.indices, indexBufferOffset: 0,
                        indirectBuffer: indirectArguments, indirectBufferOffset: list * stride
                    )
                }
            }
        case .cpu:
            let listCounts = counts.contents().bindMemory(to: UInt32.self, capacity: 4)
            for (list, range) in meshes.rangeList.enumerated() where listCounts[list] > 0 {
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: Int(range.indexCount),
                    indexType: .uint16,
                    indexBuffer: meshes.indices,
                    indexBufferOffset: Int(range.indexStart) * MemoryLayout<UInt16>.stride,
                    instanceCount: Int(listCounts[list]),
                    baseVertex: Int(range.baseVertex),
                    baseInstance: list * Self.capacity
                )
            }
        }
        encoder.endEncoding()
    }

    /// The same frustum and LOD test as `city_cull`, on the main thread.
    private func cullOnCPU(planes: [SIMD4<Float>], eye: SIMD3<Float>, into visible: MTLBuffer, counts: MTLBuffer) {
        let start = CACurrentMediaTime()
        let lists = visible.contents().bindMemory(to: UInt32.self, capacity: Self.capacity * 4)
        var listCounts = [Int](repeating: 0, count: 4)
        cpuInstances.withUnsafeBufferPointer { instances in
            for index in 0..<instances.count {
                let instance = instances[index]
                let width = instance.placement.z, height = instance.placement.w
                let center = SIMD3(instance.placement.x, height * 0.5, instance.placement.y)
                let radius = simd_length(SIMD3(width, height, width)) * 0.5
                var inside = true
                for plane in planes where simd_dot(SIMD3(plane.x, plane.y, plane.z), center) + plane.w < -radius {
                    inside = false
                    break
                }
                guard inside else { continue }
                let distance = simd_distance(center, eye)
                guard distance <= Self.farDistance else { continue }
                let list = Int(instance.style.w) * 2 + (distance < Self.lodDistance ? 0 : 1)
                lists[list * Self.capacity + listCounts[list]] = UInt32(index)
                listCounts[list] += 1
            }
        }
        let countPointer = counts.contents().bindMemory(to: UInt32.self, capacity: 4)
        for list in 0..<4 {
            countPointer[list] = UInt32(listCounts[list])
        }
        lastCullMilliseconds = (CACurrentMediaTime() - start) * 1000
    }

    /// Built outside the main actor: Metal calls completion handlers on its own thread.
    private nonisolated static func statsReader(buffer: MTLBuffer, into stats: VisibleStats) -> MTLCommandBufferHandler {
        { _ in
            let pointer = buffer.contents().bindMemory(to: UInt32.self, capacity: 4)
            stats.store((0..<4).map { Int(pointer[$0]) })
        }
    }
}

nonisolated private final class VisibleStats: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: [0, 0, 0, 0])

    var counts: [Int] { value.withLock { $0 } }

    func store(_ counts: [Int]) {
        value.withLock { $0 = counts }
    }
}
