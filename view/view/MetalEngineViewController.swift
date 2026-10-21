import UIKit
import simd

private enum EngineStyle {
    static let background = UIColor(red: 0.035, green: 0.047, blue: 0.06, alpha: 1)
    static let panel = UIColor(red: 0.067, green: 0.086, blue: 0.10, alpha: 1)
    static let accent = UIColor(red: 0.48, green: 0.97, blue: 0.77, alpha: 1)
    static let muted = UIColor(red: 0.51, green: 0.59, blue: 0.63, alpha: 1)
    static func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular,
                      color: UIColor = .white) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = color
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: size, weight: weight))
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }
    static func button(_ title: String, symbol: String? = nil) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = symbol.flatMap(UIImage.init(systemName:))
        config.imagePadding = 10
        config.baseBackgroundColor = panel
        config.baseForegroundColor = accent
        config.cornerStyle = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 13, weight: .semibold)
            return attributes
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        button.configuration = config
        return button
    }
}

enum MetalSampleSignal {
    nonisolated static func make(count: Int, startingAt start: Int = 0) throws -> [SIMD2<Float>] {
        var points = [SIMD2<Float>]()
        points.reserveCapacity(count)
        for i in start..<(start + count) {
            if i & 4095 == 0 { try Task.checkCancellation() }
            let x = Float(i)
            let hash = UInt32(truncatingIfNeeded: i) &* 1_664_525 &+ 1_013_904_223
            let noise = (Float(hash & 1023) / 1023 - 0.5) * 0.08
            var y = sin(x * 0.000047) * 0.48 + sin(x * 0.00031) * 0.18 + cos(x * 0.0021) * 0.06 + noise
            if i % 15_467 < 3 { y += 0.65 }
            if i % 24_713 < 2 { y -= 0.65 }
            points.append(SIMD2(x, y))
        }
        return points
    }
}

final class MetalEngineViewController: UIViewController, MetalTransitionBackendReporting {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let chart = MetalChartView()
    private let rain = MatrixDigitalRainView()
    private let fluid = FluidMeshGradientView()
    private let sampleControl = UISegmentedControl(items: ["1M точек", "2M точек"])
    private let live = UISwitch()
    private let status = EngineStyle.label("Подготовка данных…", size: 11, color: EngineStyle.muted)
    private let geometry = EngineStyle.label("GPU MIN/MAX LOD", size: 10, weight: .semibold, color: EngineStyle.accent)
    private let renderStat = EngineStyle.label("— /с", size: 19, weight: .semibold)
    private let gpuStat = EngineStyle.label("— мс", size: 19, weight: .semibold)
    private let cpuStat = EngineStyle.label("— мс", size: 19, weight: .semibold)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var loadTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var streamTimer: Timer?
    private var appending = false
    private var streamRevision = 0
    private weak var backButton: UIButton?

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = EngineStyle.background
        configureLayout()
        buildHeader()
        buildChart()
        buildTransitions()
        buildVFX()
        let note = EngineStyle.label("120 Гц — целевой режим на ProMotion. Частота зависит от устройства, нагрузки, температуры и энергосбережения. Рендер/с показывает отправленные кадры; GPU и CPU — время одного кадра, без подготовки снимков перехода.", size: 11, color: EngineStyle.muted)
        stack.addArrangedSubview(note)
        chart.onMetrics = { [weak self] metrics in self?.updateMetrics(metrics) }
        chart.onError = { [weak self] error in self?.status.text = error.localizedDescription }
        loadSamples(count: 1_000_000)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if live.isOn { startStreaming() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopStreaming()
        if isMovingFromParent { loadTask?.cancel() }
    }

    private func configureLayout() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        scroll.isDirectionalLockEnabled = true
        scroll.panGestureRecognizer.maximumNumberOfTouches = 1
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.centerXAnchor.constraint(equalTo: scroll.contentLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40).priority(999),
            stack.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 900)
        ])
    }

    private func buildHeader() {
        let back = EngineStyle.button("Лаборатория", symbol: "arrow.left")
        back.accessibilityIdentifier = "engineBack"
        backButton = back
        back.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        let top = UIStackView(arrangedSubviews: [back, UIView(), EngineStyle.label("◈  METAL ENGINE", size: 10, weight: .bold, color: EngineStyle.accent)])
        top.alignment = .center
        top.spacing = 12
        stack.addArrangedSubview(top)
        let title = EngineStyle.label("Данные\nв движении.", size: 39, weight: .semibold)
        title.accessibilityTraits = .header
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(10, after: title)
        stack.addArrangedSubview(EngineStyle.label("Миллионы точек. Свет. Переходы.\nВся геометрия остаётся на GPU.", size: 14, color: EngineStyle.muted))
    }

    private func buildChart() {
        sectionTitle("01", "Signal engine", subtitle: "Пики сохраняются. Масштаб меняется.")
        sampleControl.selectedSegmentIndex = 0
        sampleControl.selectedSegmentTintColor = EngineStyle.accent
        sampleControl.setTitleTextAttributes([.foregroundColor: EngineStyle.background], for: .selected)
        sampleControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        sampleControl.accessibilityIdentifier = "sampleCount"
        sampleControl.addTarget(self, action: #selector(changeSamples), for: .valueChanged)
        stack.addArrangedSubview(sampleControl)
        let loading = UIStackView(arrangedSubviews: [status, UIView(), spinner])
        loading.alignment = .center
        status.accessibilityIdentifier = "engineStatus"
        spinner.hidesWhenStopped = true
        stack.addArrangedSubview(loading)
        chart.translatesAutoresizingMaskIntoConstraints = false
        chart.allowsVerticalPanning = false
        chart.heightAnchor.constraint(equalToConstant: 290).isActive = true
        stack.addArrangedSubview(chart)
        for gesture in chart.gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer {
            scroll.panGestureRecognizer.require(toFail: gesture)
        }
        stack.setCustomSpacing(10, after: chart)
        stack.addArrangedSubview(geometry)
        let stats = UIStackView(arrangedSubviews: [stat("РЕНДЕР /С", renderStat), stat("GPU", gpuStat), stat("CPU ENCODE", cpuStat)])
        stats.distribution = .fillEqually
        stats.spacing = 12
        stack.addArrangedSubview(stats)
        let reset = EngineStyle.button("Сбросить масштаб", symbol: "arrow.counterclockwise")
        reset.accessibilityIdentifier = "resetChartViewport"
        reset.addAction(UIAction { [weak self] _ in self?.chart.resetViewport() }, for: .touchUpInside)
        let liveLabel = EngineStyle.label("LIVE", size: 10, weight: .bold, color: EngineStyle.accent)
        live.onTintColor = EngineStyle.accent
        live.accessibilityLabel = "Стриминг точек"
        live.accessibilityIdentifier = "streamPoints"
        live.addTarget(self, action: #selector(toggleLive), for: .valueChanged)
        let controls = UIStackView(arrangedSubviews: [reset, UIView(), liveLabel, live])
        controls.alignment = .center
        controls.spacing = 12
        stack.addArrangedSubview(controls)
        stack.addArrangedSubview(EngineStyle.label("Панорама — по горизонтали. Масштаб — двумя пальцами.\nLive добавляет 20 480 точек/с в свободный хвост буфера.", size: 11, color: EngineStyle.muted))
    }

    private func stat(_ title: String, _ value: UILabel) -> UIView {
        let box = UIStackView(arrangedSubviews: [EngineStyle.label(title, size: 9, weight: .semibold, color: EngineStyle.muted), value])
        box.axis = .vertical
        box.spacing = 8
        box.isLayoutMarginsRelativeArrangement = true
        box.layoutMargins = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        box.backgroundColor = EngineStyle.panel
        box.layer.cornerRadius = 16
        return box
    }

    private func buildTransitions() {
        sectionTitle("02", "Beyond the screen", subtitle: "Три способа оказаться по ту сторону.")
        for style in MetalTransitionStyle.allCases {
            let button = TransitionTriggerButton(type: .system)
            var config = UIButton.Configuration.filled()
            config.title = style.title
            config.subtitle = ["Шум Перлина и неоновая кромка", "Волна от точки вашего касания", "RGB-сдвиг и цифровые блоки"][Int(style.rawValue)]
            config.image = UIImage(systemName: ["sparkles", "water.waves", "waveform.path"][Int(style.rawValue)])
            config.imagePadding = 16
            config.baseBackgroundColor = EngineStyle.panel
            config.baseForegroundColor = .white
            config.cornerStyle = .large
            config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
            config.titleAlignment = .leading
            button.configuration = config
            button.contentHorizontalAlignment = .leading
            button.accessibilityIdentifier = "transition\(style.rawValue)"
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let navigation = self.navigationController as? MetalNavigationController else { return }
                let size = navigation.view.bounds.size
                let point = button?.lastPoint ?? CGPoint(x: size.width / 2, y: size.height / 2)
                navigation.transitionOrigin = CGPoint(x: point.x / max(size.width, 1), y: point.y / max(size.height, 1))
                navigation.transitionStyle = style
                navigation.pushViewController(MetalTransitionDestination(style: style), animated: true)
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    private func buildVFX() {
        sectionTitle("03", "Living surfaces", subtitle: "Процедурный свет и цифровой дождь.")
        fluid.translatesAutoresizingMaskIntoConstraints = false
        fluid.heightAnchor.constraint(equalToConstant: 170).isActive = true
        stack.addArrangedSubview(fluid)
        stack.setCustomSpacing(10, after: fluid)
        stack.addArrangedSubview(EngineStyle.label("FLUID MESH  /  палец + Core Motion", size: 10, weight: .medium, color: EngineStyle.muted))
        rain.translatesAutoresizingMaskIntoConstraints = false
        rain.heightAnchor.constraint(equalToConstant: 245).isActive = true
        stack.addArrangedSubview(rain)
        stack.setCustomSpacing(10, after: rain)
        stack.addArrangedSubview(EngineStyle.label("DIGITAL RAIN  /  96 глифов · 1 instanced draw call", size: 10, weight: .medium, color: EngineStyle.muted))
    }

    private func sectionTitle(_ number: String, _ title: String, subtitle: String) {
        let label = EngineStyle.label("\(number)  /  \(title)", size: 21, weight: .semibold)
        label.accessibilityTraits = .header
        stack.addArrangedSubview(label)
        stack.setCustomSpacing(10, after: label)
        stack.addArrangedSubview(EngineStyle.label(subtitle, size: 12, color: EngineStyle.muted))
    }

    @objc private func changeSamples() { loadSamples(count: sampleControl.selectedSegmentIndex == 0 ? 1_000_000 : 2_000_000) }

    private func loadSamples(count: Int) {
        loadTask?.cancel()
        stopStreaming()
        live.isOn = false
        live.isEnabled = false
        spinner.startAnimating()
        status.text = "Подготовка \(count.formatted()) точек…"
        loadTask = Task { [weak self] in
            let generation = Task.detached(priority: .userInitiated) { try MetalSampleSignal.make(count: count) }
            do {
                let points = try await withTaskCancellationHandler(operation: { try await generation.value }, onCancel: { generation.cancel() })
                try Task.checkCancellation()
                guard let self else { return }
                try await self.chart.setPoints(points, reserveCapacity: count + 500_000)
                try Task.checkCancellation()
                self.status.text = "\(count.formatted()) точек загружено · XY Float32"
                self.live.isEnabled = true
                self.spinner.stopAnimating()
            } catch is CancellationError { /* a newer dataset or a popped page owns the UI */ }
            catch {
                self?.status.text = error.localizedDescription
                self?.spinner.stopAnimating()
            }
        }
    }

    private func updateMetrics(_ metrics: MetalChartMetrics) {
        renderStat.text = String(format: "%.0f /с", metrics.renderedFramesPerSecond)
        gpuStat.text = metrics.gpuMilliseconds > 0 ? String(format: "%.2f мс", metrics.gpuMilliseconds) : "н/д"
        cpuStat.text = String(format: "%.2f мс", metrics.cpuEncodingMilliseconds)
        geometry.text = "\(metrics.points.formatted()) точек  →  \(metrics.vertices.formatted()) вершин"
        geometry.accessibilityIdentifier = "chartGeometry"
    }

    func didSelectMetalTransitionBackend(_ metal: Bool) {
#if DEBUG
        backButton?.accessibilityValue = metal ? "Metal" : "UIKit fallback"
#endif
    }

    @objc private func toggleLive() { if live.isOn { startStreaming() } else { stopStreaming() } }

    private func startStreaming() {
        guard streamTimer == nil, live.isOn, chart.pointCount > 0 else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.appendBatch() }
        }
        timer.tolerance = 0.015
        RunLoop.main.add(timer, forMode: .common)
        streamTimer = timer
    }

    private func stopStreaming() {
        streamRevision += 1
        streamTimer?.invalidate()
        streamTimer = nil
        streamTask?.cancel()
        streamTask = nil
        appending = false
    }

    private func appendBatch() {
        guard !appending else { return }
        appending = true
        let start = chart.pointCount
        let revision = streamRevision
        streamTask = Task { [weak self] in
            do {
                let batch = try await Task.detached { try MetalSampleSignal.make(count: 2048, startingAt: start) }.value
                try Task.checkCancellation()
                guard let self, self.live.isOn, self.streamRevision == revision else { return }
                try self.chart.append(batch)
                self.status.text = "LIVE · \(self.chart.pointCount.formatted()) / \(self.chart.pointCapacity.formatted()) точек"
                self.appending = false
            } catch is CancellationError {
                if self?.streamRevision == revision { self?.appending = false }
            }
            catch {
                guard self?.streamRevision == revision else { return }
                self?.stopStreaming()
                self?.live.isOn = false
                self?.status.text = error.localizedDescription
            }
        }
    }
}

private final class TransitionTriggerButton: UIButton {
    var lastPoint: CGPoint?
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        lastPoint = touch?.location(in: window)
        super.endTracking(touch, with: event)
    }
}

private final class MetalTransitionDestination: UIViewController, MetalTransitionBackendReporting {
    private let style: MetalTransitionStyle
    private weak var backButton: UIButton?
    init(style: MetalTransitionStyle) { self.style = style; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(style:)") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = EngineStyle.background
        let background: UIView = style == .glitchRGB ? MatrixDigitalRainView() : FluidMeshGradientView(intensity: 0.6)
        background.frame = view.bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        background.isUserInteractionEnabled = false
        background.accessibilityElementsHidden = true
        view.addSubview(background)
        let shade = UIView(frame: view.bounds)
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        shade.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(shade)
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 24
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        let back = EngineStyle.button("Назад к движку", symbol: "arrow.left")
        back.accessibilityIdentifier = "transitionBack"
        backButton = back
        back.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        content.addArrangedSubview(back)
        content.addArrangedSubview(EngineStyle.label("ВЫ ПО ТУ СТОРОНУ", size: 11, weight: .semibold, color: EngineStyle.accent))
        let title = EngineStyle.label(["Noise.\nInto signal.", "Make\nwaves.", "Break\nthe pattern."][Int(style.rawValue)], size: 51, weight: .bold)
        title.accessibilityTraits = .header
        content.addArrangedSubview(title)
        content.addArrangedSubview(EngineStyle.label(style.title + "\n0.5 секунды · UIKit → Metal → UIKit", size: 14, color: UIColor.white.withAlphaComponent(0.75)))
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            content.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func didSelectMetalTransitionBackend(_ metal: Bool) {
#if DEBUG
        // Invisible test instrumentation; release VoiceOver copy contains no renderer details.
        backButton?.accessibilityValue = metal ? "Metal" : "UIKit fallback"
#endif
    }
}

private extension NSLayoutConstraint {
    func priority(_ value: Float) -> NSLayoutConstraint { priority = UILayoutPriority(value); return self }
}
