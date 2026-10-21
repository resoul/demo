import UIKit

final class ComputeBenchmarkViewController: GPUExperimentsViewController {
    override var experiments: [GPUExperiment] { GPUExperiment.computeBench }
    override var screenTitle: String { "Compute Bench" }
    override var isComputeBench: Bool { true }
}
