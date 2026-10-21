import MetalKit
import CoreMotion

struct LiquidPhysicsUniforms {
    var tilt: SIMD2<Float>
    var impulseTime: Float
    var padding: Float = 0
}

final class MetalLiquidView: MetalAnimationView {
    override var fragmentFunctionName: String { "liquidWavesFragment" }
    var motionEnabled = false { didSet { updateMotion() } }
    var motionAvailable: Bool { motion.isDeviceMotionAvailable }
    private let motion = CMMotionManager()
    private var tilt = SIMD2<Float>.zero
    private var impulseTime: Float = -100

    override func animationDidStart() { updateMotion() }
    override func animationDidStop() { motion.stopDeviceMotionUpdates() }

    private func updateMotion() {
        if motionEnabled, motion.isDeviceMotionAvailable, isAnimating, window != nil {
            if !motion.isDeviceMotionActive {
                motion.deviceMotionUpdateInterval = 1 / 30
                motion.startDeviceMotionUpdates()
            }
        } else { motion.stopDeviceMotionUpdates() }
    }

    override func interactionDidChange() { impulseTime = Float(animationTime) }

    override func encodeRender(encoder: MTLRenderCommandEncoder, uniforms: inout EffectUniforms) {
        var gravity = SIMD2<Float>.zero
        if motionEnabled, let data = motion.deviceMotion {
            let x = Float(data.gravity.x), y = Float(data.gravity.y)
            switch window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: gravity = SIMD2(-y, x)
            case .landscapeRight: gravity = SIMD2(y, -x)
            case .portraitUpsideDown: gravity = SIMD2(-x, -y)
            default: gravity = SIMD2(x, y)
            }
        }
        tilt += (gravity - tilt) * 0.08
        var physics = LiquidPhysicsUniforms(tilt: tilt, impulseTime: impulseTime)
        encoder.setFragmentBytes(&physics, length: MemoryLayout<LiquidPhysicsUniforms>.stride, index: 1)
        super.encodeRender(encoder: encoder, uniforms: &uniforms)
    }
}
