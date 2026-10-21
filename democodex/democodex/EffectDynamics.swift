import UIKit

enum EffectDynamics {
    static func waveHeight(x: CGFloat, time: Double, progress: Float, touch: CGPoint, strength: Float) -> CGFloat {
        let x = Double(x)
        let wave = sin(x * 9 + time * 1.4) * 0.018
                 + sin(x * 17 - time * 1.9) * 0.010
                 + sin(x * 27 + time * 2.7) * 0.006
                 + sin(x * 41 - time * 3.2) * 0.003
        let dx = x - touch.x
        let ripple = Double(strength) * (sin(dx * 32 - time * 7) * exp(-dx * dx * 12) * 0.055
                                        + dx * 0.12)
        return CGFloat(1 - Double(progress) + (wave + ripple) * sin(Double(progress) * .pi))
    }

    struct Blob {
        let center: CGPoint // normalized to container; distances use height units
        let radius: CGFloat
    }

    static func blobs(time: Double, progress: Float, touch: CGPoint, strength: Float) -> [Blob] {
        (0..<5).map { index in
            let i = Double(index)
            let t = time * 0.45
            let x = 0.5 + 0.32 * sin(t * (0.7 + i * 0.13) + i * 1.7)
            let y = 0.5 + 0.27 * cos(t * (0.9 + i * 0.09) + i * 2.1)
            let attraction = Double(strength) * 0.78
            return Blob(center: CGPoint(x: x + (touch.x - x) * attraction,
                                        y: y + (touch.y - y) * attraction),
                        radius: (0.08 + Double(progress) * 0.075) * (0.85 + i * 0.07))
        }
    }

    static func potential(at point: CGPoint, blobs: [Blob], aspect: CGFloat) -> CGFloat {
        blobs.reduce(0) { sum, blob in
            let dx = (point.x - blob.center.x) * aspect
            let dy = point.y - blob.center.y
            return sum + blob.radius * blob.radius / max(dx * dx + dy * dy, 0.0001)
        }
    }
}
