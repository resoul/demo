//
//  MetalEmojiParticlesView.swift
//  demo
//

import UIKit
import Metal
import os

/// Mirrors `EmojiUniforms` in EmojiShared.h (64 bytes).
private struct EmojiUniforms {
    var resolution: SIMD2<Float>
    var emitter: SIMD2<Float>
    var touch: SIMD2<Float>
    var touchStrength: Float
    var time: Float
    var deltaTime: Float
    var gravity: Float
    var baseSize: Float
    var count: UInt32
    var emojiFirst: UInt32
    var emojiCount: UInt32
    var atlasColumns: UInt32
    var frame: UInt32
}

/// Latest on-screen emoji count, written by Metal completion handlers on a background thread.
nonisolated private final class VisibleCount: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: 0)

    var current: Int { value.withLock { $0 } }

    func store(_ count: Int) {
        value.withLock { $0 = count }
    }
}

/// Emoji fountain stress test. Particle state lives in a GPU-only buffer; `emoji_update`
/// (EmojiPhysics.metal) simulates every particle, and `emoji_vertex` / `emoji_fragment`
/// (EmojiRender.metal) draw them all as textured quads with one instanced draw call.
/// The CPU encodes a fill, one dispatch and one draw per frame, whatever the particle count.
final class MetalEmojiParticlesView: MetalAnimationView {
    enum Palette: Int, CaseIterable {
        case fire
        case rocket
        case hearts
        case mix

        var title: String {
            switch self {
            case .fire: "Огонь 🔥"
            case .rocket: "Ракета 🚀"
            case .hearts: "Сердечки ❤️"
            case .mix: "Микс 🎲"
            }
        }

        /// Atlas cells new particles pick from (see `atlasEmoji`).
        var cells: Range<Int> {
            switch self {
            case .fire: 0..<1
            case .rocket: 1..<2
            case .hearts: 2..<3
            case .mix: 0..<MetalEmojiParticlesView.atlasEmoji.count
            }
        }
    }

    static let atlasEmoji = ["🔥", "🚀", "❤️", "💥", "🦊"]
    static let countRange = 1_000...200_000
    /// `MemoryLayout` of `EmojiParticle` in EmojiShared.h.
    private static let particleStride = 48

    /// Rendered once, the first time an emoji view is created.
    private static let atlas: EmojiTextureProvider.Atlas? = MetalEffectContext.shared.flatMap {
        try? EmojiTextureProvider.makeAtlas(emoji: atlasEmoji, device: $0.device)
    }

    var emojiCount = 20_000 {
        didSet { emojiCount = min(max(emojiCount, Self.countRange.lowerBound), Self.countRange.upperBound) }
    }
    /// Applies to newly spawned emoji, so switching blends over one particle lifetime.
    var palette: Palette = .mix

    /// Emoji the GPU counted inside the view on the last completed frame.
    var visibleEmojiCount: Int { visibleCount.current }

    override var textureMemoryBytes: Int { Self.atlas?.byteCount ?? 0 }

    private lazy var particleBuffer = MetalEffectContext.shared?.device.makeBuffer(
        length: Self.countRange.upperBound * Self.particleStride,
        options: .storageModePrivate
    )
    /// One counter per frame in flight, so the CPU never reads a counter the GPU is resetting.
    private lazy var counterBuffers: [MTLBuffer] = (0..<3).compactMap { _ in
        MetalEffectContext.shared?.device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
    }
    private let initPipeline = MetalEffectContext.shared?.computePipeline(function: "emoji_init")
    private let updatePipeline = MetalEffectContext.shared?.computePipeline(function: "emoji_update")
    private let renderPipeline = MetalEffectContext.shared?.renderPipeline(
        vertex: "emoji_vertex",
        fragment: "emoji_fragment",
        blending: .premultipliedAlpha
    )

    private let visibleCount = VisibleCount()
    private var isInitialized = false
    private var frameIndex: UInt32 = 0
    private var deltaTime: Float = 0

    override func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {
        self.deltaTime = Float(deltaTime)
    }

    override func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        guard let atlas = Self.atlas,
              let particleBuffer,
              counterBuffers.count == 3,
              let initPipeline,
              let updatePipeline,
              let renderPipeline else { return }

        let scale = Float(pixelsPerPoint)
        let resolution = uniforms.resolution
        // Touching moves the fountain to the finger; otherwise it sways along the bottom.
        let emitter = touch.isActive
            ? uniforms.touch
            : SIMD2(resolution.x * (0.5 + 0.12 * sin(uniforms.time * 0.5)), resolution.y * 0.9)
        // Smaller emoji as the count grows so the fountain stays readable:
        // 36 pt at 1 000, 12 pt at 20 000, 8 pt from about 80 000.
        let baseSize = max(36 * pow(Float(Self.countRange.lowerBound) / Float(emojiCount), 0.37), 8) * scale
        var emojiUniforms = EmojiUniforms(
            resolution: resolution,
            emitter: emitter,
            touch: uniforms.touch,
            touchStrength: touch.isActive ? uniforms.touchStrength : 0,
            time: uniforms.time,
            deltaTime: deltaTime,
            gravity: resolution.y * 1.1,
            baseSize: baseSize,
            count: UInt32(Self.countRange.upperBound),
            emojiFirst: UInt32(palette.cells.lowerBound),
            emojiCount: UInt32(palette.cells.count),
            atlasColumns: UInt32(atlas.columns),
            frame: frameIndex
        )

        let counter = counterBuffers[Int(frameIndex % 3)]
        frameIndex &+= 1
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.fill(buffer: counter, range: 0..<counter.length, value: 0)
            blit.endEncoding()
        }

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setBuffer(particleBuffer, offset: 0, index: 0)
            if !isInitialized {
                isInitialized = true
                compute.setBytes(&emojiUniforms, length: MemoryLayout<EmojiUniforms>.stride, index: 1)
                dispatch(compute, pipeline: initPipeline, count: Self.countRange.upperBound)
            }
            emojiUniforms.count = UInt32(emojiCount)
            compute.setBytes(&emojiUniforms, length: MemoryLayout<EmojiUniforms>.stride, index: 1)
            compute.setBuffer(counter, offset: 0, index: 2)
            dispatch(compute, pipeline: updatePipeline, count: emojiCount)
            compute.endEncoding()
        }

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&emojiUniforms, length: MemoryLayout<EmojiUniforms>.stride, index: 1)
        encoder.setFragmentTexture(atlas.texture, index: 0)
        // Single draw call: a 4-vertex strip instanced once per emoji.
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: emojiCount)
        encoder.endEncoding()

        commandBuffer.addCompletedHandler(Self.counterReader(buffer: counter, into: visibleCount))
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, count: Int) {
        let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        encoder.setComputePipelineState(pipeline)
        encoder.dispatchThreadgroups(
            MTLSize(width: (count + width - 1) / width, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
    }

    /// Built outside the main actor: Metal calls completion handlers on its own thread.
    private nonisolated static func counterReader(buffer: MTLBuffer, into visibleCount: VisibleCount) -> MTLCommandBufferHandler {
        { _ in
            visibleCount.store(Int(buffer.contents().load(as: UInt32.self)))
        }
    }
}
