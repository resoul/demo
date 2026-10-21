//
//  MetalLiquidView.swift
//  demo
//

import UIKit
import CoreMotion

/// Deep water that reacts to device tilt (CoreMotion gravity) and to taps.
///
/// The CPU runs a tiny simulation per frame: an underdamped spring for the surface angle (so the
/// water overshoots and sloshes back) and a list of tap ripples. Everything else, including wave
/// layers, foam and caustics, is computed in `liquid_fragment` (LiquidWaves.metal).
/// Without a motion sensor (the Simulator), dragging horizontally tilts the water instead.
final class MetalLiquidView: MetalAnimationView, MetalLabEffectView {
    override class var fragmentFunction: String? { "liquid_fragment" }

    private struct Ripple {
        let x: Float
        let startTime: Float
    }

    private static let maxRipples = EffectUniforms.maxBlobs
    private static let rippleLifetime: Float = 4
    private static let waterLevel: Float = 0.55

    private let motion = CMMotionManager()
    private var angle: Double = 0
    private var angularVelocity: Double = 0
    private var ripples: [Ripple] = []
    private var wasTouching = false

    var activeEntityDescription: String {
        "3 слоя волн · ряби: \(ripples.count)"
    }

    override func startAnimation() {
        super.startAnimation()
        if motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 1.0 / 60
            motion.startDeviceMotionUpdates()
        }
    }

    override func stopAnimation() {
        super.stopAnimation()
        motion.stopDeviceMotionUpdates()
    }

    override func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {
        // The water surface stays level in the world, so on screen it tilts against the device.
        var targetAngle = 0.0
        if let gravity = motion.deviceMotion?.gravity {
            targetAngle = asin(min(max(gravity.x, -1), 1))
        } else if touch.isActive, bounds.width > 0 {
            targetAngle = (Double(touch.location.x / bounds.width) - 0.5) * 0.9
        }
        // Underdamped spring: overshoot and slosh.
        let acceleration = 30 * (targetAngle - angle) - 3 * angularVelocity
        angularVelocity += acceleration * deltaTime
        angle += angularVelocity * deltaTime

        if touch.isActive && !wasTouching {
            ripples.append(Ripple(x: Float(touch.location.x * pixelsPerPoint), startTime: uniforms.time))
            if ripples.count > Self.maxRipples {
                ripples.removeFirst()
            }
        }
        wasTouching = touch.isActive
        ripples.removeAll { uniforms.time - $0.startTime > Self.rippleLifetime }

        for (index, ripple) in ripples.enumerated() {
            uniforms.setBlob(index, SIMD4(ripple.x, ripple.startTime, 1, 0))
        }
        uniforms.blobCount = Int32(ripples.count)
        let slope = Float(tan(min(max(angle, -0.6), 0.6)))
        uniforms.setCustom(0, SIMD4(slope, Float(angularVelocity), Self.waterLevel, 0))
    }
}
