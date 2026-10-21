import UIKit

final class StandardPlasmaView: AnimationView {
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
        backgroundColor = UIColor(red: 0.025, green: 0.015, blue: 0.12, alpha: 1)
        accessibilityLabel = "Неоновая плазма, UIKit"
        let colors = [UIColor(red: 0.5, green: 0.05, blue: 1, alpha: 1),
                      UIColor(red: 0.01, green: 0.88, blue: 1, alpha: 1),
                      UIColor(red: 0.1, green: 0.16, blue: 1, alpha: 1)]
        for index in 0..<10 {
            let gradient = CAGradientLayer()
            gradient.type = .radial
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            let color = colors[index % colors.count]
            gradient.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
            gradient.locations = [0, 1]
            layer.addSublayer(gradient)
            currents.append(gradient)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFrame(time: animationTime)
    }

    override func updateFrame(time: CFTimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, current) in currents.enumerated() {
            let i = Double(index)
            let t = time * 0.45
            let x = 0.5 + sin(t * (0.6 + i * 0.08) + i * 2.4) * 0.45
            let y = 0.5 + cos(t + i * 1.7) * 0.5
            let strength = Double(interactionStrength) * 0.7
            current.position = CGPoint(x: (x + (interactionPoint.x - x) * strength) * bounds.width,
                                       y: (y + (interactionPoint.y - y) * strength) * bounds.height)
            current.bounds = CGRect(x: 0, y: 0, width: bounds.width * 0.9, height: bounds.height * 1.7)
            current.transform = CATransform3DMakeRotation(CGFloat(t * 0.4 + i), 0, 0, 1)
            current.opacity = (0.35 + progress * 0.65) * Float(0.65 + sin(t * 2 + i) * 0.3)
        }
        CATransaction.commit()
    }
}
