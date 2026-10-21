import UIKit

final class StandardFireView: AnimationView {
    private let flame = CAEmitterLayer()
    private let smoke = CAEmitterLayer()
    private let sparks = CAEmitterLayer()
    private var lastWind: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = UIColor(red: 0.035, green: 0.02, blue: 0.035, alpha: 1)
        accessibilityLabel = "Огонь и искры, UIKit"
        let texture = Self.particleTexture()
        for (index, emitter) in [smoke, flame, sparks].enumerated() {
            emitter.seed = UInt32(42 + index)
            emitter.emitterShape = .line
            emitter.emitterMode = .outline
            emitter.renderMode = emitter === smoke ? .unordered : .additive
            emitter.birthRate = 0
            emitter.speed = 0
            let cell = CAEmitterCell()
            cell.name = "particle"
            cell.contents = texture
            cell.emissionLongitude = 0
            cell.emissionRange = .pi / 7
            cell.lifetime = emitter === smoke ? 2.4 : 1.8
            cell.lifetimeRange = 0.35
            cell.birthRate = emitter === sparks ? 20 : (emitter === smoke ? 40 : 140)
            cell.velocity = emitter === sparks ? 180 : (emitter === smoke ? 65 : 135)
            cell.velocityRange = 30
            cell.yAcceleration = emitter === sparks ? 22 : -15
            cell.scale = emitter === sparks ? 0.07 : (emitter === smoke ? 1.4 : 1.2)
            cell.scaleRange = emitter === sparks ? 0.02 : 0.4
            cell.scaleSpeed = emitter === smoke ? 0.35 : -0.3
            cell.alphaSpeed = emitter === smoke ? -0.08 : (emitter === sparks ? -0.6 : -0.3)
            cell.color = (emitter === smoke ? UIColor(white: 0.35, alpha: 0.24)
                           : emitter === sparks ? UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
                           : UIColor(red: 1, green: 0.6, blue: 0.08, alpha: 0.8)).cgColor
            cell.greenSpeed = -0.18
            cell.redSpeed = -0.15
            emitter.emitterCells = [cell]
            layer.addSublayer(emitter)
        }
    }

    private static func particleTexture() -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                                  endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
        }.cgImage
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for emitter in [smoke, flame, sparks] {
            emitter.frame = bounds
            emitter.emitterSize = CGSize(width: bounds.width * 0.8, height: 0)
        }
        CATransaction.commit()
    }

    override func animationDidStart() {
        for emitter in [smoke, flame, sparks] {
            guard emitter.speed == 0 else { continue }
            let pausedTime = emitter.timeOffset
            emitter.speed = 1
            emitter.timeOffset = 0
            emitter.beginTime = 0
            emitter.beginTime = emitter.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        }
        progressDidChange()
    }

    override func animationDidStop() {
        for emitter in [smoke, flame, sparks] {
            let paused = emitter.convertTime(CACurrentMediaTime(), from: nil)
            emitter.speed = 0
            emitter.timeOffset = paused
            emitter.birthRate = 0
        }
    }

    override func progressDidChange() {
        for emitter in [smoke, flame, sparks] { emitter.birthRate = isAnimating ? progress : 0 }
        // Remove residual particles as well, so zero intensity is immediately empty.
        for emitter in [smoke, flame, sparks] { emitter.isHidden = progress == 0 }
    }

    override func updateFrame(time: CFTimeInterval) {
        let wind = (interactionPoint.x - 0.5) * CGFloat(interactionStrength)
        let windChanged = lastWind.map { abs($0 - wind) > 0.001 } ?? true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for emitter in [smoke, flame, sparks] {
            emitter.emitterPosition = CGPoint(x: bounds.midX + wind * bounds.width * 0.45, y: bounds.height + 4)
            if windChanged { emitter.setValue(wind * 90, forKeyPath: "emitterCells.particle.xAcceleration") }
        }
        if windChanged { lastWind = wind }
        CATransaction.commit()
    }
}
