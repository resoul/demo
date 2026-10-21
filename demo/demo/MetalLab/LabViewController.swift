//
//  LabViewController.swift
//  demo
//

import UIKit

/// Generic lab screen: a mode switch, the active effect with the profiler overlay on top, and the
/// effect's own controls underneath. Only the active effect exists, so heavy GPU resources of the
/// other modes are released when switching.
class LabViewController: UIViewController {
    struct Mode {
        let title: String
        let hint: String
        let make: () -> any MetalLabEffectView
    }

    private let modes: [Mode]
    private let launchKey: String
    private let modeControl: UISegmentedControl
    private let container = UIView()
    private let overlay = ProfilerOverlayView(entitiesTitle: "Entities", throughputTitle: "Throughput")
    private let controlsStack = UIStackView()
    private let hintLabel = UILabel()
    private let monitor = PerformanceMonitor()
    private var effectView: (any MetalLabEffectView)?

    /// `launchKey` names the launch argument that preselects a mode, e.g. `-computeMode 2`.
    init(modes: [Mode], launchKey: String) {
        self.modes = modes
        self.launchKey = launchKey
        modeControl = UISegmentedControl(items: modes.map(\.title))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)
        overrideUserInterfaceStyle = .dark
        buildLayout()
        showEffect()
        monitor.onUpdate = { [weak self] snapshot in
            self?.show(snapshot)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        monitor.start()
        effectView?.startAnimation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        monitor.stop()
        effectView?.stopAnimation()
    }

    // MARK: - Layout

    private func buildLayout() {
        modeControl.selectedSegmentIndex = min(UserDefaults.standard.integer(forKey: launchKey), modes.count - 1)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        container.backgroundColor = .black
        container.layer.cornerRadius = 20
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        container.setContentHuggingPriority(.defaultLow, for: .vertical)
        container.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(overlay)

        controlsStack.axis = .vertical
        controlsStack.spacing = 8

        hintLabel.numberOfLines = 0
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = UIColor(white: 1, alpha: 0.65)

        let root = UIStackView(arrangedSubviews: [modeControl, container, controlsStack, hintLabel])
        root.axis = .vertical
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -10),
            root.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            overlay.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            overlay.widthAnchor.constraint(equalToConstant: 230),
        ])
    }

    // MARK: - Effects

    private func showEffect() {
        effectView?.stopAnimation()
        effectView?.removeFromSuperview()

        let mode = modes[modeControl.selectedSegmentIndex]
        let newView = mode.make()
        newView.workRecorder = monitor.recorder
        newView.translatesAutoresizingMaskIntoConstraints = false
        container.insertSubview(newView, belowSubview: overlay)
        NSLayoutConstraint.activate([
            newView.topAnchor.constraint(equalTo: container.topAnchor),
            newView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            newView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            newView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        effectView = newView
        if view.window != nil {
            newView.startAnimation()
        }

        rebuildControls(newView.controls)
        hintLabel.text = mode.hint
        overlay.reset()
        overlay.entitiesText = newView.activeEntityDescription
        overlay.throughputText = newView.throughputDescription
        monitor.reset()
    }

    @objc private func modeChanged() {
        showEffect()
    }

    private func rebuildControls(_ controls: [LabControl]) {
        controlsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for control in controls {
            controlsStack.addArrangedSubview(makeRow(for: control))
        }
        controlsStack.isHidden = controls.isEmpty
    }

    private func makeRow(for control: LabControl) -> UIView {
        switch control {
        case let .slider(title, range, value, isLogarithmic, format, onChange):
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .systemFont(ofSize: 13)
            titleLabel.textColor = UIColor(white: 1, alpha: 0.7)
            titleLabel.widthAnchor.constraint(equalToConstant: 92).isActive = true

            let valueLabel = UILabel()
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            valueLabel.textColor = .white
            valueLabel.textAlignment = .right
            valueLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true
            valueLabel.text = format(value)

            // Logarithmic sliders run 0...1 and map to the range exponentially.
            let toValue: (Float) -> Float = isLogarithmic
                ? { range.lowerBound * pow(range.upperBound / range.lowerBound, $0) }
                : { $0 }
            let slider = UISlider()
            slider.minimumTrackTintColor = UIColor(red: 0.3, green: 0.85, blue: 1, alpha: 1)
            if isLogarithmic {
                slider.value = log(value / range.lowerBound) / log(range.upperBound / range.lowerBound)
            } else {
                slider.minimumValue = range.lowerBound
                slider.maximumValue = range.upperBound
                slider.value = value
            }
            slider.addAction(UIAction { [weak slider] _ in
                guard let slider else { return }
                let newValue = toValue(slider.value)
                valueLabel.text = format(newValue)
                onChange(newValue)
            }, for: .valueChanged)

            let row = UIStackView(arrangedSubviews: [titleLabel, slider, valueLabel])
            row.spacing = 10
            return row

        case let .segments(items, selected, onChange):
            let segments = UISegmentedControl(items: items)
            segments.selectedSegmentIndex = selected
            segments.addAction(UIAction { [weak segments] _ in
                guard let segments else { return }
                onChange(segments.selectedSegmentIndex)
            }, for: .valueChanged)
            return segments

        case let .button(title, action):
            var configuration = UIButton.Configuration.gray()
            configuration.title = title
            configuration.buttonSize = .small
            return UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        }
    }

    // MARK: - Metrics

    private func show(_ snapshot: PerformanceMonitor.Snapshot) {
        let maxFPS = Double(view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
        overlay.update(with: snapshot, maxFPS: maxFPS)
        overlay.entitiesText = effectView?.activeEntityDescription
        overlay.throughputText = effectView?.throughputDescription
    }
}
