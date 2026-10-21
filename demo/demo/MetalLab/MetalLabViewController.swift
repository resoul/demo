//
//  MetalLabViewController.swift
//  demo
//

import UIKit

/// Metal-only stress tests (particles, liquid physics, glass optics) with a live profiler overlay.
final class MetalLabViewController: UIViewController {
    private enum Mode: Int, CaseIterable {
        case particles
        case liquid
        case glass

        var title: String {
            switch self {
            case .particles: "Частицы"
            case .liquid: "Вода / Физика"
            case .glass: "Оптика / Стекло"
            }
        }

        var hint: String {
            switch self {
            case .particles: "Удерживайте палец — рой стягивается к нему. Отпустите — частицы разлетятся."
            case .liquid: "Наклоните устройство или тапните по воде. В симуляторе ведите пальцем по горизонтали, чтобы наклонить воду."
            case .glass: "Перетаскивайте линзу пальцем; резкий бросок вытягивает её в каплю."
            }
        }

        func makeView() -> any MetalLabEffectView {
            switch self {
            case .particles: MetalParticlesView()
            case .liquid: MetalLiquidView()
            case .glass: MetalGlassView()
            }
        }
    }

    private let modeControl = UISegmentedControl(items: Mode.allCases.map(\.title))
    private let container = UIView()
    private let overlay = ProfilerOverlayView(entitiesTitle: "Entities")
    private let countSlider = UISlider()
    private let countLabel = UILabel()
    private let sliderRow = UIStackView()
    private let hintLabel = UILabel()

    private let countMapping = LogarithmicCountMapping(range: MetalParticlesView.particleRange, step: 10_000)

    private let monitor = PerformanceMonitor()
    private var effectView: (any MetalLabEffectView)?

    private var mode: Mode {
        Mode(rawValue: modeControl.selectedSegmentIndex) ?? .particles
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
        // Launch argument `-labMode 0...2` preselects a mode for repeatable runs.
        modeControl.selectedSegmentIndex = min(UserDefaults.standard.integer(forKey: "labMode"), Mode.allCases.count - 1)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        container.backgroundColor = .black
        container.layer.cornerRadius = 20
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true

        overlay.translatesAutoresizingMaskIntoConstraints = false

        countSlider.minimumTrackTintColor = UIColor(red: 0.2, green: 0.9, blue: 0.95, alpha: 1)
        countSlider.addTarget(self, action: #selector(countChanged), for: .valueChanged)
        countSlider.value = countMapping.sliderValue(forCount: 200_000)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        countLabel.textColor = .white
        countLabel.textAlignment = .right
        countLabel.widthAnchor.constraint(equalToConstant: 92).isActive = true
        sliderRow.addArrangedSubview(countSlider)
        sliderRow.addArrangedSubview(countLabel)
        sliderRow.spacing = 12

        hintLabel.numberOfLines = 0
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = UIColor(white: 1, alpha: 0.7)

        let root = UIStackView(arrangedSubviews: [modeControl, container, sliderRow, hintLabel])
        root.axis = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(.defaultLow, for: .vertical)
        container.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.addSubview(root)
        container.addSubview(overlay)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
            root.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),

            overlay.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            overlay.widthAnchor.constraint(equalToConstant: 220),
        ])
    }

    // MARK: - Effects

    private func showEffect() {
        effectView?.stopAnimation()
        effectView?.removeFromSuperview()

        let newView = mode.makeView()
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
        if let particles = newView as? MetalParticlesView {
            particles.particleCount = countMapping.count(forSliderValue: countSlider.value)
        }
        if view.window != nil {
            newView.startAnimation()
        }

        sliderRow.isHidden = mode != .particles
        updateCountLabel()
        hintLabel.text = mode.hint
        overlay.reset()
        overlay.entitiesText = newView.activeEntityDescription
        monitor.reset()
    }

    @objc private func modeChanged() {
        showEffect()
    }

    // MARK: - Particle count

    @objc private func countChanged() {
        (effectView as? MetalParticlesView)?.particleCount = countMapping.count(forSliderValue: countSlider.value)
        updateCountLabel()
        overlay.entitiesText = effectView?.activeEntityDescription
    }

    private func updateCountLabel() {
        countLabel.text = countMapping.count(forSliderValue: countSlider.value).formatted()
    }

    // MARK: - Metrics

    private func show(_ snapshot: PerformanceMonitor.Snapshot) {
        let maxFPS = Double(view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
        overlay.update(with: snapshot, maxFPS: maxFPS)
        overlay.entitiesText = effectView?.activeEntityDescription
    }
}
