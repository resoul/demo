import MetalKit

final class MetalCityView: GPUExperimentView {
    override var entityCount: Int { 4_096 + Int(load * 258_048) / 1024 * 1024 }
    override var vertexFunctionName: String { "cityVertex" }
    override var fragmentFunctionName: String { "cityFragment" }
    override var loadDescription: String { "\(entityCount.formatted()) зданий" }
    override var experimentDescription: String { "GPU frustum culling · compact IDs · 2 indirect draws · 2 LOD" }
    override var actionTitle: String { alternate ? "Включить culling" : "Отключить culling" }
    private var ids: MTLBuffer!
    private var arguments: MTLBuffer!
    private var depthState: MTLDepthStencilState?
    override func configurePipeline(_ descriptor: MTLRenderPipelineDescriptor) { descriptor.depthAttachmentPixelFormat = .depth32Float }
    override func prepareResources(device: MTLDevice, library: MTLLibrary, queue: MTLCommandQueue) throws {
        try makePipelines(["cityReset", "cityCull"], device: device, library: library)
        ids = try buffer(device, bytes: 262_144 * 2 * 4, label: "GPU compacted near / far instances")
        arguments = try buffer(device, bytes: 32, label: "GPU indirect arguments × 2")
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depth)
    }
    override func encodeSimulation(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) -> Bool {
        updateUniforms(uniforms); u.side = 512
        return dispatch("cityReset", command: commandBuffer, size: MTLSize(width: 1,height: 1,depth: 1), buffers: [arguments])
            && dispatch("cityCull", command: commandBuffer, size: MTLSize(width: entityCount,height: 1,depth: 1), buffers: [ids,arguments])
    }
    override func encodeRender(encoder: MTLRenderCommandEncoder, uniforms: inout EffectUniforms) {
        renderUniforms(encoder)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(ids, offset: 0, index: 0)
        for level: UInt32 in 0..<2 {
            var lod = level
            encoder.setVertexBytes(&lod, length: 4, index: 9)
            encoder.drawPrimitives(type: .triangle, indirectBuffer: arguments, indirectBufferOffset: Int(level)*16)
        }
    }
}
