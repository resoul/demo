import UIKit

/// A layer-based baseline. Core Animation composites these layers on the GPU;
/// the measured CPU work here is updating their geometry once per display tick.
final class StandardLavaProgressBarView: AnimationView {
    private let lava = CALayer()
    private let fillMask = CAShapeLayer()
    private let gradient = CAGradientLayer()
    private let meniscus = CAGradientLayer()
    private var currents: [CAGradientLayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isAccessibilityElement = true
        accessibilityLabel = "Прогресс, UIKit"
        backgroundColor = UIColor(red: 0.075, green: 0.045, blue: 0.04, alpha: 1)
        clipsToBounds = true
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.addSublayer(lava)
        lava.mask = fillMask
        fillMask.fillColor = UIColor.black.cgColor
        gradient.colors = [UIColor(red: 0.22, green: 0.015, blue: 0.01, alpha: 1).cgColor,
                           UIColor(red: 0.96, green: 0.13, blue: 0.015, alpha: 1).cgColor,
                           UIColor(red: 1, green: 0.43, blue: 0.025, alpha: 1).cgColor,
                           UIColor(red: 0.5, green: 0.025, blue: 0, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        lava.addSublayer(gradient)

        for index in 0..<14 {
            let current = CAGradientLayer()
            current.type = .radial
            current.startPoint = CGPoint(x: 0.5, y: 0.5)
            current.endPoint = CGPoint(x: 1, y: 1)
            let hot = index.isMultiple(of: 3)
            let color = hot ? UIColor(red: 1, green: 0.79, blue: 0.13, alpha: 0.95)
                            : UIColor(red: 0.15, green: 0.005, blue: 0, alpha: 0.85)
            current.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
            current.locations = [0.1, 1]
            lava.addSublayer(current)
            currents.append(current)
        }

        meniscus.colors = [UIColor.clear.cgColor,
                           UIColor(red: 1, green: 0.7, blue: 0.14, alpha: 1).cgColor,
                           UIColor(red: 1, green: 0.97, blue: 0.79, alpha: 1).cgColor]
        meniscus.locations = [0, 0.8, 1]
        meniscus.startPoint = CGPoint(x: 0, y: 0.5)
        meniscus.endPoint = CGPoint(x: 1, y: 0.5)
        lava.addSublayer(meniscus)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lava.frame = bounds
        gradient.frame = bounds.insetBy(dx: -bounds.width * 0.25, dy: 0)
        let width = bounds.width * CGFloat(progress)
        fillMask.frame = bounds
        fillMask.path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: bounds.height),
                                    cornerRadius: min(16, width / 2)).cgPath
        meniscus.frame = CGRect(x: width - 16, y: 0, width: 16, height: bounds.height)
        meniscus.isHidden = progress <= 0 || progress >= 1
        for (index, current) in currents.enumerated() {
            let diameter = bounds.height * (index.isMultiple(of: 3) ? 1.15 : 1.65)
            current.bounds = CGRect(x: 0, y: 0, width: diameter * 1.7, height: diameter)
        }
        CATransaction.commit()
        accessibilityValue = "\(Int(progress * 100)) процентов"
    }

    /// The caller uses one shared CADisplayLink for both implementations.
    override func updateFrame(time: CFTimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.transform = CATransform3DMakeTranslation(CGFloat(sin(time * 0.5)) * bounds.width * 0.16, 0, 0)
        for (index, current) in currents.enumerated() {
            let seed = Double(index)
            let phase = (seed / Double(currents.count) + time * (0.028 + seed * 0.001))
                .truncatingRemainder(dividingBy: 1)
            current.position = CGPoint(x: CGFloat(phase) * (bounds.width + 120) - 60,
                                       y: bounds.midY + CGFloat(sin(time * 0.8 + seed * 2.4)) * bounds.height * 0.48)
            current.transform = CATransform3DMakeRotation(CGFloat(sin(time * 0.3 + seed)) * 0.8, 0, 0, 1)
        }
        meniscus.opacity = Float(0.84 + sin(time * 4) * 0.16)
        CATransaction.commit()
    }
}
