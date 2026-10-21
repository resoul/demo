import UIKit

enum GPUExperiment: String, CaseIterable {
    case aquarium, boids, city, rays, cloth, smoke, nbody, sph, reaction, ink
    static let showcase: [Self] = [.aquarium, .boids, .city, .rays, .cloth, .smoke]
    static let computeBench: [Self] = [.nbody, .sph, .reaction, .ink]
    var title: String {
        switch self {
        case .aquarium: "Аквариум"
        case .boids: "Рой / Boids"
        case .city: "GPU-город"
        case .rays: "Трассировка лучей"
        case .cloth: "Ткань"
        case .smoke: "Объёмный дым"
        case .nbody: "N-body · CPU / GPU"
        case .sph: "SPH · до 100 000"
        case .reaction: "Реакция–диффузия"
        case .ink: "Чернила · Stable Fluids"
        }
    }
    var hint: String {
        switch self {
        case .aquarium, .sph: "Палец толкает воду. Уберите перегородку или включите наклон."
        case .boids: "Тяните палец: стая притягивается или избегает касания."
        case .city: "Тяните влево / вправо для поворота камеры. Отключите culling для сравнения."
        case .rays: "Перетягивайте источник света. Стекло преломляет, зеркало отражает."
        case .cloth: "Тяните полотно. В режиме разрыва проведите пальцем по ткани."
        case .smoke: "Палец задаёт источник дыма внутри куба. Кнопка вращает камеру."
        case .nbody: "Одинаковые N и силы; счётчики показывают разницу скоростей."
        case .reaction: "Рисуйте реагент. 100% — сетка нативного разрешения всего экрана."
        case .ink: "Рисуйте цветные чернила пальцем. Слайдер меняет размер расчётной сетки."
        }
    }
    @MainActor func makeView() -> GPUExperimentView {
        switch self {
        case .aquarium: return MetalAquariumView()
        case .boids: return MetalBoidsView()
        case .city: return MetalCityView()
        case .rays: return MetalRaySceneView()
        case .cloth: return MetalClothView()
        case .smoke: return MetalFluidFieldView()
        case .nbody: return MetalNBodyView()
        case .sph:
            let view = MetalAquariumView(); view.stressRange = true; return view
        case .reaction: return MetalReactionView()
        case .ink: return MetalInkView()
        }
    }
}

/// Shared UI/lifecycle, separate catalogs. Only the selected renderer is instantiated.
class GPUExperimentsViewController: UIViewController {
    var experiments: [GPUExperiment] { GPUExperiment.showcase }
    var screenTitle: String { "GPU Showcase" }
    var isComputeBench: Bool { false }
    private(set) var selectedExperiment: GPUExperiment = .aquarium
    private(set) var activeExperimentView: GPUExperimentView?
    private lazy var profiler = PerformanceProfiler(cpuScope: isComputeBench ? .process : .mainThread)
    private let selector = UIButton(type: .system)
    private let slider = UISlider()
    private let stepsControl = UISegmentedControl(items: ["1", "10", "20"])
    private let rate = UISegmentedControl(items: ["60 FPS", "120 FPS"])
    private let action = UIButton(type: .system)
    private let pause = UIButton(type: .system)
    private let reset = UIButton(type: .system)
    private let motion = UISwitch()
    private let canvas = UIView()
    private let scroll = UIScrollView()
    private let detail = MetalLabStyle.label("", size: 11)
    private let hint = MetalLabStyle.label("", size: 11)
    private let loadLabel = MetalLabStyle.label("", size: 13, weight: .medium)
    private let extra = MetalLabStyle.label("", size: 11)
    private let environment = MetalLabStyle.label("", size: 10)
    private let frameStatus = MetalLabStyle.label("Сбор метрик…", size: 10)
    private let fps = MetalLabMetric("DISPLAY / COMPLETED FPS")
    private let gpu = MetalLabMetric("GPU FRAME · ms")
    private lazy var cpu = MetalLabMetric(isComputeBench ? "CPU · PROCESS" : "CPU · MAIN THREAD")
    private let entities = MetalLabMetric("WORKLOAD")
    private let splitLabels = MetalLabStyle.label("CPU                                        GPU", size: 12, weight: .semibold)
    private lazy var motionRow = MetalLabStyle.stack([MetalLabStyle.label("Управление наклоном", size: 12), motion], axis: .horizontal)
    private lazy var stepRow = MetalLabStyle.stack([MetalLabStyle.label("Итерации / шаги", size: 12), stepsControl], axis: .horizontal)
    private var isVisible = false
    private(set) var isPaused = false
    private var stepOptions = [1, 10, 20]
    private var savedLoads: [GPUExperiment: Float] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = screenTitle
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.025, green: 0.035, blue: 0.055, alpha: 1)
        selectedExperiment = experiments[0]
        let arguments = ProcessInfo.processInfo.arguments
        let prefix = isComputeBench ? "--compute-effect=" : "--showcase-effect="
        if let arg = arguments.first(where: { $0.hasPrefix(prefix) }),
           let effect = GPUExperiment(rawValue: String(arg.dropFirst(prefix.count))), experiments.contains(effect) { selectedExperiment = effect }
        if let arg = arguments.first(where: { $0.hasPrefix("--experiment-load=") }), let value = Float(arg.dropFirst(18)), value.isFinite {
            savedLoads[selectedExperiment] = min(max(value, 0), 1)
        }
        buildInterface()
        profiler.onFrame = { [weak self] in self?.activeExperimentView?.render(time: $0) }
        profiler.onSnapshot = { [weak self] in self?.show($0) }
        slider.addTarget(self, action: #selector(loadChanged), for: .valueChanged)
        stepsControl.addTarget(self, action: #selector(stepsChanged), for: .valueChanged)
        rate.addTarget(self, action: #selector(rateChanged), for: .valueChanged)
        action.addTarget(self, action: #selector(performAction), for: .touchUpInside)
        pause.addTarget(self, action: #selector(togglePause), for: .touchUpInside)
        reset.addTarget(self, action: #selector(resetSimulation), for: .touchUpInside)
        motion.addTarget(self, action: #selector(motionChanged), for: .valueChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(suspend), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
        selectExperiment(selectedExperiment)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); isVisible = true
        rate.setEnabled((view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60) >= 120, forSegmentAt: 1)
        resume()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); isVisible = false; suspend()
    }

    private func buildInterface() {
        let header = MetalLabStyle.label(screenTitle, size: 25, weight: .semibold)
        var configuration = UIButton.Configuration.tinted()
        configuration.title = "Выбрать эксперимент"
        configuration.image = UIImage(systemName: "chevron.down")
        configuration.imagePlacement = .trailing; configuration.imagePadding = 12
        configuration.baseForegroundColor = MetalLabStyle.cyan
        selector.configuration = configuration; selector.showsMenuAsPrimaryAction = true
        selector.accessibilityLabel = "Выбор эксперимента"
        canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        canvas.backgroundColor = UIColor(red: 0.012, green: 0.02, blue: 0.04, alpha: 1)
        canvas.layer.cornerRadius = 20; canvas.clipsToBounds = true
        let first = MetalLabStyle.stack([fps, gpu], axis: .horizontal, spacing: 10)
        let second = MetalLabStyle.stack([cpu, entities], axis: .horizontal, spacing: 10)
        first.distribution = .fillEqually; second.distribution = .fillEqually
        let overlay = MetalLabStyle.stack([first,second], spacing: 6)
        overlay.backgroundColor = .black.withAlphaComponent(0.65)
        overlay.layer.cornerRadius = 12; overlay.isUserInteractionEnabled = false
        overlay.isLayoutMarginsRelativeArrangement = true
        overlay.layoutMargins = UIEdgeInsets(top: 10,left: 12,bottom: 10,right: 12)
        frameStatus.backgroundColor = .black.withAlphaComponent(0.65)
        frameStatus.textAlignment = .center; frameStatus.isUserInteractionEnabled = false
        splitLabels.textAlignment = .center; splitLabels.isUserInteractionEnabled = false
        for item in [overlay, frameStatus, splitLabels] { canvas.addSubview(item); item.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 10), overlay.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -10),
            overlay.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 10),
            frameStatus.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -8), frameStatus.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 8),
            frameStatus.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -8), frameStatus.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            splitLabels.leadingAnchor.constraint(equalTo: canvas.leadingAnchor), splitLabels.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            splitLabels.bottomAnchor.constraint(equalTo: frameStatus.topAnchor, constant: -6)
        ])
        slider.minimumValue = 0; slider.maximumValue = 1; slider.tintColor = MetalLabStyle.cyan
        slider.accessibilityLabel = "Сложность эксперимента"
        rate.selectedSegmentIndex = 0
        rate.widthAnchor.constraint(equalToConstant: 170).isActive = true
        stepsControl.widthAnchor.constraint(equalToConstant: 170).isActive = true
        rate.accessibilityLabel = "Целевой FPS эксперимента"
        stepsControl.accessibilityLabel = "Количество шагов симуляции"
        let rateRow = MetalLabStyle.stack([MetalLabStyle.label("Частота", size: 12),rate],axis: .horizontal)
        rateRow.alignment = .center; motionRow.alignment = .center; stepRow.alignment = .center
        for (button, title) in [(pause,"Пауза"),(reset,"Сброс"),(action,"Режим")] {
            var config = UIButton.Configuration.bordered(); config.title = title; config.baseForegroundColor = MetalLabStyle.cyan
            button.configuration = config
        }
        let buttons = MetalLabStyle.stack([pause,reset],axis: .horizontal,spacing: 10); buttons.distribution = .fillEqually
        hint.textColor = MetalLabStyle.muted; environment.textColor = MetalLabStyle.muted
        extra.font = .monospacedDigitSystemFont(ofSize: 11,weight: .regular)
        let controls = MetalLabStyle.stack([detail,hint,loadLabel,slider,stepRow,motionRow,rateRow,action,buttons,extra,environment],spacing: 7)
        controls.setContentHuggingPriority(.required,for: .vertical)
        controls.setContentCompressionResistancePriority(.required,for: .vertical)
        let content = MetalLabStyle.stack([header,selector,canvas,controls],spacing: 10)
        view.addSubview(scroll); scroll.addSubview(content)
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false; content.translatesAutoresizingMaskIntoConstraints = false
        let width = content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32); width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor,constant: 10), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor,constant: -10),
            content.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor), content.widthAnchor.constraint(lessThanOrEqualToConstant: 900), width,
            content.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor,constant: -20)
        ])
    }

    func selectExperiment(_ experiment: GPUExperiment) {
        guard experiments.contains(experiment) else { return }
        activeExperimentView?.stopAnimation(); activeExperimentView?.removeFromSuperview(); profiler.stop()
        selectedExperiment = experiment
        let renderer = experiment.makeView()
        if let load = savedLoads[experiment] { renderer.load = load }
        renderer.externallyDriven = true; renderer.accessibilityLabel = experiment.title
        activeExperimentView = renderer
        canvas.insertSubview(renderer, at: 0); renderer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            renderer.topAnchor.constraint(equalTo: canvas.topAnchor), renderer.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            renderer.leadingAnchor.constraint(equalTo: canvas.leadingAnchor), renderer.trailingAnchor.constraint(equalTo: canvas.trailingAnchor)
        ])
        scroll.panGestureRecognizer.require(toFail: renderer.interactionPan)
        selector.configuration?.title = experiment.title
        selector.menu = UIMenu(children: experiments.map { item in
            UIAction(title: item.title, state: item == experiment ? .on : .off) { [weak self] _ in self?.selectExperiment(item) }
        })
        slider.value = renderer.load
        detail.text = renderer.unavailabilityReason ?? renderer.experimentDescription; hint.text = experiment.hint
        action.configuration?.title = renderer.actionTitle
        splitLabels.isHidden = experiment != .nbody
        motion.isOn = false
        let aquarium = renderer as? MetalAquariumView
        motionRow.isHidden = aquarium?.motionAvailable != true
        stepRow.isHidden = ![.cloth,.smoke,.reaction,.ink].contains(experiment)
        stepOptions = experiment == .reaction ? [1,10,20] : (experiment == .cloth ? [4,8,16] : [8,12,20])
        stepsControl.removeAllSegments()
        for (index, count) in stepOptions.enumerated() { stepsControl.insertSegment(withTitle: String(count), at: index, animated: false) }
        stepsControl.selectedSegmentIndex = stepOptions.firstIndex(of: renderer.simulationSteps) ?? 1
        [slider,action,pause,reset].forEach { $0.isUserInteractionEnabled = renderer.isAvailable }
        profiler.measurements = renderer.measurements
        resetMetrics(); updateLabels(); resume()
    }

    private func updateLabels() {
        guard let renderer = activeExperimentView else { return }
        loadLabel.text = renderer.loadDescription
        action.configuration?.title = renderer.actionTitle
        detail.text = renderer.unavailabilityReason ?? renderer.experimentDescription
    }
    private func resetMetrics() {
        _ = activeExperimentView?.throughput.drain()
        [fps,gpu,cpu,entities].forEach { $0.show("—") }
        frameStatus.text = isPaused ? "Пауза" : "Сбор метрик…"; extra.text = ""
    }
    private func show(_ s: PerformanceSnapshot) {
        guard let renderer = activeExperimentView else { return }
        fps.show(String(format: "%.0f / %.0f", s.fps,s.completedFPS))
        gpu.show(s.render.gpuMS.isEmpty ? "—" : String(format: "%.2f",s.render.gpuMS.mean))
        cpu.show(s.cpuPercent.map { String(format: "%.1f %%",$0) } ?? "—")
        entities.show(renderer.entityCount.formatted())
        let presented = MetalAnimationView.presentationMetricsAvailable ? String(format: "%.1f",Double(s.render.presentedFrames)/s.duration) : "n/a"
        frameStatus.text = String(format: "Interval %.2f ms · p95 %.2f ms\nGPU p95 %@ ms · Presented %@ FPS",s.frameMS,s.p95MS,s.render.gpuMS.isEmpty ? "—" : String(format: "%.2f",s.render.gpuMS.percentile95),presented)
        let rate = renderer.throughput.drain()
        var lines = [renderer.extraMetrics]
        if let gflops = rate.gflops { lines.insert(String(format: "GPU ≈%.2f GFLOPS · по полному command buffer",gflops),at: 0) }
        if let gbps = rate.gbps { lines.insert(String(format: "≈%.2f logical GB/s · оценка, не DRAM bandwidth",gbps),at: 0) }
        extra.text = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        let thermal = ["nominal","fair","serious","critical"]
        environment.text = "\(BenchmarkRun.isSimulator ? "SIMULATOR" : "DEVICE") · \(BenchmarkRun.buildConfiguration) · thermal \(thermal[min(3,max(0,s.thermalState))]) · power \(s.lowPowerMode ? "low" : "normal")"
        if s.render.failedFrames > 0 { environment.text = "Ошибок GPU: \(s.render.failedFrames). Снизьте нагрузку." }
        updateLabels()
    }
    @objc private func loadChanged() {
        let value = (slider.value*50).rounded()/50
        guard activeExperimentView?.load != value else { return }
        activeExperimentView?.load = value; savedLoads[selectedExperiment] = value
        profiler.reset(); _ = activeExperimentView?.throughput.drain(); resetMetrics(); updateLabels()
    }
    @objc private func stepsChanged() { activeExperimentView?.simulationSteps = stepOptions[stepsControl.selectedSegmentIndex]; profiler.reset(); updateLabels() }
    @objc private func rateChanged() { profiler.targetFPS = rate.selectedSegmentIndex == 1 ? 120 : 60; profiler.reset(); resetMetrics() }
    @objc private func motionChanged() { (activeExperimentView as? MetalAquariumView)?.motionEnabled = motion.isOn }
    @objc private func performAction() { activeExperimentView?.performAction(); updateLabels() }
    @objc private func resetSimulation() { activeExperimentView?.resetSimulation(); profiler.reset(); resetMetrics() }
    @objc private func togglePause() {
        isPaused.toggle(); pause.configuration?.title = isPaused ? "Продолжить" : "Пауза"
        if isPaused { suspend(); resetMetrics() } else { resume() }
    }
    @objc private func suspend() { activeExperimentView?.stopAnimation(); profiler.stop(); _ = activeExperimentView?.throughput.drain() }
    @objc private func resume() {
        guard isVisible, !isPaused, activeExperimentView?.isAvailable == true, UIApplication.shared.applicationState == .active else { return }
        activeExperimentView?.startAnimation(); profiler.start()
    }
}

final class GPUShowcaseViewController: GPUExperimentsViewController {}
