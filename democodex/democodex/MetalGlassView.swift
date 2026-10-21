import MetalKit

final class MetalGlassView: MetalAnimationView {
    override var fragmentFunctionName: String { "glassRefractionFragment" }
}
