//
//  ProfilerOverlayView.swift
//  demo
//

import UIKit

/// Translucent metrics panel laid over a Metal effect. It ignores touches, so the effect underneath
/// still receives them.
final class ProfilerOverlayView: UIVisualEffectView {
    private let stack = UIStackView()
    private var fpsLabel: UILabel!
    private var frameTimeLabel: UILabel!
    private var gpuTimeLabel: UILabel!
    private var mainThreadLabel: UILabel!
    private var processLabel: UILabel!
    private var entitiesLabel: UILabel!
    private var throughputLabel: UILabel?

    var entitiesText: String? {
        get { entitiesLabel.text }
        set { entitiesLabel.text = newValue }
    }

    var throughputText: String? {
        get { throughputLabel?.text }
        set { throughputLabel?.text = newValue ?? "—" }
    }

    /// `throughputTitle` adds a row for an effect-specific workload metric.
    init(entitiesTitle: String, throughputTitle: String? = nil) {
        super.init(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        layer.cornerRadius = 12
        clipsToBounds = true
        isUserInteractionEnabled = false

        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
        ])

        fpsLabel = addRow("FPS")
        frameTimeLabel = addRow("Frame time")
        gpuTimeLabel = addRow("GPU frame")
        mainThreadLabel = addRow("CPU main")
        processLabel = addRow("CPU app")
        entitiesLabel = addRow(entitiesTitle)
        throughputLabel = throughputTitle.map { addRow($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows placeholders until the next measurement window completes.
    func reset() {
        [fpsLabel, frameTimeLabel, gpuTimeLabel, mainThreadLabel, processLabel].forEach { $0?.text = "…" }
    }

    /// Uses the frames the effect actually rendered (one effect on screen), which can be lower
    /// than the display refresh when the GPU or the drawable queue cannot keep up.
    func update(with snapshot: PerformanceMonitor.Snapshot, maxFPS: Double) {
        let fps = snapshot.renderedFPS > 0 ? snapshot.renderedFPS : snapshot.fps
        fpsLabel.text = String(format: "%.0f / %.0f", fps, maxFPS)
        fpsLabel.textColor = switch fps / maxFPS {
        case 0.9...: .systemGreen
        case 0.6..<0.9: .systemYellow
        default: .systemRed
        }
        frameTimeLabel.text = String(format: "%.2f ms", fps > 0 ? 1000 / fps : snapshot.frameIntervalMs)
        gpuTimeLabel.text = snapshot.gpuWorkMs.map { String(format: "%.3f ms", $0) } ?? "—"
        mainThreadLabel.text = String(format: "%.1f %%", snapshot.mainThreadCPUPercent)
        processLabel.text = String(format: "%.1f %%", snapshot.cpuUsagePercent)
    }

    private func addRow(_ title: String) -> UILabel {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = UIColor(white: 1, alpha: 0.6)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let valueLabel = UILabel()
        valueLabel.text = "—"
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.textAlignment = .right
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        let row = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        row.spacing = 8
        stack.addArrangedSubview(row)
        return valueLabel
    }
}

/// Maps a 0...1 slider to a count on a logarithmic scale, rounded to `step`.
struct LogarithmicCountMapping {
    let range: ClosedRange<Int>
    let step: Int

    func count(forSliderValue value: Float) -> Int {
        let ratio = Double(range.upperBound) / Double(range.lowerBound)
        let raw = Double(range.lowerBound) * pow(ratio, Double(value))
        let rounded = Int((raw / Double(step)).rounded()) * step
        return min(max(rounded, range.lowerBound), range.upperBound)
    }

    func sliderValue(forCount count: Int) -> Float {
        let ratio = Double(range.upperBound) / Double(range.lowerBound)
        return Float(log(Double(count) / Double(range.lowerBound)) / log(ratio))
    }
}
