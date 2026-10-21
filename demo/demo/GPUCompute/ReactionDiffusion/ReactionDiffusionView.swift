//
//  ReactionDiffusionView.swift
//  demo
//

import UIKit
import Metal

/// Mirrors `ReactionParams` in ReactionDiffusion.metal (32 bytes).
private struct ReactionParams {
    var feed: Float
    var kill: Float
    var brushCenter: SIMD2<Float>
    var brushRadius: Float
    var brushStrength: Float
    var seed: UInt32
    var padding: Float = 0
}

/// Gray–Scott reaction–diffusion at half the view's pixel resolution, many steps per frame.
/// Every step reads 9 cells and writes 1 for the whole grid, so this mostly measures memory
/// bandwidth. The finger paints the second chemical.
final class ReactionDiffusionView: MetalAnimationView, MetalLabEffectView {
    private enum Preset: Int, CaseIterable {
        case corals
        case spots
        case maze
        case worms

        var title: String {
            switch self {
            case .corals: "Кораллы"
            case .spots: "Пятна"
            case .maze: "Лабиринт"
            case .worms: "Черви"
            }
        }

        /// (feed, kill)
        var rates: (Float, Float) {
            switch self {
            case .corals: (0.0545, 0.062)
            case .spots: (0.0367, 0.0649)
            case .maze: (0.029, 0.057)
            case .worms: (0.078, 0.061)
            }
        }
    }

    /// Bytes touched per cell update: 9 texel reads and 1 write of rg16Float.
    private static let bytesPerCellUpdate = 10 * 4.0

    private var preset: Preset = .corals
    private var stepsPerFrame = 16
    private var textures: [MTLTexture] = []
    private var current = 0
    private var needsSeed = true
    private var seed: UInt32 = 1
    private var frames = RateMeter()

    private let seedPipeline = MetalEffectContext.shared?.computePipeline(function: "reaction_seed")
    private let stepPipeline = MetalEffectContext.shared?.computePipeline(function: "reaction_step")
    private let displayPipeline = MetalEffectContext.shared?.renderPipeline(vertex: "fullscreen_vertex", fragment: "reaction_fragment")

    private var cellCount: Int {
        textures.first.map { $0.width * $0.height } ?? 0
    }

    var activeEntityDescription: String {
        "\(compactCount(Double(cellCount))) клеток × \(stepsPerFrame) шагов"
    }

    var throughputDescription: String? {
        let updates = Double(cellCount * stepsPerFrame) * frames.framesPerSecond
        let gigabytes = updates * Self.bytesPerCellUpdate / 1e9
        return "\(compactCount(updates)) клеток/с · ≈\(String(format: "%.0f", gigabytes)) ГБ/с"
    }

    var controls: [LabControl] {
        [
            .segments(items: Preset.allCases.map(\.title), selected: preset.rawValue) { [weak self] index in
                self?.preset = Preset(rawValue: index) ?? .corals
                self?.needsSeed = true
            },
            .slider(
                title: "Шагов/кадр",
                range: 1...64,
                value: Float(stepsPerFrame),
                format: { "\(Int($0.rounded()))" },
                onChange: { [weak self] value in self?.stepsPerFrame = Int(value.rounded()) }
            ),
            .button(title: "Посеять заново") { [weak self] in
                self?.needsSeed = true
            },
        ]
    }

    override var textureMemoryBytes: Int { cellCount * 4 * 2 }

    override func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        guard let seedPipeline, let stepPipeline, let displayPipeline else { return }
        let width = Int(uniforms.resolution.x) / 2
        let height = Int(uniforms.resolution.y) / 2
        if textures.first?.width != width || textures.first?.height != height {
            textures = (0..<2).compactMap { _ in
                MetalEffectContext.shared?.makeTexture(width: width, height: height, format: .rg16Float)
            }
            needsSeed = true
        }
        guard textures.count == 2 else { return }

        let (feed, kill) = preset.rates
        var params = ReactionParams(
            feed: feed,
            kill: kill,
            brushCenter: uniforms.touch / 2,
            brushRadius: Float(min(width, height)) * 0.04,
            brushStrength: touch.isActive ? 1 : 0,
            seed: seed
        )

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setBytes(&params, length: MemoryLayout<ReactionParams>.stride, index: 0)
            if needsSeed {
                needsSeed = false
                seed &+= 1
                params.seed = seed
                compute.setBytes(&params, length: MemoryLayout<ReactionParams>.stride, index: 0)
                compute.setTexture(textures[current], index: 0)
                compute.dispatch(seedPipeline, width: width, height: height)
            }
            for _ in 0..<stepsPerFrame {
                compute.setTexture(textures[current], index: 0)
                compute.setTexture(textures[1 - current], index: 1)
                compute.dispatch(stepPipeline, width: width, height: height)
                current = 1 - current
            }
            compute.endEncoding()
        }
        frames.tick(at: CACurrentMediaTime())

        encodeFullscreen(displayPipeline, into: commandBuffer, pass: pass, uniforms: &uniforms, textures: [textures[current]])
    }
}
