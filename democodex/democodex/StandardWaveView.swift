import UIKit

final class StandardWaveView: AnimationView {
    private let water = CAGradientLayer()
    private let waterMask = CAShapeLayer()
    private let backWave = CAShapeLayer()
    private let foam = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = UIColor(red: 0.02, green: 0.06, blue: 0.12, alpha: 1)
        accessibilityLabel = "Вода, UIKit"
        backWave.fillColor = UIColor(red: 0.02, green: 0.45, blue: 0.65, alpha: 0.5).cgColor
        layer.addSublayer(backWave)
        water.colors = [UIColor(red: 0.06, green: 0.91, blue: 0.88, alpha: 1).cgColor,
                        UIColor(red: 0.005, green: 0.15, blue: 0.54, alpha: 1).cgColor]
        water.startPoint = CGPoint(x: 0.5, y: 0)
        water.endPoint = CGPoint(x: 0.5, y: 1)
        water.mask = waterMask
        layer.addSublayer(water)
        foam.fillColor = UIColor.clear.cgColor
        foam.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor
        foam.lineWidth = 2
        layer.addSublayer(foam)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        water.frame = bounds
        waterMask.frame = bounds
        backWave.frame = bounds
        foam.frame = bounds
        updateFrame(time: animationTime)
        CATransaction.commit()
    }

    override func interactionDidChange() {
        progress = Float(1 - interactionPoint.y)
        onProgressChanged?(progress)
    }

    override func updateFrame(time: CFTimeInterval) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let surface = UIBezierPath()
        let back = UIBezierPath()
        let steps = max(32, Int(bounds.width / 3))
        for index in 0...steps {
            let x = CGFloat(index) / CGFloat(steps)
            let y = EffectDynamics.waveHeight(x: x, time: time, progress: progress,
                                              touch: interactionPoint, strength: interactionStrength)
            let by = EffectDynamics.waveHeight(x: x, time: time + 1.5, progress: progress,
                                               touch: interactionPoint, strength: interactionStrength)
            let point = CGPoint(x: x * bounds.width, y: y * bounds.height)
            let backPoint = CGPoint(x: point.x, y: by * bounds.height)
            if index == 0 { surface.move(to: point); back.move(to: backPoint) }
            else { surface.addLine(to: point); back.addLine(to: backPoint) }
        }
        let fill = surface.copy() as! UIBezierPath
        for path in [fill, back] {
            path.addLine(to: CGPoint(x: bounds.width, y: bounds.height))
            path.addLine(to: CGPoint(x: 0, y: bounds.height))
            path.close()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        waterMask.path = fill.cgPath
        backWave.path = back.cgPath
        foam.path = surface.cgPath
        foam.isHidden = progress <= 0 || progress >= 1
        water.isHidden = progress <= 0
        backWave.isHidden = progress <= 0
        CATransaction.commit()
    }
}
