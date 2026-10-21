//
//  LavaProgressViewController.swift
//  demo
//

import UIKit

/// Shows any effect in either engine, optionally replicated for load, with live performance metrics.
final class LavaProgressViewController: UIViewController {
    private enum Engine: Int {
        case uiKit
        case metal
    }

    private enum Effect: Int, CaseIterable {
        case lava
        case water
        case blobs
        case plasma
        case fire

        var title: String {
            switch self {
            case .lava: "Лава"
            case .water: "Вода"
            case .blobs: "Капли"
            case .plasma: "Плазма"
            case .fire: "Огонь"
            }
        }

        var hint: String {
            switch self {
            case .lava: "Слайдер — заполнение прогресс-бара."
            case .water: "Слайдер — уровень воды. Ведите пальцем по воде, чтобы поднять волну."
            case .blobs: "Слайдер — размер капель. Коснитесь, и капли стекутся к пальцу и сольются."
            case .plasma: "Слайдер — энергия плазмы. Палец закручивает поле."
            case .fire: "Слайдер — высота пламени. Палец сбоку создаёт ветер."
            }
        }

        /// Progress bars are laid out as thin rows; other effects fill grid cells.
        var isBar: Bool { self == .lava }

        func makeView(for engine: Engine) -> any BenchmarkableAnimationView {
            switch (self, engine) {
            case (.lava, .uiKit): return StandardLavaProgressBarView()
            case (.lava, .metal): return MetalLavaProgressBarView()
            case (.water, .uiKit): return StandardLiquidWaveView()
            case (.water, .metal): return MetalLiquidWaveView()
            case (.blobs, .uiKit): return StandardMetaBallsView()
            case (.blobs, .metal): return MetalMetaBallsView()
            case (.plasma, .uiKit): return StandardPlasmaView()
            case (.plasma, .metal): return MetalPlasmaView()
            case (.fire, .uiKit): return StandardFireView()
            case (.fire, .metal): return MetalFireView()
            }
        }
    }

    private let copyCounts = [1, 6, 20]
    private let containerHeight: CGFloat = 300
    private let gridSpacing: CGFloat = 6

    private let effectControl = UISegmentedControl(items: Effect.allCases.map(\.title))
    private let engineControl = UISegmentedControl(items: ["UIKit", "Metal"])
    private let loadControl = UISegmentedControl(items: ["1 view", "6 views", "20 views"])
    private let slider = UISlider()
    private let percentLabel = UILabel()
    private let container = UIView()
    private let hintLabel = UILabel()
    private let metricsPanel = UIStackView()

    private var fpsLabel: UILabel!
    private var frameIntervalLabel: UILabel!
    private var cpuWorkLabel: UILabel!
    private var gpuWorkLabel: UILabel!
    private var cpuUsageLabel: UILabel!
    private var textureLabel: UILabel!

    private let monitor = PerformanceMonitor()
    private var effectViews: [any BenchmarkableAnimationView] = []

    private var effect: Effect {
        Effect(rawValue: effectControl.selectedSegmentIndex) ?? .lava
    }

    private var engine: Engine {
        Engine(rawValue: engineControl.selectedSegmentIndex) ?? .uiKit
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.04, green: 0.03, blue: 0.03, alpha: 1)
        overrideUserInterfaceStyle = .dark
        buildLayout()
        rebuildEffect()
        monitor.onUpdate = { [weak self] snapshot in
            self?.show(snapshot)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        monitor.start()
        effectViews.forEach { $0.startAnimation() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        monitor.stop()
        effectViews.forEach { $0.stopAnimation() }
    }

    // MARK: - Layout

    private func buildLayout() {
        let titleLabel = UILabel()
        titleLabel.text = "Metal vs UIKit Benchmark"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white

        metricsPanel.axis = .vertical
        metricsPanel.spacing = 4
        metricsPanel.isLayoutMarginsRelativeArrangement = true
        metricsPanel.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        metricsPanel.backgroundColor = UIColor(white: 1, alpha: 0.06)
        metricsPanel.layer.cornerRadius = 14
        fpsLabel = addMetricRow("FPS")
        frameIntervalLabel = addMetricRow("Frame interval")
        cpuWorkLabel = addMetricRow("CPU work / frame")
        gpuWorkLabel = addMetricRow("GPU time / frame")
        cpuUsageLabel = addMetricRow("CPU usage (app)")
        textureLabel = addMetricRow("Bitmap memory / view")

        // Launch arguments preset the configuration for repeatable runs, e.g. `-effect 2 -engine 1 -copies 2`.
        let defaults = UserDefaults.standard
        effectControl.selectedSegmentIndex = min(defaults.integer(forKey: "effect"), Effect.allCases.count - 1)
        engineControl.selectedSegmentIndex = min(defaults.integer(forKey: "engine"), 1)
        loadControl.selectedSegmentIndex = min(defaults.integer(forKey: "copies"), copyCounts.count - 1)
        for control in [effectControl, engineControl, loadControl] {
            control.addTarget(self, action: #selector(configurationChanged), for: .valueChanged)
        }

        slider.value = 0.6
        slider.minimumTrackTintColor = LavaPalette.orange
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        percentLabel.textColor = .white
        percentLabel.textAlignment = .right
        percentLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        updatePercentLabel()
        let sliderRow = UIStackView(arrangedSubviews: [slider, percentLabel])
        sliderRow.spacing = 12

        container.heightAnchor.constraint(equalToConstant: containerHeight).isActive = true

        hintLabel.numberOfLines = 0
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = UIColor(white: 1, alpha: 0.7)

        let footnote = UILabel()
        footnote.numberOfLines = 0
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = UIColor(white: 1, alpha: 0.45)
        footnote.text = "CPU usage counts this app's process only (100% = one core). Core Animation composites layers, runs layer animations and emitters in the render server, which is not included: UIKit plasma and fire do almost no work in the app. GPU time is measured for Metal only (command buffer gpuStart/EndTime). Measure on a device with a Release build: the Simulator is not representative."

        let root = UIStackView(arrangedSubviews: [titleLabel, metricsPanel, effectControl, engineControl, loadControl, sliderRow, container, hintLabel, footnote])
        root.axis = .vertical
        root.spacing = 12
        root.setCustomSpacing(18, after: sliderRow)
        root.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = EffectFriendlyScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.delaysContentTouches = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(root)
        view.addSubview(scrollView)
        let content = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            root.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    private func addMetricRow(_ title: String) -> UILabel {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.textColor = UIColor(white: 1, alpha: 0.6)

        let valueLabel = UILabel()
        valueLabel.text = "—"
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.textAlignment = .right

        metricsPanel.addArrangedSubview(UIStackView(arrangedSubviews: [titleLabel, valueLabel]))
        return valueLabel
    }

    // MARK: - Effect views

    private func rebuildEffect() {
        effectViews.forEach { $0.stopAnimation() }
        container.subviews.forEach { $0.removeFromSuperview() }

        let count = copyCounts[loadControl.selectedSegmentIndex]
        let views = (0..<count).map { _ in
            let effectView = effect.makeView(for: engine)
            effectView.workRecorder = monitor.recorder
            effectView.progress = slider.value
            return effectView
        }
        let layout = effect.isBar ? makeBarLayout(views) : makeGridLayout(views)
        layout.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            layout.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            layout.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor),
        ])
        if !effect.isBar {
            layout.heightAnchor.constraint(equalTo: container.heightAnchor).isActive = true
        }

        effectViews = views
        if view.window != nil {
            views.forEach { $0.startAnimation() }
        }

        hintLabel.text = effect.hint
        textureLabel.text = "\((views.first?.textureMemoryBytes ?? 0) / 1024) KB"
        [fpsLabel, frameIntervalLabel, cpuWorkLabel, gpuWorkLabel, cpuUsageLabel].forEach { $0?.text = "…" }
        monitor.reset()
    }

    /// Thin progress bars stacked vertically, centered in the container.
    private func makeBarLayout(_ views: [UIView]) -> UIView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = gridSpacing
        let available = (containerHeight - gridSpacing * CGFloat(views.count - 1)) / CGFloat(views.count)
        let height = min(36, available)
        views.forEach { $0.heightAnchor.constraint(equalToConstant: height).isActive = true }
        return stack
    }

    /// Equal cells filling the container: 1, 2 or 4 columns depending on the number of copies.
    private func makeGridLayout(_ views: [UIView]) -> UIView {
        let columns = views.count == 1 ? 1 : views.count <= 6 ? 2 : 4
        let rows = stride(from: 0, to: views.count, by: columns).map { start in
            let row = UIStackView(arrangedSubviews: Array(views[start..<min(start + columns, views.count)]))
            row.distribution = .fillEqually
            row.spacing = gridSpacing
            return row
        }
        let grid = UIStackView(arrangedSubviews: rows)
        grid.axis = .vertical
        grid.distribution = .fillEqually
        grid.spacing = gridSpacing
        for effectView in views {
            effectView.layer.cornerRadius = views.count == 1 ? 20 : 10
            effectView.layer.cornerCurve = .continuous
            effectView.clipsToBounds = true
        }
        return grid
    }

    @objc private func configurationChanged() {
        rebuildEffect()
    }

    @objc private func sliderChanged() {
        effectViews.forEach { $0.progress = slider.value }
        updatePercentLabel()
    }

    private func updatePercentLabel() {
        percentLabel.text = "\(Int((slider.value * 100).rounded()))%"
    }

    // MARK: - Metrics

    private func show(_ snapshot: PerformanceMonitor.Snapshot) {
        let maxFPS = Double(view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
        fpsLabel.text = String(format: "%.0f / %.0f", snapshot.fps, maxFPS)
        fpsLabel.textColor = switch snapshot.fps / maxFPS {
        case 0.9...: .systemGreen
        case 0.6..<0.9: .systemYellow
        default: .systemRed
        }
        frameIntervalLabel.text = String(format: "%.2f ms", snapshot.frameIntervalMs)
        cpuWorkLabel.text = String(format: "%.3f ms", snapshot.cpuWorkMs)
        gpuWorkLabel.text = snapshot.gpuWorkMs.map { String(format: "%.3f ms", $0) } ?? "n/a (render server)"
        cpuUsageLabel.text = String(format: "%.1f %%", snapshot.cpuUsagePercent)
        // Some views allocate their bitmaps on first layout, so refresh this with the samples.
        textureLabel.text = "\((effectViews.first?.textureMemoryBytes ?? 0) / 1024) KB"
    }
}

/// Lets drags on an effect reach the effect (waves, blobs, wind) instead of scrolling the page.
private final class EffectFriendlyScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate is any BenchmarkableAnimationView {
                return false
            }
            current = candidate.superview
        }
        return super.touchesShouldCancel(in: view)
    }
}
