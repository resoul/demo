//
//  StandardLavaProgressBarView.swift
//  demo
//

import UIKit

/// Baseline implementation: Core Animation layers driven from the main thread.
///
/// The lava is a scrolling `CAGradientLayer` heat map, two scrolling layers with CPU-generated
/// noise textures (glowing cracks and dark crust), bubble layers simulated on the CPU,
/// and a gradient meniscus at the leading edge. A `CAShapeLayer` mask gives the fill rounded ends.
final class StandardLavaProgressBarView: DisplayLinkAnimationView {
    override var textureMemoryBytes: Int { LavaTextures.byteCount }

    private struct Bubble {
        let layer = CALayer()
        var x: CGFloat
        var y: CGFloat
        var phase: Double
        var speed: Double
        var cycle = -1
    }

    private let fillLayer = CALayer()
    private let fillMask = CAShapeLayer()
    private let flowGradient = CAGradientLayer()
    private let glowStrip = CALayer()
    private let crustStrip = CALayer()
    private let meniscus = CAGradientLayer()
    private let edgeSpill = CAGradientLayer()
    private var bubbles: [Bubble] = []

    private var tileWidth: CGFloat = 0
    private var laidOutSize: CGSize = .zero

    override func setUp() {
        backgroundColor = LavaPalette.track
        layer.masksToBounds = true

        // The spill glow sits under the fill and starts behind its rounded tip, so it has no hard edge.
        layer.addSublayer(edgeSpill)
        fillLayer.mask = fillMask
        layer.addSublayer(fillLayer)

        // One period of the heat map; repeated twice so scrolling by one period is seamless.
        let period: [UIColor] = [
            LavaPalette.crust, LavaPalette.deepRed, LavaPalette.orange, LavaPalette.deepRed,
            LavaPalette.crust, LavaPalette.deepRed, LavaPalette.orange, LavaPalette.yellow,
            LavaPalette.orange, LavaPalette.deepRed, LavaPalette.crust,
        ]
        flowGradient.colors = (period + period.dropFirst()).map(\.cgColor)
        flowGradient.startPoint = CGPoint(x: 0, y: 0.5)
        flowGradient.endPoint = CGPoint(x: 1, y: 0.5)
        fillLayer.addSublayer(flowGradient)
        fillLayer.addSublayer(glowStrip)
        fillLayer.addSublayer(crustStrip)

        for i in 0..<10 {
            let bubble = Bubble(x: .random(in: 0...1), y: .random(in: 0.3...0.7), phase: Double(i) / 10, speed: .random(in: 0.5...0.9))
            bubble.layer.borderColor = LavaPalette.yellow.withAlphaComponent(0.9).cgColor
            bubble.layer.borderWidth = 1
            bubble.layer.backgroundColor = LavaPalette.orange.withAlphaComponent(0.35).cgColor
            fillLayer.addSublayer(bubble.layer)
            bubbles.append(bubble)
        }

        meniscus.colors = [
            LavaPalette.orange.withAlphaComponent(0).cgColor,
            LavaPalette.yellow.withAlphaComponent(0.85).cgColor,
            LavaPalette.hotWhite.cgColor,
        ]
        meniscus.locations = [0, 0.6, 1]
        meniscus.startPoint = CGPoint(x: 0, y: 0.5)
        meniscus.endPoint = CGPoint(x: 1, y: 0.5)
        fillLayer.addSublayer(meniscus)

        edgeSpill.colors = [
            LavaPalette.orange.withAlphaComponent(0.45).cgColor,
            LavaPalette.orange.withAlphaComponent(0).cgColor,
        ]
        edgeSpill.startPoint = CGPoint(x: 0, y: 0.5)
        edgeSpill.endPoint = CGPoint(x: 1, y: 0.5)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size

        let w = bounds.width, h = bounds.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = bounds
        flowGradient.frame = CGRect(x: 0, y: 0, width: w * 2, height: h)
        tileWidth = h * LavaTextures.aspect
        rebuildTiles(in: glowStrip, image: LavaTextures.glow)
        rebuildTiles(in: crustStrip, image: LavaTextures.crust)
        meniscus.bounds = CGRect(x: 0, y: 0, width: h * 1.4, height: h)
        edgeSpill.bounds = CGRect(x: 0, y: 0, width: h * 1.4, height: h)
        CATransaction.commit()

        updateLayers(time: elapsedTime)
    }

    private func rebuildTiles(in strip: CALayer, image: CGImage) {
        strip.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard tileWidth > 0 else { return }
        let count = Int(ceil(bounds.width / tileWidth)) + 1
        for i in 0..<count {
            let tile = CALayer()
            tile.contents = image
            tile.contentsGravity = .resize
            tile.frame = CGRect(x: CGFloat(i) * tileWidth, y: 0, width: tileWidth, height: bounds.height)
            strip.addSublayer(tile)
        }
        strip.frame = CGRect(x: 0, y: 0, width: CGFloat(count) * tileWidth, height: bounds.height)
    }

    // MARK: - Animation

    override func didStartAnimation() {
        let flicker = CAKeyframeAnimation(keyPath: "opacity")
        flicker.values = [0.55, 0.9, 0.65, 1.0, 0.7, 0.55]
        flicker.keyTimes = [0, 0.2, 0.45, 0.6, 0.8, 1]
        flicker.duration = 2.4
        flicker.calculationMode = .cubic
        flicker.repeatCount = .infinity
        glowStrip.add(flicker, forKey: "flicker")
    }

    override func didStopAnimation() {
        glowStrip.removeAnimation(forKey: "flicker")
    }

    override func renderFrame(time: CFTimeInterval, deltaTime: CFTimeInterval) {
        updateLayers(time: time)
    }

    private func updateLayers(time t: CFTimeInterval) {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        let progress = CGFloat(displayedProgress)
        let fillWidth = w * progress
        let isVisible = progress > 0.001

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        fillMask.path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: fillWidth, height: h), cornerRadius: h / 2).cgPath

        // Everything flows towards the meniscus, each layer at its own speed.
        flowGradient.frame.origin.x = CGFloat((t * 0.08).truncatingRemainder(dividingBy: 1)) * w - w
        glowStrip.frame.origin.x = scrollOffset(t * Double(h) * 1.6)
        crustStrip.frame.origin.x = scrollOffset(t * Double(h) * 0.9)

        for i in bubbles.indices {
            let life = t * bubbles[i].speed + bubbles[i].phase
            let cycle = Int(life)
            if cycle != bubbles[i].cycle {
                bubbles[i].cycle = cycle
                bubbles[i].x = .random(in: 0.05...0.95)
                bubbles[i].y = .random(in: 0.3...0.7)
            }
            let f = CGFloat(life - floor(life))
            let radius = h * 0.32 * f
            let bubbleLayer = bubbles[i].layer
            bubbleLayer.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            bubbleLayer.cornerRadius = radius
            bubbleLayer.position = CGPoint(x: bubbles[i].x * fillWidth, y: bubbles[i].y * h)
            bubbleLayer.opacity = Float((1 - f) * min(f * 4, 1))
        }

        let pulse = Float(0.85 + 0.15 * sin(t * 7))
        meniscus.position = CGPoint(x: fillWidth - meniscus.bounds.width / 2, y: h / 2)
        meniscus.opacity = isVisible ? pulse : 0
        edgeSpill.position = CGPoint(x: fillWidth - h / 2 + edgeSpill.bounds.width / 2, y: h / 2)
        edgeSpill.opacity = isVisible && progress < 0.999 ? pulse : 0

        CATransaction.commit()
    }

    /// Maps an ever-growing offset to a strip origin in [-tileWidth, 0), scrolling to the right.
    private func scrollOffset(_ offset: Double) -> CGFloat {
        guard tileWidth > 0 else { return 0 }
        return CGFloat(offset.truncatingRemainder(dividingBy: Double(tileWidth))) - tileWidth
    }
}

enum LavaPalette {
    static let track = UIColor(red: 0.07, green: 0.05, blue: 0.05, alpha: 1)
    static let crust = UIColor(red: 0.12, green: 0.01, blue: 0.0, alpha: 1)
    static let deepRed = UIColor(red: 0.55, green: 0.04, blue: 0.0, alpha: 1)
    static let orange = UIColor(red: 1.0, green: 0.35, blue: 0.0, alpha: 1)
    static let yellow = UIColor(red: 1.0, green: 0.78, blue: 0.15, alpha: 1)
    static let hotWhite = UIColor(red: 1.0, green: 0.97, blue: 0.88, alpha: 1)
}

/// Horizontally tileable noise textures, generated once on the CPU and kept in memory.
enum LavaTextures {
    static let width = 512
    static let height = 64
    static var aspect: CGFloat { CGFloat(width) / CGFloat(height) }
    static var byteCount: Int { width * height * 4 * 2 }

    /// Dark cooling crust: opaque where the noise is high.
    static let crust: CGImage = makeTexture(seed: 1) { n in
        let a = smoothstep(0.42, 0.62, n) * 0.85
        return (0.10 * a, 0.01 * a, 0, a)
    }

    /// Glowing cracks: thin ridges along the noise mid-level.
    static let glow: CGImage = makeTexture(seed: 7) { n in
        let a = pow(max(0, 1 - abs(n - 0.5) * 2), 6) * 0.9
        return (a, 0.82 * a, 0.35 * a, a)
    }

    /// `shade` maps noise in 0...1 to premultiplied RGBA.
    private static func makeTexture(seed: Int, shade: (Double) -> (Double, Double, Double, Double)) -> CGImage {
        let period = 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let n = fbm(
                    x: Double(x) / Double(width) * Double(period),
                    y: Double(y) / Double(height) * 1.5 + Double(seed) * 13.7,
                    period: period,
                    seed: seed
                )
                let (r, g, b, a) = shade(n)
                let i = (y * width + x) * 4
                pixels[i] = UInt8(clamping: Int(r * 255))
                pixels[i + 1] = UInt8(clamping: Int(g * 255))
                pixels[i + 2] = UInt8(clamping: Int(b * 255))
                pixels[i + 3] = UInt8(clamping: Int(a * 255))
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    /// Value-noise fBm, periodic in x with `period` lattice cells at the base octave.
    private static func fbm(x: Double, y: Double, period: Int, seed: Int) -> Double {
        var sum = 0.0, amplitude = 0.5, total = 0.0
        var x = x, y = y, period = period
        for _ in 0..<4 {
            sum += amplitude * valueNoise(x: x, y: y, period: period, seed: seed)
            total += amplitude
            x *= 2
            y *= 2
            period *= 2
            amplitude *= 0.5
        }
        return sum / total
    }

    private static func valueNoise(x: Double, y: Double, period: Int, seed: Int) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
        func corner(_ i: Int, _ j: Int) -> Double {
            hash(((i % period) + period) % period, j, seed)
        }
        let top = corner(xi, yi) + (corner(xi + 1, yi) - corner(xi, yi)) * ux
        let bottom = corner(xi, yi + 1) + (corner(xi + 1, yi + 1) - corner(xi, yi + 1)) * ux
        return top + (bottom - top) * uy
    }

    private static func hash(_ x: Int, _ y: Int, _ seed: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 144_665)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Double(h & 0xFFFF) / 65535
    }
}
