//
//  StandardLiquidWaveView.swift
//  demo
//

import UIKit

/// Baseline implementation: every frame the wave polylines are rebuilt as `UIBezierPath`s on the
/// main thread and handed to `CAShapeLayer`s (water mask, back wave and foam strokes).
final class StandardLiquidWaveView: DisplayLinkAnimationView {
    private let air = CAGradientLayer()
    private let backWave = CAShapeLayer()
    private let water = CAGradientLayer()
    private let waterMask = CAShapeLayer()
    private let crestFoam = CAShapeLayer()
    private let foam = CAShapeLayer()

    /// Horizontal distance between sampled surface points, in points.
    private let sampleStep: CGFloat = 4

    override func setUp() {
        air.colors = [
            UIColor(red: 0.02, green: 0.04, blue: 0.08, alpha: 1).cgColor,
            UIColor(red: 0.04, green: 0.07, blue: 0.13, alpha: 1).cgColor,
        ]
        layer.addSublayer(air)

        backWave.fillColor = UIColor(red: 0.10, green: 0.45, blue: 0.62, alpha: 0.55).cgColor
        layer.addSublayer(backWave)

        water.colors = [
            UIColor(red: 0.10, green: 0.78, blue: 0.80, alpha: 1).cgColor,
            UIColor(red: 0.02, green: 0.10, blue: 0.35, alpha: 1).cgColor,
        ]
        water.mask = waterMask
        layer.addSublayer(water)

        crestFoam.fillColor = nil
        crestFoam.strokeColor = UIColor(white: 1, alpha: 0.3).cgColor
        crestFoam.lineWidth = 7
        crestFoam.lineJoin = .round
        layer.addSublayer(crestFoam)

        foam.fillColor = nil
        foam.strokeColor = UIColor(red: 0.92, green: 0.98, blue: 1, alpha: 0.85).cgColor
        foam.lineWidth = 2.5
        foam.lineCap = .round
        foam.lineJoin = .round
        foam.lineDashPattern = [10, 5, 3, 6]
        layer.addSublayer(foam)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        air.frame = bounds
        water.frame = bounds
        CATransaction.commit()
        renderFrame(time: elapsedTime, deltaTime: 0)
    }

    override func renderFrame(time: CFTimeInterval, deltaTime: CFTimeInterval) {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        let wave = WaveShape(
            size: bounds.size,
            progress: CGFloat(displayedProgress),
            time: time,
            touchX: touch.location.x,
            touchStrength: CGFloat(touch.strength)
        )
        let backOffset = min(w, h) * 0.02 * wave.calm

        let surface = UIBezierPath()
        let back = UIBezierPath()
        var x: CGFloat = 0
        while true {
            let front = CGPoint(x: x, y: h - wave.height(at: x, phase: 0))
            let backPoint = CGPoint(x: x, y: h - wave.height(at: x, phase: 2.1) - backOffset)
            if x == 0 {
                surface.move(to: front)
                back.move(to: backPoint)
            } else {
                surface.addLine(to: front)
                back.addLine(to: backPoint)
            }
            if x >= w { break }
            x = min(x + sampleStep, w)
        }
        let body = surface.copy() as! UIBezierPath
        for path in [body, back] {
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.close()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        waterMask.path = body.cgPath
        backWave.path = back.cgPath
        crestFoam.path = surface.cgPath
        foam.path = surface.cgPath
        // Foam drifts along the surface; it disappears when the container is empty or full.
        foam.lineDashPhase = CGFloat(time * 40)
        foam.opacity = Float(wave.calm)
        crestFoam.opacity = Float(wave.calm)
        CATransaction.commit()
    }
}

/// Same wave model as `waveSurface` in WaveShader.metal, in points.
private struct WaveShape {
    let size: CGSize
    let progress: CGFloat
    let time: Double
    let touchX: CGFloat
    let touchStrength: CGFloat

    var calm: CGFloat {
        smoothstep(0, 0.06, progress) * (1 - smoothstep(0.94, 1, progress))
    }

    /// Height of the surface above the bottom edge.
    func height(at x: CGFloat, phase: CGFloat) -> CGFloat {
        let unit = min(size.width, size.height)
        let t = CGFloat(time)
        let xn = x / unit
        var h = 0.045 * sin(xn * 4.1 + t * 1.6 + phase)
        h += 0.030 * sin(xn * 7.3 - t * 2.3 + phase * 1.7)
        h += 0.018 * sin(xn * 12.9 + t * 3.1 + phase * 0.6)
        h += 0.010 * sin(xn * 21.7 - t * 4.2 + phase * 2.3)
        let dx = (x - touchX) / unit
        h += touchStrength * 0.12 * exp(-dx * dx * 18) * cos(dx * 22 - t * 9)
        return progress * size.height + h * unit * calm
    }
}
