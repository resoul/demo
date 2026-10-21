import UIKit
import MetalKit

private enum LabStyle {
    static let background = UIColor(red: 0.035, green: 0.039, blue: 0.047, alpha: 1)
    static let surface = UIColor(red: 0.075, green: 0.082, blue: 0.094, alpha: 1)
    static let muted = UIColor(red: 0.51, green: 0.54, blue: 0.59, alpha: 1)
    static let orange = UIColor(red: 1, green: 0.37, blue: 0.12, alpha: 1)
    static let border = UIColor.white.withAlphaComponent(0.08)

    static func label(_ text: String, size: CGFloat = 13, weight: UIFont.Weight = .regular,
                      color: UIColor = .white) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    static func stack(_ views: [UIView], spacing: CGFloat = 12, axis: NSLayoutConstraint.Axis = .vertical) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = axis
        stack.spacing = spacing
        return stack
    }

    static func card(_ content: UIView, inset: CGFloat = 20) -> UIView {
        let card = UIView()
        card.backgroundColor = surface
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.layer.borderColor = border.cgColor
        card.layer.borderWidth = 1
        card.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset)
        ])
        return card
    }
}

private final class MetricTile: UIView {
    let valueLabel = LabStyle.label("—", size: 26, weight: .medium)
    let detailLabel = LabStyle.label("Ожидание замера", size: 10, color: LabStyle.muted)

    init(title: String, accent: Bool = false) {
        super.init(frame: .zero)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 26, weight: .medium)
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.65
        valueLabel.numberOfLines = 1
        if accent { valueLabel.textColor = LabStyle.orange }
        let contents = LabStyle.stack([LabStyle.label(title, size: 10, weight: .semibold, color: LabStyle.muted),
                                       valueLabel, detailLabel], spacing: 7)
        let card = LabStyle.card(contents, inset: 15)
        addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor), card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor), card.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        isAccessibilityElement = true
        accessibilityLabel = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ value: String, detail: String) {
        valueLabel.text = value
        detailLabel.text = detail
        accessibilityValue = "\(value), \(detail)"
    }
}

private final class FrameHistoryView: UIView {
    var values: [Double] = [] { didSet { setNeedsDisplay() } }
    var budgetMS = 1_000.0 / 60 { didSet { setNeedsDisplay() } }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let maxMS = max(budgetMS * 2, (values.max() ?? 0) * 1.1)
        let y = bounds.height * (1 - budgetMS / maxMS)
        context.setStrokeColor(LabStyle.muted.withAlphaComponent(0.35).cgColor)
        context.setLineDash(phase: 0, lengths: [3, 4])
        context.move(to: CGPoint(x: 0, y: y))
        context.addLine(to: CGPoint(x: bounds.width, y: y))
        context.strokePath()
        guard values.count > 1 else { return }
        context.setLineDash(phase: 0, lengths: [])
        context.setStrokeColor(LabStyle.orange.cgColor)
        context.setLineWidth(1.8)
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: bounds.width * CGFloat(index) / CGFloat(max(59, values.count - 1)),
                                y: bounds.height * (1 - min(value / maxMS, 1)))
            if index == 0 { context.move(to: point) } else { context.addLine(to: point) }
        }
        context.strokePath()
    }
}

class BenchmarkViewController: UIViewController, UIScrollViewDelegate {
    private(set) var activeAnimation: AnimationView?
    private let previewContainer = UIView()
    private weak var benchmarkScroll: UIScrollView?
    private let effectControl = UISegmentedControl(items: AnimationEffect.allCases.map(\.title))
    private let parameterLabel = LabStyle.label("Заполнение", size: 12, color: LabStyle.muted)
    private let previewMetrics = LabStyle.label("FPS —   ·   Frame —   ·   CPU —", size: 10, weight: .medium)
    private var effect: AnimationEffect = .lava
    private var metalAvailable = MTLCreateSystemDefaultDevice() != nil
    private let profiler = PerformanceProfiler()
    private let engineControl = UISegmentedControl(items: ["UIKit", "Metal"])
    private let rateControl = UISegmentedControl(items: ["60 FPS", "120 FPS"])
    private let progressSlider = UISlider()
    private let progressLabel = LabStyle.label("68", size: 56, weight: .light)
    private let engineBadge = LabStyle.label("●  METAL", size: 11, weight: .bold, color: LabStyle.orange)
    private let engineDescription = LabStyle.label("", size: 12, color: LabStyle.muted)
    private let environmentLabel = LabStyle.label("", size: 11, color: LabStyle.muted)
    private let runStatus = LabStyle.label("2 с прогрева + 10 с замера для каждого режима.", size: 12, color: LabStyle.muted)
    private let resultsStack = UIStackView()
    private let benchmarkButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private let history = FrameHistoryView()
    private let fpsTile = MetricTile(title: "DISPLAY FPS", accent: true)
    private let frameTile = MetricTile(title: "FRAME INTERVAL")
    private let cpuTile = MetricTile(title: "CPU · ПРОЦЕСС")
    private let gpuTile = MetricTile(title: "GPU · METAL", accent: true)
    private let encodeTile = MetricTile(title: "CPU · UPDATE / ENCODE")
    private let latencyTile = MetricTile(title: "COMMAND LATENCY")
    private var engine: LavaEngine = .metal
    private var run: BenchmarkRun?
    private var completedRun: BenchmarkRun?
    private var isVisible = false
    private var requestedFPS: Int { rateControl.selectedSegmentIndex == 1 ? 120 : 60 }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = LabStyle.background
        overrideUserInterfaceStyle = .dark
        buildInterface()
        configureProfiler()
        effectControl.selectedSegmentIndex = 0
        engineControl.selectedSegmentIndex = 1
        rateControl.selectedSegmentIndex = 0
        progressSlider.value = 0.68
        effectControl.addTarget(self, action: #selector(effectChanged), for: .valueChanged)
        engineControl.addTarget(self, action: #selector(engineChanged), for: .valueChanged)
        rateControl.addTarget(self, action: #selector(rateChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(progressChanged), for: .valueChanged)
        benchmarkButton.addTarget(self, action: #selector(toggleBenchmark), for: .touchUpInside)
        exportButton.addTarget(self, action: #selector(exportResults), for: .touchUpInside)
        NotificationCenter.default.addObserver(self, selector: #selector(suspend),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        let arguments = ProcessInfo.processInfo.arguments
        if let argument = arguments.first(where: { $0.hasPrefix("--effect=") }),
           let selected = AnimationEffect(rawValue: String(argument.dropFirst(9))) { effect = selected }
        effectControl.selectedSegmentIndex = AnimationEffect.allCases.firstIndex(of: effect) ?? 0
        if arguments.contains("--engine-uikit") { engine = .uiKit }
        if arguments.contains("--progress-zero") { progressSlider.value = 0 }
        if arguments.contains("--progress-full") { progressSlider.value = 1 }
        selectEngine(metalAvailable ? engine : .uiKit)
        progressChanged()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        let maximum = view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60
        rateControl.setEnabled(maximum >= 120, forSegmentAt: 1)
        activeAnimation?.startAnimation()
        profiler.start()
        if ProcessInfo.processInfo.arguments.contains("--benchmark"), run == nil, completedRun == nil,
           metalAvailable { toggleBenchmark() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        suspend()
    }

    private func buildInterface() {
        let scroll = UIScrollView()
        benchmarkScroll = scroll
        scroll.delegate = self
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let wordmark = LabStyle.label("F X   /   L A B", size: 12, weight: .bold)
        let version = LabStyle.label("RENDER STUDY  02", size: 9, weight: .medium, color: LabStyle.muted)
        version.textAlignment = .right
        let topRow = LabStyle.stack([wordmark, version], axis: .horizontal)
        let heading = LabStyle.label("Материя в движении.", size: 31, weight: .semibold)
        let subtitle = LabStyle.label("Пять эффектов. Два движка. Реальные замеры.", size: 14, color: LabStyle.muted)
        let header = LabStyle.stack([topRow, heading, subtitle], spacing: 10)
        header.setCustomSpacing(25, after: topRow)

        effectControl.accessibilityLabel = "Эффект"
        effectControl.selectedSegmentTintColor = UIColor(white: 0.23, alpha: 1)
        effectControl.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 12, weight: .medium)], for: .normal)
        effectControl.heightAnchor.constraint(equalToConstant: 38).isActive = true
        engineControl.accessibilityLabel = "Режим отрисовки"
        engineControl.selectedSegmentTintColor = UIColor(white: 0.23, alpha: 1)
        engineControl.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 11, weight: .semibold)], for: .normal)
        engineControl.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let previewTitle = LabStyle.label("LIVE PREVIEW", size: 10, weight: .semibold, color: LabStyle.muted)
        engineBadge.textAlignment = .right
        let previewHeader = LabStyle.stack([previewTitle, engineBadge], axis: .horizontal)
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 56, weight: .light)
        let percent = LabStyle.label("%", size: 22, weight: .light, color: LabStyle.muted)
        let progressRow = LabStyle.stack([progressLabel, percent, UIView(), parameterLabel], spacing: 4, axis: .horizontal)
        progressRow.alignment = .firstBaseline
        progressLabel.setContentHuggingPriority(.required, for: .horizontal)
        percent.setContentHuggingPriority(.required, for: .horizontal)
        previewContainer.heightAnchor.constraint(equalToConstant: 220).isActive = true
        previewMetrics.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        previewMetrics.textAlignment = .center
        previewMetrics.numberOfLines = 1
        previewMetrics.adjustsFontSizeToFitWidth = true
        previewMetrics.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        previewMetrics.layer.cornerRadius = 7
        previewMetrics.clipsToBounds = true
        previewMetrics.isUserInteractionEnabled = false
        previewContainer.addSubview(previewMetrics)
        previewMetrics.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewMetrics.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 10),
            previewMetrics.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 10),
            previewMetrics.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -10),
            previewMetrics.heightAnchor.constraint(equalToConstant: 24)
        ])
        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.minimumTrackTintColor = LabStyle.orange
        progressSlider.maximumTrackTintColor = UIColor(white: 0.23, alpha: 1)
        progressSlider.thumbTintColor = .white
        progressSlider.accessibilityLabel = "Параметр эффекта"
        let zero = LabStyle.label("0%", size: 10, color: LabStyle.muted)
        let full = LabStyle.label("100%", size: 10, color: LabStyle.muted)
        full.textAlignment = .right
        let ticks = LabStyle.stack([zero, full], axis: .horizontal)
        let preview = LabStyle.card(LabStyle.stack([previewHeader, progressRow, previewContainer,
                                                    progressSlider, ticks, engineDescription], spacing: 12))

        let metricsTitle = LabStyle.label("Телеметрия", size: 19, weight: .semibold)
        let sampleRate = LabStyle.label("●  LIVE · 0.5 s", size: 10, weight: .medium, color: LabStyle.orange)
        sampleRate.textAlignment = .right
        let metricsHeader = LabStyle.stack([metricsTitle, sampleRate], axis: .horizontal)
        var rows: [UIStackView] = []
        for pair in [[fpsTile, frameTile], [cpuTile, gpuTile], [encodeTile, latencyTile]] {
            let row = LabStyle.stack(pair, spacing: 10, axis: .horizontal)
            row.distribution = .fillEqually
            rows.append(row)
        }
        history.heightAnchor.constraint(equalToConstant: 48).isActive = true
        history.backgroundColor = .clear
        history.isAccessibilityElement = true
        history.accessibilityLabel = "График среднего интервала кадров за последние 30 секунд"
        let historyCaption = LabStyle.label("FRAME INTERVAL  /  30 s     ··· целевой бюджет", size: 9, color: LabStyle.muted)
        let historyCard = LabStyle.card(LabStyle.stack([historyCaption, history], spacing: 12), inset: 16)
        let rateLabel = LabStyle.label("Частота обновления", size: 13, color: LabStyle.muted)
        rateControl.accessibilityLabel = "Целевой FPS"
        rateControl.selectedSegmentTintColor = UIColor(white: 0.23, alpha: 1)
        rateControl.widthAnchor.constraint(equalToConstant: 172).isActive = true
        let rateRow = LabStyle.stack([rateLabel, rateControl], axis: .horizontal)
        rateRow.alignment = .center

        let benchmarkTitle = LabStyle.label("Проверить гипотезу", size: 19, weight: .semibold)
        let benchmarkExplanation = LabStyle.label("Последовательный A/B-тест при одинаковом прогрессе и разрешении. Результат — реальные замеры этого устройства.",
                                                 size: 12, color: LabStyle.muted)
        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.title = "Запустить A/B-тест"
        buttonConfig.image = UIImage(systemName: "play.fill")
        buttonConfig.imagePadding = 9
        buttonConfig.baseBackgroundColor = LabStyle.orange
        buttonConfig.baseForegroundColor = .black
        buttonConfig.cornerStyle = .medium
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        benchmarkButton.configuration = buttonConfig
        var exportConfig = UIButton.Configuration.bordered()
        exportConfig.title = "Экспорт CSV"
        exportConfig.image = UIImage(systemName: "square.and.arrow.up")
        exportConfig.imagePadding = 8
        exportConfig.baseForegroundColor = .white
        exportButton.configuration = exportConfig
        exportButton.isEnabled = false
        resultsStack.axis = .vertical
        resultsStack.spacing = 14
        resultsStack.isHidden = true
        let benchmarkCard = LabStyle.card(LabStyle.stack([benchmarkTitle, benchmarkExplanation,
                                                         benchmarkButton, runStatus, resultsStack, exportButton], spacing: 16))

        let methodology = LabStyle.label("КАК ЧИТАТЬ МЕТРИКИ", size: 10, weight: .semibold, color: LabStyle.muted)
        let notes = LabStyle.label("FPS и Frame Interval показывают частоту CADisplayLink, а не доказательство показа каждого кадра. CPU — весь процесс; 100% = одно ядро. CPU Update / Encode — работа приложения над кадром. GPU — время Metal command buffer; для UIKit нужен Instruments. Command Latency включает очередь и ожидание завершения. Core Animation также использует GPU.", size: 11, color: LabStyle.muted)
        let footer = LabStyle.stack([methodology, notes, environmentLabel], spacing: 10)
        let content = LabStyle.stack([header, effectControl, engineControl, preview, metricsHeader,
                                      LabStyle.stack(rows, spacing: 10), historyCard, rateRow, benchmarkCard, footer], spacing: 22)
        scroll.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        let width = content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
            content.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(lessThanOrEqualTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 640), width
        ])
    }

    private func configureProfiler() {
        profiler.onFrame = { [weak self] time in
            guard let self else { return }
            guard let animation = self.activeAnimation else { return }
            let start = CACurrentMediaTime()
            animation.render(time: time)
            if self.engine == .uiKit {
                self.profiler.measurements.recordCPU((CACurrentMediaTime() - start) * 1_000,
                                                      generation: self.profiler.measurements.generation)
            }
        }
        profiler.onSnapshot = { [weak self] in self?.show($0) }
    }

    private func selectEngine(_ requested: LavaEngine) {
        activeAnimation?.stopAnimation()
        activeAnimation?.removeFromSuperview()
        profiler.measurements.reset()
        var animation = effect.makeView(engine: requested)
        var chosen = requested
        var failure: String?
        if let metal = animation as? MetalAnimationView, !metal.isAvailable {
            failure = metal.unavailabilityReason
            metalAvailable = false
            chosen = .uiKit
            animation = effect.makeView(engine: .uiKit)
            cancelBenchmark(message: failure ?? "Metal недоступен для этого эффекта.")
        }
        engine = chosen
        engineControl.selectedSegmentIndex = chosen == .uiKit ? 0 : 1
        engineControl.setEnabled(metalAvailable, forSegmentAt: 1)
        benchmarkButton.isEnabled = metalAvailable
        animation.externallyDriven = true
        animation.progress = progressSlider.value
        animation.isUserInteractionEnabled = run == nil
        animation.onProgressChanged = { [weak self] value in
            self?.progressSlider.value = value
            self?.progressLabel.text = "\(Int((value * 100).rounded()))"
        }
        previewContainer.insertSubview(animation, at: 0)
        animation.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            animation.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            animation.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            animation.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            animation.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor)
        ])
        benchmarkScroll?.panGestureRecognizer.require(toFail: animation.interactionPan)
        activeAnimation = animation
        profiler.measurements = (animation as? MetalAnimationView)?.measurements ?? RenderMeasurements()
        profiler.reset()
        parameterLabel.text = effect.parameterTitle
        progressSlider.accessibilityLabel = effect.parameterTitle
        engineBadge.text = chosen == .metal ? "●  METAL" : "●  UIKIT"
        engineDescription.text = failure ?? (effect.details(engine: chosen) + "\n" + effect.interactionHint)
        history.values = []
        resetTiles()
        if isVisible { animation.startAnimation() }
    }

    @objc private func effectChanged() {
        effect = AnimationEffect.allCases[effectControl.selectedSegmentIndex]
        metalAvailable = MTLCreateSystemDefaultDevice() != nil
        selectEngine(engine)
    }

    private func resetTiles() {
        previewMetrics.text = "FPS —   ·   Frame —   ·   CPU —"
        [fpsTile, frameTile, cpuTile, encodeTile].forEach { $0.update("—", detail: "Сбор данных…") }
        gpuTile.update("—", detail: engine == .metal ? "Сбор данных…" : "Недоступно для UIKit")
        latencyTile.update("—", detail: engine == .metal ? "Сбор данных…" : "Только Metal")
    }

    @objc private func engineChanged() { selectEngine(engineControl.selectedSegmentIndex == 0 ? .uiKit : .metal) }

    @objc private func progressChanged() {
        activeAnimation?.progress = progressSlider.value
        progressLabel.text = "\(Int((progressSlider.value * 100).rounded()))"
    }

    @objc private func rateChanged() {
        profiler.targetFPS = requestedFPS
        profiler.reset()
        history.budgetMS = 1_000 / Double(requestedFPS)
        history.values = []
        resetTiles()
    }

    private func show(_ sample: PerformanceSnapshot) {
        let cpuText = sample.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—"
        previewMetrics.text = String(format: "FPS %.1f   ·   Frame %.2f ms   ·   CPU ", sample.fps, sample.frameMS) + cpuText
        fpsTile.update(String(format: "%.1f", sample.fps), detail: "Цель \(requestedFPS) FPS")
        frameTile.update(String(format: "%.2f ms", sample.frameMS), detail: String(format: "p95  %.2f ms", sample.p95MS))
        cpuTile.update(sample.cpuPercent.map { String(format: "%.1f %%", $0) } ?? "—", detail: "100% = одно ядро")
        encodeTile.update(sample.render.cpuMS.isEmpty ? "—" : String(format: "%.3f ms", sample.render.cpuMS.mean),
                          detail: engine == .metal ? "Encode + drawable + commit" : "Обновление CA-слоёв")
        if engine == .metal {
            gpuTile.update(sample.render.gpuMS.isEmpty ? "—" : String(format: "%.3f ms", sample.render.gpuMS.mean),
                           detail: String(format: "%.1f completed FPS", sample.completedFPS))
            latencyTile.update(sample.render.latencyMS.isEmpty ? "—" : String(format: "%.2f ms", sample.render.latencyMS.mean),
                               detail: sample.render.failedFrames > 0 ? "Ошибок GPU: \(sample.render.failedFrames)" : "CPU start → GPU complete")
        }
        history.values = Array((history.values + [sample.frameMS]).suffix(60))
        let thermal = ["nominal", "fair", "serious", "critical"]
        let thermalName = thermal.indices.contains(sample.thermalState) ? thermal[sample.thermalState] : "unknown"
        environmentLabel.text = "\(BenchmarkRun.isSimulator ? "SIMULATOR" : "DEVICE") · \(BenchmarkRun.buildConfiguration) · iOS \(UIDevice.current.systemVersion)\nThermal: \(thermalName) · Low Power: \(sample.lowPowerMode ? "ON" : "OFF")\nДля сравнения используйте Release на физическом iPhone без отладчика."
        guard let run else { return }
        let event = run.consume(sample)
        runStatus.text = run.status
        engineBadge.text = run.status
        switch event {
        case .collecting: break
        case .measurementStarted: profiler.reset()
        case .switchEngine(let next): selectEngine(next)
        case .finished:
            completedRun = run
            self.run = nil
            engineBadge.text = engine == .metal ? "●  METAL" : "●  UIKIT"
            setControlsLocked(false)
            showResults(run)
        }
    }

    @objc private func toggleBenchmark() {
        if run != nil {
            cancelBenchmark(message: "Тест отменён. Неполные результаты отброшены.")
            return
        }
        guard metalAvailable else { return }
        let candidate = effect.makeView(engine: .metal) as! MetalAnimationView
        guard candidate.isAvailable else {
            runStatus.text = candidate.unavailabilityReason
            return
        }
        selectEngine(engine)
        view.layoutIfNeeded()
        if let scroll = benchmarkScroll {
            scroll.scrollRectToVisible(previewContainer.convert(previewContainer.bounds, to: scroll), animated: false)
        }
        let scale = view.window?.screen.scale ?? 1
        run = BenchmarkRun(firstEngine: engine, requestedFPS: requestedFPS, progress: progressSlider.value,
                           drawableSize: CGSize(width: previewContainer.bounds.width * scale, height: previewContainer.bounds.height * scale),
                           effect: effect)
        completedRun = nil
        resultsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        resultsStack.isHidden = true
        setControlsLocked(true)
        runStatus.text = run?.status
        profiler.reset()
    }

    private func setControlsLocked(_ locked: Bool) {
        effectControl.isEnabled = !locked
        activeAnimation?.isUserInteractionEnabled = !locked
        engineControl.isEnabled = !locked
        rateControl.isEnabled = !locked
        progressSlider.isEnabled = !locked
        exportButton.isEnabled = !locked && completedRun != nil
        benchmarkButton.configuration?.title = locked ? "Остановить тест" : "Запустить A/B-тест"
        benchmarkButton.configuration?.image = UIImage(systemName: locked ? "stop.fill" : "play.fill")
    }

    private func cancelBenchmark(message: String) {
        guard run != nil else { return }
        run = nil
        engineBadge.text = engine == .metal ? "●  METAL" : "●  UIKIT"
        setControlsLocked(false)
        runStatus.text = message
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelBenchmark(message: "Тест прерван прокруткой. Для замера превью должно оставаться на экране.")
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        cancelBenchmark(message: "Тест прерван: изменился размер отрисовки. Запустите заново.")
        super.viewWillTransition(to: size, with: coordinator)
    }

    @objc private func suspend() {
        activeAnimation?.stopAnimation()
        profiler.stop()
        cancelBenchmark(message: "Тест прерван при уходе с экрана или потере активности. Запустите заново.")
    }

    @objc private func resume() {
        if isVisible { activeAnimation?.startAnimation(); profiler.start() }
    }

    private func showResults(_ run: BenchmarkRun) {
        resultsStack.isHidden = false
        for result in run.results.sorted(by: { $0.engine.rawValue > $1.engine.rawValue }) {
            let title = LabStyle.label(result.engine.rawValue, size: 14, weight: .semibold,
                                       color: result.engine == .metal ? LabStyle.orange : .white)
            let cpu = result.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—"
            let gpu = result.gpuMS.isEmpty ? "—" : String(format: "%.3f ms", result.gpuMS.mean)
            let detail = LabStyle.label(String(format: "%.1f FPS   ·   p95 %.2f ms", result.fps, result.p95MS)
                                         + "\nCPU \(cpu)   ·   GPU \(gpu)", size: 12, color: LabStyle.muted)
            resultsStack.addArrangedSubview(LabStyle.stack([title, detail], spacing: 5))
        }
        runStatus.text = run.environmentChanged
            ? "Готово. Во время теста изменились нагрев или энергосбережение; повторите замер."
            : "Готово · \(run.effect.title) · \(run.requestedFPS) FPS · прогресс \(Int(run.progress * 100))%. Сохраните CSV для сравнения."
    }

    @objc private func exportResults() {
        guard let completedRun else { return }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fx-\(completedRun.effect.rawValue)-\(UUID().uuidString.prefix(8)).csv")
            try completedRun.csv().write(to: url, atomically: true, encoding: .utf8)
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = exportButton
            sheet.popoverPresentationController?.sourceRect = exportButton.bounds
            present(sheet, animated: true)
        } catch {
            runStatus.text = "Не удалось сохранить CSV: \(error.localizedDescription)"
        }
    }
}
