//
//  EmojiParticlesViewController.swift
//  demo
//

import UIKit

/// Instancing stress test: an emoji fountain simulated and drawn entirely on the GPU, with a
/// palette switch, a count slider (1 000 to 200 000) and a live profiler overlay.
final class EmojiParticlesViewController: UIViewController {
    private let paletteControl = UISegmentedControl(items: MetalEmojiParticlesView.Palette.allCases.map(\.title))
    private let container = UIView()
    private let emojiView = MetalEmojiParticlesView()
    private let overlay = ProfilerOverlayView(entitiesTitle: "Active emoji")
    private let countSlider = UISlider()
    private let countLabel = UILabel()
    private let hintLabel = UILabel()

    private let countMapping = LogarithmicCountMapping(range: MetalEmojiParticlesView.countRange, step: 1_000)
    private let monitor = PerformanceMonitor()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)
        overrideUserInterfaceStyle = .dark
        buildLayout()
        monitor.onUpdate = { [weak self] snapshot in
            self?.show(snapshot)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        monitor.start()
        emojiView.startAnimation()
        overlay.reset()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        monitor.stop()
        emojiView.stopAnimation()
    }

    // MARK: - Layout

    private func buildLayout() {
        // Launch arguments preset the run, e.g. `-emojiPalette 3 -emojiCount 100000`.
        let defaults = UserDefaults.standard
        let palette = MetalEmojiParticlesView.Palette(rawValue: defaults.integer(forKey: "emojiPalette")) ?? .fire
        let requestedCount = defaults.integer(forKey: "emojiCount")
        let initialCount = requestedCount > 0 ? requestedCount : 20_000

        paletteControl.selectedSegmentIndex = palette.rawValue
        paletteControl.addTarget(self, action: #selector(paletteChanged), for: .valueChanged)
        emojiView.palette = palette
        emojiView.workRecorder = monitor.recorder

        countSlider.minimumTrackTintColor = UIColor(red: 1, green: 0.45, blue: 0.2, alpha: 1)
        countSlider.value = countMapping.sliderValue(forCount: initialCount)
        countSlider.addTarget(self, action: #selector(countChanged), for: .valueChanged)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        countLabel.textColor = .white
        countLabel.textAlignment = .right
        countLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let sliderRow = UIStackView(arrangedSubviews: [countSlider, countLabel])
        sliderRow.spacing = 12
        countChanged()

        hintLabel.numberOfLines = 0
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = UIColor(white: 1, alpha: 0.7)
        hintLabel.text = "Коснитесь экрана — фонтан бьёт из-под пальца, а палец расталкивает эмодзи вокруг. Слайдер меняет количество на лету."

        container.layer.cornerRadius = 20
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        container.setContentHuggingPriority(.defaultLow, for: .vertical)
        container.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        emojiView.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(emojiView)
        container.addSubview(overlay)

        let root = UIStackView(arrangedSubviews: [paletteControl, container, sliderRow, hintLabel])
        root.axis = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
            root.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),

            emojiView.topAnchor.constraint(equalTo: container.topAnchor),
            emojiView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emojiView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            emojiView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            overlay.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            overlay.widthAnchor.constraint(equalToConstant: 220),
        ])
    }

    @objc private func paletteChanged() {
        emojiView.palette = MetalEmojiParticlesView.Palette(rawValue: paletteControl.selectedSegmentIndex) ?? .mix
    }

    @objc private func countChanged() {
        let count = countMapping.count(forSliderValue: countSlider.value)
        emojiView.emojiCount = count
        countLabel.text = count.formatted()
    }

    // MARK: - Metrics

    private func show(_ snapshot: PerformanceMonitor.Snapshot) {
        let maxFPS = Double(view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
        overlay.update(with: snapshot, maxFPS: maxFPS)
        overlay.entitiesText = "\(emojiView.visibleEmojiCount.formatted()) / \(emojiView.emojiCount.formatted())"
    }
}
