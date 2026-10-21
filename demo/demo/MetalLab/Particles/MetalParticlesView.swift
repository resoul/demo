//
//  MetalParticlesView.swift
//  demo
//

import UIKit
import Metal

/// Mirrors `ParticleUniforms` in ParticlesCompute.metal (32 bytes).
private struct ParticleUniforms {
    var resolution: SIMD2<Float>
    var touch: SIMD2<Float>
    var touchStrength: Float
    var time: Float
    var deltaTime: Float
    var count: UInt32
}

/// Particle stress test: positions live in a GPU-only buffer and are integrated by a compute
/// kernel every frame; the CPU only encodes two dispatches and one point draw.
/// Holding a finger attracts the swarm, releasing it blasts the particles away.
final class MetalParticlesView: MetalAnimationView, MetalLabEffectView {
    static let particleRange = 10_000...1_000_000

    var particleCount = 200_000 {
        didSet { particleCount = min(max(particleCount, Self.particleRange.lowerBound), Self.particleRange.upperBound) }
    }

    var activeEntityDescription: String {
        "\(particleCount.formatted()) частиц"
    }

    private static let particleStride = MemoryLayout<SIMD4<Float>>.stride

    /// 16 MB for a million particles, allocated once in GPU-private memory.
    private lazy var particleBuffer = MetalEffectContext.shared?.device.makeBuffer(
        length: Self.particleRange.upperBound * Self.particleStride,
        options: .storageModePrivate
    )
    private let initPipeline = MetalEffectContext.shared?.computePipeline(function: "particles_init")
    private let updatePipeline = MetalEffectContext.shared?.computePipeline(function: "particles_update")
    private let renderPipeline = MetalEffectContext.shared?.renderPipeline(
        vertex: "particles_vertex",
        fragment: "particles_fragment",
        blending: .additive
    )

    private var initializedResolution: SIMD2<Float> = .zero
    private var deltaTime: Float = 0
    private var wasTouching = false
    /// 1 right after the finger lifts, decaying to 0: the release burst.
    private var burst: Float = 0

    override func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {
        self.deltaTime = Float(deltaTime)
        if wasTouching && !touch.isActive {
            burst = 1
        }
        wasTouching = touch.isActive
        burst = max(0, burst - Float(deltaTime) * 2.5)
    }

    override func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        guard let particleBuffer, let initPipeline, let updatePipeline, let renderPipeline else { return }

        var particleUniforms = ParticleUniforms(
            resolution: uniforms.resolution,
            touch: uniforms.touch,
            touchStrength: touch.isActive ? uniforms.touchStrength : -burst,
            time: uniforms.time,
            deltaTime: deltaTime,
            count: UInt32(Self.particleRange.upperBound)
        )

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setBuffer(particleBuffer, offset: 0, index: 0)
            // Scatter all particles over the view whenever its pixel size changes.
            if initializedResolution != uniforms.resolution {
                initializedResolution = uniforms.resolution
                compute.setBytes(&particleUniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 1)
                dispatch(compute, pipeline: initPipeline, count: Self.particleRange.upperBound)
            }
            particleUniforms.count = UInt32(particleCount)
            compute.setBytes(&particleUniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 1)
            dispatch(compute, pipeline: updatePipeline, count: particleCount)
            compute.endEncoding()
        }

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.02, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&particleUniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
        encoder.endEncoding()
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, count: Int) {
        let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        encoder.setComputePipelineState(pipeline)
        encoder.dispatchThreadgroups(
            MTLSize(width: (count + width - 1) / width, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
    }
}
