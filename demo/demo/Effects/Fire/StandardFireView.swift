//
//  StandardFireView.swift
//  demo
//

import UIKit

/// Baseline implementation: `CAEmitterLayer` particles (flames and sparks blended additively, smoke
/// on a separate normal-blended emitter). Particles are simulated by Core Animation in the render
/// server; the app only changes emitter parameters when progress or the touch changes.
/// Heat haze is not possible here without private filters.
final class StandardFireView: DisplayLinkAnimationView {
    override var usesDisplayLink: Bool { false }
    override var textureMemoryBytes: Int { FireSprites.byteCount }

    private let glow = CAGradientLayer()
    private let smokeEmitter = CAEmitterLayer()
    private let fireEmitter = CAEmitterLayer()
    private let smoke = CAEmitterCell()
    private let flame = CAEmitterCell()
    private let sparks = CAEmitterCell()

    override func setUp() {
        backgroundColor = UIColor(red: 0.03, green: 0.025, blue: 0.03, alpha: 1)

        glow.colors = [
            UIColor(red: 1, green: 0.35, blue: 0, alpha: 0).cgColor,
            UIColor(red: 1, green: 0.35, blue: 0, alpha: 0.35).cgColor,
        ]
        layer.addSublayer(glow)

        Self.configure(smoke, image: FireSprites.soft) {
            $0.lifetime = 2.6
            $0.lifetimeRange = 0.6
            $0.color = UIColor(red: 0.32, green: 0.30, blue: 0.30, alpha: 0.14).cgColor
            $0.alphaSpeed = -0.08
            $0.spinRange = 0.8
        }
        smokeEmitter.emitterShape = .line
        smokeEmitter.emitterMode = .outline
        smokeEmitter.emitterCells = [smoke]
        smokeEmitter.birthRate = 0
        layer.addSublayer(smokeEmitter)

        Self.configure(flame, image: FireSprites.soft) {
            $0.lifetime = 0.9
            $0.lifetimeRange = 0.3
            $0.color = UIColor(red: 1, green: 0.7, blue: 0.3, alpha: 0.8).cgColor
            $0.greenSpeed = -0.7
            $0.blueSpeed = -0.5
            $0.alphaSpeed = -0.75
            $0.spinRange = 1.5
        }
        Self.configure(sparks, image: FireSprites.spark) {
            $0.lifetime = 1.6
            $0.lifetimeRange = 0.6
            $0.color = UIColor(red: 1, green: 0.7, blue: 0.3, alpha: 1).cgColor
            $0.greenSpeed = -0.4
            $0.alphaSpeed = -0.55
        }
        fireEmitter.emitterShape = .line
        fireEmitter.emitterMode = .outline
        fireEmitter.renderMode = .additive
        fireEmitter.emitterCells = [flame, sparks]
        fireEmitter.birthRate = 0
        layer.addSublayer(fireEmitter)
    }

    /// Particles rise through negative `yAcceleration`; velocity is only random spread in all
    /// directions, so the look does not depend on the emission angle.
    private static func configure(_ cell: CAEmitterCell, image: CGImage, _ configure: (CAEmitterCell) -> Void) {
        cell.contents = image
        cell.emissionRange = 2 * .pi
        configure(cell)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = CGRect(x: 0, y: bounds.height * 0.55, width: bounds.width, height: bounds.height * 0.45)
        smokeEmitter.frame = bounds
        fireEmitter.frame = bounds
        CATransaction.commit()
        applyParameters()
    }

    override func didStartAnimation() {
        smokeEmitter.birthRate = 1
        fireEmitter.birthRate = 1
    }

    override func didStopAnimation() {
        smokeEmitter.birthRate = 0
        fireEmitter.birthRate = 0
    }

    override func progressDidChange() {
        applyParameters()
    }

    override func touchDidChange() {
        applyParameters()
    }

    /// Progress sets the flame height through upward acceleration; the finger adds sideways wind.
    private func applyParameters() {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        let unit = min(w, h)
        let flameHeight = h * CGFloat(0.25 + 0.75 * progress)
        let widthScale = w / 100
        let wind = touch.isActive ? (touch.location.x - w / 2) * 3 : 0
        let flameScale = unit * 0.45 / CGFloat(FireSprites.softSize)
        let sparkScale = unit * 0.03 / CGFloat(FireSprites.sparkSize)
        let smokeScale = unit * 0.3 / CGFloat(FireSprites.softSize)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fireEmitter.emitterPosition = CGPoint(x: w / 2, y: h + unit * 0.04)
        fireEmitter.emitterSize = CGSize(width: w * 0.95, height: 0)
        smokeEmitter.emitterPosition = CGPoint(x: w / 2, y: h - flameHeight * 0.7)
        smokeEmitter.emitterSize = CGSize(width: w * 0.7, height: 0)
        flame.birthRate = Float(50 * widthScale)
        flame.velocity = flameHeight * 0.1
        flame.velocityRange = flameHeight * 0.1
        flame.yAcceleration = -flameHeight * 2.4
        flame.scale = flameScale
        flame.scaleSpeed = -flameScale * 0.7
        flame.xAcceleration = wind
        sparks.birthRate = Float(5 * widthScale)
        sparks.velocity = flameHeight * 0.25
        sparks.velocityRange = flameHeight * 0.2
        sparks.yAcceleration = -flameHeight * 1.2
        sparks.scale = sparkScale
        sparks.xAcceleration = wind
        smoke.birthRate = Float(3 * widthScale)
        smoke.velocity = flameHeight * 0.08
        smoke.yAcceleration = -flameHeight * 0.15
        smoke.scale = smokeScale
        smoke.scaleSpeed = smokeScale * 0.5
        smoke.xAcceleration = wind * 0.6
        // Emitter layers copy their cells, so changed cells must be assigned again.
        fireEmitter.emitterCells = [flame, sparks]
        smokeEmitter.emitterCells = [smoke]
        CATransaction.commit()
    }
}

/// Soft round particle sprites, drawn once.
private enum FireSprites {
    static let softSize = 64
    static let sparkSize = 16
    static let soft = makeRadialSprite(size: softSize)
    static let spark = makeRadialSprite(size: sparkSize)
    static var byteCount: Int { (softSize * softSize + sparkSize * sparkSize) * 4 }

    private static func makeRadialSprite(size: Int) -> CGImage {
        let side = CGFloat(size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1])!
            let center = CGPoint(x: side / 2, y: side / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side / 2, options: [])
        }
        return image.cgImage!
    }
}
