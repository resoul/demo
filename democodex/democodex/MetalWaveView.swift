import UIKit

final class MetalWaveView: MetalAnimationView {
    override var fragmentFunctionName: String { "waveFragment" }

    override func interactionDidChange() {
        progress = Float(1 - interactionPoint.y)
        onProgressChanged?(progress)
    }
}
