import UIKit
import MetalKit

enum MetalLabEffect: String, CaseIterable {
    case particles, liquid, glass
    var title: String {
        switch self {
        case .particles: "Частицы"
        case .liquid: "Вода / Физика"
        case .glass: "Оптика / Стекло"
        }
    }
    var detail: String {
        switch self {
        case .particles: "Compute → render · до 1 000 000 частиц"
        case .liquid: "Глубокая вода · 4 волны · пена · каустика"
        case .glass: "Raymarching · два преломления · RGB dispersion"
        }
    }
    var hint: String {
        switch self {
        case .particles: "Удерживайте или перетягивайте палец, чтобы управлять роем."
        case .liquid: "Тап создаёт затухающую волну. Наклон можно включить ниже."
        case .glass: "Перетягивайте линзу: сетка и свет преломляются внутри объёма."
        }
    }
}

enum MetalLabStyle {
    static let cyan = UIColor(red: 0.2, green: 0.85, blue: 1, alpha: 1)
    static let muted = UIColor(red: 0.55, green: 0.6, blue: 0.68, alpha: 1)
    static func label(_ text: String, size: CGFloat = 12, weight: UIFont.Weight = .regular) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: size, weight: weight)
        label.numberOfLines = 0
        return label
    }
    static func stack(_ views: [UIView], axis: NSLayoutConstraint.Axis = .vertical, spacing: CGFloat = 8) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = axis
        stack.spacing = spacing
        return stack
    }
}

final class MetalLabMetric: UIStackView {
    private let value = MetalLabStyle.label("—", size: 19, weight: .medium)
    init(_ title: String) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 3
        let caption = MetalLabStyle.label(title, size: 9, weight: .semibold)
        caption.textColor = MetalLabStyle.muted
        value.font = .monospacedDigitSystemFont(ofSize: 19, weight: .medium)
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.7
        value.numberOfLines = 1
        value.textColor = MetalLabStyle.cyan
        addArrangedSubview(caption)
        addArrangedSubview(value)
        isAccessibilityElement = true
        accessibilityLabel = title
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(_ text: String) { value.text = text; accessibilityValue = text }
}

final class MetalLabViewController: UIViewController {
    private(set) var activeEffectView: MetalAnimationView?
    private(set) var selectedEffect: MetalLabEffect = .particles
    private let profiler = PerformanceProfiler(cpuScope: .mainThread)
    private let effectControl = UISegmentedControl(items: MetalLabEffect.allCases.map(\.title))
    private let rateControl = UISegmentedControl(items: ["60 FPS", "120 FPS"])
    private let forceControl = UISegmentedControl(items: ["Притяжение", "Отталкивание"])
    private let parameterSlider = UISlider()
    private let motionSwitch = UISwitch()
    private let canvas = UIView()
    private weak var contentScroll: UIScrollView?
    private let detail = MetalLabStyle.label("", size: 13, weight: .semibold)
    private let hint = MetalLabStyle.label("", size: 11)
    private let parameterTitle = MetalLabStyle.label("", size: 12)
    private let parameterValue = MetalLabStyle.label("", size: 14, weight: .medium)
    private let motionCaption = MetalLabStyle.label("Наклон устройства", size: 12)
    private lazy var motionRow = MetalLabStyle.stack([motionCaption, motionSwitch], axis: .horizontal)
    private let fps = MetalLabMetric("DISPLAY FPS")
    private let gpu = MetalLabMetric("GPU FRAME · ms")
    private let cpu = MetalLabMetric("CPU · MAIN THREAD")
    private let entities = MetalLabMetric("ACTIVE ENTITIES")
    private let frameStatus = MetalLabStyle.label("Сбор метрик…", size: 10)
    private let environment = MetalLabStyle.label("", size: 10)
    private var isVisible = false
    private var particleCount = 100_000
    private var liquidLevel: Float = 0.62
    private var opticalStrength: Float = 0.65
    private var requestedFPS: Int { rateControl.selectedSegmentIndex == 1 ? 120 : 60 }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Metal Lab"
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.025, green: 0.035, blue: 0.055, alpha: 1)
        let arguments = ProcessInfo.processInfo.arguments
        if let arg = arguments.first(where: { $0.hasPrefix("--lab-effect=") }),
           let effect = MetalLabEffect(rawValue: String(arg.dropFirst(13))) { selectedEffect = effect }
        if let arg = arguments.first(where: { $0.hasPrefix("--particles-count=") }),
           let count = Int(arg.dropFirst(18)) {
            particleCount = min(max(count, MetalParticlesView.minimumCount), MetalParticlesView.maximumCount)
        }
        buildInterface()
        configureProfiler()
        effectControl.selectedSegmentIndex = MetalLabEffect.allCases.firstIndex(of: selectedEffect) ?? 0
        rateControl.selectedSegmentIndex = 0
        forceControl.selectedSegmentIndex = 0
        effectControl.addTarget(self, action: #selector(effectChanged), for: .valueChanged)
        parameterSlider.addTarget(self, action: #selector(parameterChanged), for: .valueChanged)
        rateControl.addTarget(self, action: #selector(rateChanged), for: .valueChanged)
        forceControl.addTarget(self, action: #selector(forceChanged), for: .valueChanged)
        motionSwitch.addTarget(self, action: #selector(motionChanged), for: .valueChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(suspend), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
        replaceEffect()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        rateControl.setEnabled((view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60) >= 120, forSegmentAt: 1)
        resume()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        suspend()
    }

    private func buildInterface() {
        let wordmark = MetalLabStyle.label("M E T A L   /   L A B", size: 11, weight: .bold)
        wordmark.textColor = MetalLabStyle.cyan
        let heading = MetalLabStyle.label("GPU под нагрузкой", size: 27, weight: .semibold)
        let subtitle = MetalLabStyle.label("Compute · жидкость · объёмная оптика", size: 11)
        subtitle.textColor = MetalLabStyle.muted
        let header = MetalLabStyle.stack([wordmark, heading, subtitle], spacing: 4)
        effectControl.accessibilityLabel = "Эффект Metal Lab"
        effectControl.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 10, weight: .semibold)], for: .normal)
        effectControl.heightAnchor.constraint(equalToConstant: 36).isActive = true
        canvas.backgroundColor = .black
        canvas.layer.cornerRadius = 22
        canvas.clipsToBounds = true
        canvas.setContentHuggingPriority(.defaultLow, for: .vertical)
        canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        let first = MetalLabStyle.stack([fps, gpu], axis: .horizontal, spacing: 16)
        let second = MetalLabStyle.stack([cpu, entities], axis: .horizontal, spacing: 16)
        first.distribution = .fillEqually
        second.distribution = .fillEqually
        let overlay = MetalLabStyle.stack([first, second], spacing: 10)
        overlay.isLayoutMarginsRelativeArrangement = true
        overlay.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        overlay.layer.cornerRadius = 14
        overlay.isUserInteractionEnabled = false
        canvas.addSubview(overlay)
        frameStatus.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        frameStatus.layer.cornerRadius = 6
        frameStatus.clipsToBounds = true
        frameStatus.textAlignment = .center
        frameStatus.isUserInteractionEnabled = false
        canvas.addSubview(frameStatus)
        for item in [overlay, frameStatus] { item.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 12),
            overlay.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 12),
            overlay.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -12),
            frameStatus.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 12),
            frameStatus.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -12),
            frameStatus.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -12),
            frameStatus.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
        hint.textColor = MetalLabStyle.muted
        parameterSlider.tintColor = MetalLabStyle.cyan
        parameterSlider.accessibilityLabel = "Параметр Metal Lab"
        parameterValue.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        parameterValue.textAlignment = .right
        let parameterRow = MetalLabStyle.stack([parameterTitle, parameterValue], axis: .horizontal)
        motionRow.alignment = .center
        forceControl.accessibilityLabel = "Сила касания"
        motionSwitch.accessibilityLabel = "Управление наклоном"
        motionSwitch.onTintColor = MetalLabStyle.cyan
        rateControl.accessibilityLabel = "Целевой FPS Metal Lab"
        rateControl.widthAnchor.constraint(equalToConstant: 170).isActive = true
        let rateRow = MetalLabStyle.stack([MetalLabStyle.label("Целевая частота", size: 12), rateControl], axis: .horizontal)
        rateRow.alignment = .center
        environment.textColor = MetalLabStyle.muted
        let controls = MetalLabStyle.stack([detail, hint, parameterRow, parameterSlider, forceControl, motionRow, rateRow, environment], spacing: 7)
        controls.setContentHuggingPriority(.required, for: .vertical)
        controls.setContentCompressionResistancePriority(.required, for: .vertical)
        let content = MetalLabStyle.stack([header, effectControl, canvas, controls], spacing: 12)
        let scroll = UIScrollView()
        contentScroll = scroll
        scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        let desiredWidth = content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        desiredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -10),
            content.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor, constant: -22),
            content.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 900), desiredWidth
        ])
    }

    private func configureProfiler() {
        profiler.onFrame = { [weak self] time in self?.activeEffectView?.render(time: time) }
        profiler.onSnapshot = { [weak self] in self?.show($0) }
    }

    private func replaceEffect() {
        activeEffectView?.stopAnimation()
        activeEffectView?.removeFromSuperview()
        profiler.measurements.reset()
        let renderer: MetalAnimationView
        switch selectedEffect {
        case .particles:
            let particles = MetalParticlesView()
            particles.particleCount = particleCount
            particles.repelsTouch = forceControl.selectedSegmentIndex == 1
            renderer = particles
        case .liquid:
            let liquid = MetalLiquidView()
            liquid.progress = liquidLevel
            liquid.motionEnabled = motionSwitch.isOn
            renderer = liquid
        case .glass:
            let glass = MetalGlassView()
            glass.progress = opticalStrength
            renderer = glass
        }
        renderer.externallyDriven = true
        renderer.accessibilityLabel = selectedEffect.title
        canvas.insertSubview(renderer, at: 0)
        renderer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            renderer.topAnchor.constraint(equalTo: canvas.topAnchor), renderer.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            renderer.leadingAnchor.constraint(equalTo: canvas.leadingAnchor), renderer.trailingAnchor.constraint(equalTo: canvas.trailingAnchor)
        ])
        activeEffectView = renderer
        contentScroll?.panGestureRecognizer.require(toFail: renderer.interactionPan)
        profiler.measurements = renderer.measurements
        profiler.reset()
        detail.text = renderer.unavailabilityReason ?? selectedEffect.detail
        hint.text = selectedEffect.hint
        forceControl.isHidden = selectedEffect != .particles
        motionRow.isHidden = selectedEffect != .liquid
        if let liquid = renderer as? MetalLiquidView {
            motionSwitch.isEnabled = liquid.motionAvailable
            motionCaption.text = liquid.motionAvailable ? "Наклон устройства" : "Наклон недоступен · используйте тапы"
        }
        parameterSlider.minimumValue = selectedEffect == .particles ? Float(MetalParticlesView.minimumCount) : 0
        parameterSlider.maximumValue = selectedEffect == .particles ? Float(MetalParticlesView.maximumCount) : 1
        switch selectedEffect {
        case .particles: parameterTitle.text = "Количество частиц"; parameterSlider.value = Float(particleCount)
        case .liquid: parameterTitle.text = "Уровень воды"; parameterSlider.value = liquidLevel
        case .glass: parameterTitle.text = "Оптическая плотность"; parameterSlider.value = opticalStrength
        }
        parameterSlider.isEnabled = renderer.isAvailable
        parameterSlider.accessibilityLabel = parameterTitle.text
        resetMetrics()
        updateParameterLabel()
        if isVisible {
            if renderer.isAvailable { renderer.startAnimation(); profiler.start() }
            else { profiler.stop() }
        }
    }

    private var entityCount: Int { selectedEffect == .particles ? particleCount : (selectedEffect == .liquid ? 4 : 1) }
    private func number(_ value: Int) -> String { value.formatted(.number.grouping(.automatic)).replacingOccurrences(of: ",", with: " ") }

    private func updateParameterLabel() {
        parameterValue.text = selectedEffect == .particles ? number(particleCount) : "\(Int(parameterSlider.value * 100))%"
        entities.show(number(entityCount))
    }

    private func resetMetrics() {
        [fps, gpu, cpu].forEach { $0.show("—") }
        frameStatus.text = "Сбор метрик…"
    }

    private func show(_ snapshot: PerformanceSnapshot) {
        fps.show(String(format: "%.1f", snapshot.fps))
        gpu.show(snapshot.render.gpuMS.isEmpty ? "—" : String(format: "%.3f", snapshot.render.gpuMS.mean))
        cpu.show(snapshot.cpuPercent.map { String(format: "%.1f %%", $0) } ?? "—")
        entities.show(number(entityCount))
        let presented = MetalAnimationView.presentationMetricsAvailable
            ? String(format: "%.1f", Double(snapshot.render.presentedFrames) / snapshot.duration) : "n/a"
        frameStatus.text = String(format: "Presented %@ FPS · Completed %.1f FPS\nInterval %.2f ms · p95 %.2f ms",
                                  presented, snapshot.completedFPS,
                                  snapshot.frameMS, snapshot.p95MS)
        let thermal = ["nominal", "fair", "serious", "critical"]
        let state = thermal.indices.contains(snapshot.thermalState) ? thermal[snapshot.thermalState] : "unknown"
        environment.text = "\(BenchmarkRun.isSimulator ? "SIMULATOR" : "DEVICE") · \(BenchmarkRun.buildConfiguration) · thermal \(state) · power \(snapshot.lowPowerMode ? "low" : "normal")"
        if snapshot.render.failedFrames > 0 { detail.text = "Ошибок GPU: \(snapshot.render.failedFrames). Снизьте нагрузку." }
    }

    @objc private func effectChanged() {
        selectedEffect = MetalLabEffect.allCases[effectControl.selectedSegmentIndex]
        replaceEffect()
    }

    @objc private func parameterChanged() {
        switch selectedEffect {
        case .particles:
            particleCount = min(max(Int((parameterSlider.value / 1_000).rounded()) * 1_000, MetalParticlesView.minimumCount), MetalParticlesView.maximumCount)
            (activeEffectView as? MetalParticlesView)?.particleCount = particleCount
        case .liquid: liquidLevel = parameterSlider.value; activeEffectView?.progress = liquidLevel
        case .glass: opticalStrength = parameterSlider.value; activeEffectView?.progress = opticalStrength
        }
        updateParameterLabel()
    }

    @objc private func forceChanged() { (activeEffectView as? MetalParticlesView)?.repelsTouch = forceControl.selectedSegmentIndex == 1 }
    @objc private func motionChanged() { (activeEffectView as? MetalLiquidView)?.motionEnabled = motionSwitch.isOn }
    @objc private func rateChanged() { profiler.targetFPS = requestedFPS; profiler.reset(); resetMetrics() }
    @objc private func suspend() { activeEffectView?.stopAnimation(); profiler.stop() }
    @objc private func resume() {
        guard isVisible, activeEffectView?.isAvailable == true else { return }
        activeEffectView?.startAnimation()
        profiler.start()
    }
}
