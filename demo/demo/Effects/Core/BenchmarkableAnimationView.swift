//
//  BenchmarkableAnimationView.swift
//  demo
//

import UIKit

/// Common interface for every effect implementation, so the benchmark can swap them freely.
protocol BenchmarkableAnimationView: UIView {
    /// 0...1. Each effect maps it to its own parameter (fill level, flame height, energy...).
    var progress: Float { get set }
    func startAnimation()
    func stopAnimation()
    /// Sink for per-frame CPU (and GPU, if any) work measurements.
    var workRecorder: FrameWorkRecorder? { get set }
    /// Bitmap memory the view keeps for textures and sprites, in bytes.
    var textureMemoryBytes: Int { get }
}

/// Finger state shared by both engines. `strength` eases in and out so effects react smoothly.
struct TouchInput {
    var location: CGPoint = .zero
    var isActive = false
    private(set) var strength: Float = 0

    mutating func track(_ touches: Set<UITouch>, in view: UIView, isActive: Bool) {
        if let touch = touches.first {
            location = touch.location(in: view)
        }
        self.isActive = isActive
    }

    mutating func advance(deltaTime: Double) {
        strength = eased(strength, toward: isActive ? 1 : 0, deltaTime: deltaTime, rate: isActive ? 12 : 3)
    }
}

/// Frame-rate independent exponential easing.
func eased(_ current: Float, toward target: Float, deltaTime: Double, rate: Double = 10) -> Float {
    let k = Float(1 - exp(-deltaTime * rate))
    let next = current + (target - current) * k
    return abs(next - target) < 0.0005 ? target : next
}

func smoothstep<T: BinaryFloatingPoint>(_ edge0: T, _ edge1: T, _ x: T) -> T {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
