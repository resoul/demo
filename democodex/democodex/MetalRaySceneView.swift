import MetalKit
import simd

/// Triangle acceleration structure on supported devices; exact sphere/plane intersections otherwise.
final class MetalRaySceneView: GPUExperimentView {
    override var vertexFunctionName: String { "experimentFullscreen" }
    override var fragmentFunctionName: String { "raySceneFragment" }
    override var entityCount: Int { 3 }
    var bounces: Int { 2 + Int(load * 4) }
    private(set) var hardwareTraversal = false
    override var loadDescription: String { "\(bounces) отражений / преломлений" }
    override var experimentDescription: String { hardwareTraversal ? "Triangle acceleration structure · Metal intersector · hard shadows" : "Analytic ray tracing · sphere / plane intersections · hard shadows" }
    override var extraMetrics: String { hardwareTraversal ? "\(triangleCount.formatted()) треугольников · AS traversal" : "Устройство без Metal ray tracing: аналитические пересечения" }
    override var actionTitle: String { alternate ? "Стекло + зеркало" : "Только зеркала" }
    private var acceleration: MTLAccelerationStructure?
    private var vertices: MTLBuffer?
    private var scratch: MTLBuffer?
    private var output: MTLTexture?
    private var device: MTLDevice?
    private var triangleCount = 0

    override func prepareResources(device: MTLDevice, library: MTLLibrary, queue: MTLCommandQueue) throws {
        self.device = device
        output = try texture(device, width: 1, height: 1)
        guard device.supportsRaytracing else { return }
        try makePipelines(["traceTriangleScene"], device: device, library: library)
        var points: [SIMD4<Float>] = []
        func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, material: Float) {
            points += [SIMD4(a, material), SIMD4(b, material), SIMD4(c, material)]
        }
        triangle(SIMD3(-6,-1,-6), SIMD3(6,-1,6), SIMD3(6,-1,-6), material: 0)
        triangle(SIMD3(-6,-1,-6), SIMD3(-6,-1,6), SIMD3(6,-1,6), material: 0)
        triangle(SIMD3(-6,-1,-4), SIMD3(6,5,-4), SIMD3(-6,5,-4), material: 4)
        triangle(SIMD3(-6,-1,-4), SIMD3(6,-1,-4), SIMD3(6,5,-4), material: 4)
        for (center, radius, material) in [(SIMD3<Float>(-0.9,-0.22,0), Float(0.76), Float(1)), (SIMD3<Float>(0.85,-0.16,-0.3), Float(0.82), Float(2)), (SIMD3<Float>(0,-0.65,1.1), Float(0.32), Float(3))] {
            func point(_ latitude: Int, _ longitude: Int) -> SIMD3<Float> {
                let theta = Float(latitude) / 24 * .pi
                let phi = Float(longitude) / 48 * .pi * 2
                return center + radius * SIMD3(sin(theta)*cos(phi), cos(theta), sin(theta)*sin(phi))
            }
            for y in 0..<24 { for x in 0..<48 {
                if y > 0 { triangle(point(y,x), point(y+1,x), point(y,x+1), material: material) }
                if y < 23 { triangle(point(y,x+1), point(y+1,x), point(y+1,x+1), material: material) }
            } }
        }
        triangleCount = points.count / 3
        guard let vertexBuffer = points.withUnsafeBytes({ bytes in device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared) }) else { throw MetalLabError.allocation }
        vertices = vertexBuffer
        let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
        geometry.vertexBuffer = vertexBuffer
        geometry.vertexStride = 16
        geometry.vertexFormat = .float3
        geometry.triangleCount = triangleCount
        geometry.opaque = true
        let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
        descriptor.geometryDescriptors = [geometry]
        let sizes = device.accelerationStructureSizes(descriptor: descriptor)
        guard let acceleration = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let command = queue.makeCommandBuffer(), let encoder = command.makeAccelerationStructureCommandEncoder() else { throw MetalLabError.allocation }
        scratch = try buffer(device, bytes: sizes.buildScratchBufferSize, label: "Ray scene AS build scratch")
        encoder.build(accelerationStructure: acceleration, descriptor: descriptor, scratchBuffer: scratch!, scratchBufferOffset: 0)
        encoder.endEncoding(); command.commit()
        self.acceleration = acceleration
        hardwareTraversal = true
    }
    override func encodeSimulation(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) -> Bool {
        updateUniforms(uniforms); u.steps = UInt32(bounces)
        guard hardwareTraversal, let device, let acceleration, let vertices, let pipeline = compute["traceTriangleScene"] else { return true }
        let width = max(1, Int(uniforms.resolution.x) / 2), height = max(1, Int(uniforms.resolution.y) / 2)
        if output?.width != width || output?.height != height {
            guard let texture = try? texture(device, width: width, height: height) else { return false }
            output = texture
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(vertices, offset: 0, index: 0)
        encoder.setAccelerationStructure(acceleration, bufferIndex: 4)
        var uniforms = u
        encoder.setBytes(&uniforms, length: 64, index: 8)
        encoder.setTexture(output, index: 0)
        encoder.dispatchThreads(MTLSize(width: width,height: height,depth: 1), threadsPerThreadgroup: MTLSize(width: 8,height: 8,depth: 1))
        encoder.endEncoding()
        return true
    }
    override func encodeRender(encoder: MTLRenderCommandEncoder, uniforms: inout EffectUniforms) {
        var settings = u
        if hardwareTraversal { settings.flags |= 4 }
        encoder.setFragmentBytes(&settings, length: 64, index: 8)
        encoder.setFragmentTexture(output, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
