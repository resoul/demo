//
//  MetalGlassView.swift
//  demo
//

import UIKit

/// A glass lens that can be dragged over an animated backdrop. The optics (refraction, dispersion,
/// reflections) run in `glass_fragment` (GlassRefraction.metal); the CPU only moves the lens on
/// a spring, so it wobbles and stretches into a droplet when flung.
final class MetalGlassView: MetalAnimationView, MetalLabEffectView {
    override class var fragmentFunction: String? { "glass_fragment" }

    private var position: CGPoint?
    private var velocity: CGVector = .zero
    /// Where the lens rests when nobody is dragging it.
    private var anchor: CGPoint?
    /// Finger-to-center offset, so the lens does not jump when grabbed off-center.
    private var grabOffset: CGPoint = .zero
    private var wasTouching = false

    private var lensRadius: CGFloat {
        min(bounds.width, bounds.height) * 0.26
    }

    var activeEntityDescription: String {
        // Rays marched per frame: the pixels under the lens footprint.
        let radiusInPixels = lensRadius * pixelsPerPoint
        let rays = Int(.pi * radiusInPixels * radiusInPixels)
        return "1 линза · \((rays / 1000).formatted())k лучей"
    }

    override func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var lens = position ?? center

        if touch.isActive && !wasTouching {
            let grabbed = hypot(touch.location.x - lens.x, touch.location.y - lens.y) < lensRadius
            grabOffset = grabbed ? CGPoint(x: lens.x - touch.location.x, y: lens.y - touch.location.y) : .zero
        }
        if !touch.isActive && wasTouching {
            anchor = lens
        }
        wasTouching = touch.isActive

        // Follow the finger; at rest, float gently around the anchor.
        let time = CGFloat(uniforms.time)
        var target: CGPoint
        if touch.isActive {
            target = CGPoint(x: touch.location.x + grabOffset.x, y: touch.location.y + grabOffset.y)
        } else {
            let rest = anchor ?? center
            target = CGPoint(x: rest.x + cos(time * 0.7) * 6, y: rest.y + sin(time * 0.9) * 8)
        }
        target.x = min(max(target.x, 0), bounds.width)
        target.y = min(max(target.y, 0), bounds.height)

        // Slightly underdamped spring: a little wobble after fast moves.
        let dt = CGFloat(deltaTime)
        let stiffness: CGFloat = 220, damping: CGFloat = 20
        velocity.dx += (stiffness * (target.x - lens.x) - damping * velocity.dx) * dt
        velocity.dy += (stiffness * (target.y - lens.y) - damping * velocity.dy) * dt
        lens.x += velocity.dx * dt
        lens.y += velocity.dy * dt
        position = lens

        let scale = Float(pixelsPerPoint)
        uniforms.setCustom(0, SIMD4(Float(lens.x) * scale, Float(lens.y) * scale, Float(lensRadius) * scale, 0))
        uniforms.setCustom(1, SIMD4(Float(velocity.dx) * scale, Float(velocity.dy) * scale, 0, 0))
    }
}
