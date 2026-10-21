//
//  StandardPlasmaView.swift
//  demo
//

import UIKit

/// Baseline implementation: radial `CAGradientLayer` orbs on elliptical orbits plus a rotating conic
/// swirl. All motion is declared once as Core Animation animations and runs in the render server,
/// so there is no per-frame work on the main thread.
final class StandardPlasmaView: DisplayLinkAnimationView {
    override var usesDisplayLink: Bool { false }

    private static let orbColors: [UIColor] = [
        UIColor(red: 0.62, green: 0.10, blue: 0.95, alpha: 1),
        UIColor(red: 0.10, green: 0.95, blue: 0.95, alpha: 1),
        UIColor(red: 0.07, green: 0.10, blue: 0.85, alpha: 1),
        UIColor(red: 0.85, green: 0.20, blue: 1.00, alpha: 1),
        UIColor(red: 0.20, green: 0.75, blue: 1.00, alpha: 1),
        UIColor(red: 0.30, green: 0.10, blue: 0.80, alpha: 1),
    ]

    private let energyLayer = CALayer()
    private let swirl = CAGradientLayer()
    private var orbs: [CAGradientLayer] = []
    private let touchGlow = CAGradientLayer()
    private var laidOutSize: CGSize = .zero

    override func setUp() {
        backgroundColor = UIColor(red: 0.01, green: 0.0, blue: 0.04, alpha: 1)
        layer.addSublayer(energyLayer)

        swirl.type = .conic
        swirl.startPoint = CGPoint(x: 0.5, y: 0.5)
        swirl.endPoint = CGPoint(x: 0.5, y: 0)
        swirl.colors = [
            UIColor(red: 0.10, green: 0.95, blue: 0.95, alpha: 0.35),
            UIColor(red: 0.62, green: 0.10, blue: 0.95, alpha: 0.05),
            UIColor(red: 0.07, green: 0.10, blue: 0.65, alpha: 0.35),
            UIColor(red: 0.62, green: 0.10, blue: 0.95, alpha: 0.05),
            UIColor(red: 0.10, green: 0.95, blue: 0.95, alpha: 0.35),
        ].map(\.cgColor)
        energyLayer.addSublayer(swirl)

        for color in Self.orbColors {
            let orb = CAGradientLayer()
            orb.type = .radial
            orb.startPoint = CGPoint(x: 0.5, y: 0.5)
            orb.endPoint = CGPoint(x: 1, y: 1)
            orb.colors = [color.cgColor, color.withAlphaComponent(0.4).cgColor, color.withAlphaComponent(0).cgColor]
            orb.locations = [0, 0.45, 1]
            energyLayer.addSublayer(orb)
            orbs.append(orb)
        }

        touchGlow.type = .radial
        touchGlow.startPoint = CGPoint(x: 0.5, y: 0.5)
        touchGlow.endPoint = CGPoint(x: 1, y: 1)
        touchGlow.colors = [
            UIColor(red: 0.75, green: 0.95, blue: 1, alpha: 0.9).cgColor,
            UIColor(red: 0.10, green: 0.95, blue: 0.95, alpha: 0).cgColor,
        ]
        touchGlow.opacity = 0
        layer.addSublayer(touchGlow)
        progressDidChange()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size

        let side = max(bounds.width, bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        energyLayer.frame = bounds
        swirl.bounds = CGRect(x: 0, y: 0, width: side * 1.5, height: side * 1.5)
        swirl.position = CGPoint(x: bounds.midX, y: bounds.midY)
        for orb in orbs {
            // Elliptical, so the rotation is visible.
            orb.bounds = CGRect(x: 0, y: 0, width: side * 0.9, height: side * 0.55)
            orb.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        let glowSize = min(bounds.width, bounds.height) * 0.6
        touchGlow.bounds = CGRect(x: 0, y: 0, width: glowSize, height: glowSize)
        CATransaction.commit()

        if isAnimating {
            addAnimations()
        }
    }

    override func didStartAnimation() {
        addAnimations()
    }

    override func didStopAnimation() {
        swirl.removeAllAnimations()
        orbs.forEach { $0.removeAllAnimations() }
    }

    override func progressDidChange() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        energyLayer.opacity = 0.35 + 0.65 * progress
        CATransaction.commit()
    }

    override func touchDidChange() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        touchGlow.position = touch.location
        CATransaction.commit()
        touchGlow.opacity = touch.isActive ? 1 : 0
    }

    private func addAnimations() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = 12
        spin.repeatCount = .infinity
        swirl.add(spin, forKey: "spin")

        for (i, orb) in orbs.enumerated() {
            let index = Double(i)
            let clockwise = i.isMultiple(of: 2)

            let orbit = CAKeyframeAnimation(keyPath: "position")
            let path = CGMutablePath()
            let radius = CGSize(width: bounds.width * (0.18 + 0.05 * index), height: bounds.height * (0.30 - 0.03 * index))
            let transform = CGAffineTransform(translationX: bounds.midX, y: bounds.midY).scaledBy(x: radius.width, y: radius.height)
            let start = index * 1.1
            path.addArc(center: .zero, radius: 1, startAngle: start, endAngle: start + (clockwise ? 2 : -2) * .pi, clockwise: !clockwise, transform: transform)
            orbit.path = path
            orbit.duration = 7 + index * 1.3
            orbit.calculationMode = .paced
            orbit.repeatCount = .infinity
            orb.add(orbit, forKey: "orbit")

            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = (clockwise ? 2 : -2) * Double.pi
            rotation.duration = 9 + index * 2
            rotation.repeatCount = .infinity
            orb.add(rotation, forKey: "rotation")

            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [0.85, 1.15, 0.9, 0.85]
            pulse.duration = 4 + index
            pulse.calculationMode = .cubic
            pulse.repeatCount = .infinity
            orb.add(pulse, forKey: "pulse")

            let flicker = CAKeyframeAnimation(keyPath: "opacity")
            flicker.values = [0.7, 1.0, 0.8, 0.7]
            flicker.duration = 3 + index * 0.7
            flicker.calculationMode = .cubic
            flicker.repeatCount = .infinity
            orb.add(flicker, forKey: "flicker")
        }
    }
}
