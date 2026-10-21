import UIKit

final class EmojiParticlesViewController: UIViewController {
    private(set) var particleView: MetalEmojiParticlesView?
    private let profiler = PerformanceProfiler(cpuScope: .mainThread)
    private let canvas = UIView()
    private weak var contentScroll: UIScrollView?
    private let modeControl = UISegmentedControl(items: EmojiParticleMode.allCases.map(\.title))
    private let countSlider = UISlider()
    private let sizeControl = UISegmentedControl(items: ["16 px", "32 px", "48 px"])
    private let rateControl = UISegmentedControl(items: ["60 FPS", "120 FPS"])
    private let countLabel = MetalLabStyle.label("10 000", size: 16, weight: .medium)
    private let fps = MetalLabMetric("DISPLAY FPS")
    private let active = MetalLabMetric("ACTIVE EMOJI · ON SCREEN")
    private let gpu = MetalLabMetric("GPU FRAME · ms")
    private let cpu = MetalLabMetric("CPU · MAIN THREAD")
    private let frameStatus = MetalLabStyle.label("Сбор метрик…", size: 10)
    private let status = MetalLabStyle.label("", size: 11)
    private let pauseButton = UIButton(type: .system)
    private let burstButton = UIButton(type: .system)
    private var isVisible = false
    private var isPaused = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Emoji"
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.035, green: 0.025, blue: 0.06, alpha: 1)
        buildInterface()
        let renderer = MetalEmojiParticlesView()
        renderer.externallyDriven = true
        renderer.accessibilityLabel = "Фонтан эмодзи. Коснитесь или перетягивайте для всплеска."
        let arguments = ProcessInfo.processInfo.arguments
        if let argument = arguments.first(where: { $0.hasPrefix("--emoji-count=") }),
           let count = Int(argument.dropFirst(14)) { renderer.particleCount = count }
        if let argument = arguments.first(where: { $0.hasPrefix("--emoji-mode=") }),
           let raw = UInt32(argument.dropFirst(13)), let mode = EmojiParticleMode(rawValue: raw) { renderer.mode = mode }
        canvas.insertSubview(renderer, at: 0)
        renderer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            renderer.topAnchor.constraint(equalTo: canvas.topAnchor), renderer.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            renderer.leadingAnchor.constraint(equalTo: canvas.leadingAnchor), renderer.trailingAnchor.constraint(equalTo: canvas.trailingAnchor)
        ])
        // Give the fountain's drag priority over the compact-screen scroll view.
        contentScroll?.panGestureRecognizer.require(toFail: renderer.interactionPan)
        particleView = renderer
        profiler.measurements = renderer.measurements
        profiler.onFrame = { [weak self] time in self?.particleView?.render(time: time) }
        profiler.onSnapshot = { [weak self] in self?.show($0) }
        modeControl.selectedSegmentIndex = Int(renderer.mode.rawValue)
        countSlider.value = Float(renderer.particleCount)
        sizeControl.selectedSegmentIndex = 1
        rateControl.selectedSegmentIndex = 0
        updateCountLabel()
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        countSlider.addTarget(self, action: #selector(countChanged), for: .valueChanged)
        sizeControl.addTarget(self, action: #selector(sizeChanged), for: .valueChanged)
        rateControl.addTarget(self, action: #selector(rateChanged), for: .valueChanged)
        burstButton.addTarget(self, action: #selector(burst), for: .touchUpInside)
        pauseButton.addTarget(self, action: #selector(togglePause), for: .touchUpInside)
        NotificationCenter.default.addObserver(self, selector: #selector(suspend), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
        if !renderer.isAvailable {
            status.text = renderer.unavailabilityReason
            [modeControl, sizeControl, rateControl].forEach { $0.isEnabled = false }
            countSlider.isEnabled = false
            pauseButton.isEnabled = false
            burstButton.isEnabled = false
        }
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
        let wordmark = MetalLabStyle.label("E M O J I   /   E N G I N E", size: 11, weight: .bold)
        wordmark.textColor = .systemOrange
        let title = MetalLabStyle.label("Фонтан эмоций", size: 28, weight: .semibold)
        let subtitle = MetalLabStyle.label("GPU physics · texture atlas · instancing", size: 11)
        subtitle.textColor = MetalLabStyle.muted
        let header = MetalLabStyle.stack([wordmark, title, subtitle], spacing: 4)
        modeControl.accessibilityLabel = "Тип эмодзи"
        modeControl.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 11, weight: .medium)], for: .normal)
        modeControl.heightAnchor.constraint(equalToConstant: 36).isActive = true
        canvas.backgroundColor = UIColor(red: 0.018, green: 0.012, blue: 0.04, alpha: 1)
        canvas.layer.cornerRadius = 22
        canvas.clipsToBounds = true
        canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        canvas.setContentHuggingPriority(.defaultLow, for: .vertical)
        let top = MetalLabStyle.stack([fps, gpu], axis: .horizontal, spacing: 14)
        let bottom = MetalLabStyle.stack([cpu, active], axis: .horizontal, spacing: 14)
        top.distribution = .fillEqually
        bottom.distribution = .fillEqually
        let overlay = MetalLabStyle.stack([top, bottom], spacing: 10)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.68)
        overlay.layer.cornerRadius = 14
        overlay.isLayoutMarginsRelativeArrangement = true
        overlay.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        overlay.isUserInteractionEnabled = false
        canvas.addSubview(overlay)
        frameStatus.textAlignment = .center
        frameStatus.backgroundColor = UIColor.black.withAlphaComponent(0.68)
        frameStatus.layer.cornerRadius = 7
        frameStatus.clipsToBounds = true
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
            frameStatus.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])
        let hint = MetalLabStyle.label("Тап — всплеск. Тяните, чтобы перемещать фонтан.", size: 12)
        hint.textColor = MetalLabStyle.muted
        countLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        countLabel.textAlignment = .right
        let countRow = MetalLabStyle.stack([MetalLabStyle.label("Количество инстансов", size: 12), countLabel], axis: .horizontal)
        countSlider.minimumValue = Float(MetalEmojiParticlesView.minimumCount)
        countSlider.maximumValue = Float(MetalEmojiParticlesView.maximumCount)
        countSlider.tintColor = .systemOrange
        countSlider.accessibilityLabel = "Количество эмодзи"
        sizeControl.accessibilityLabel = "Размер эмодзи в пикселях"
        sizeControl.widthAnchor.constraint(equalToConstant: 195).isActive = true
        let sizeRow = MetalLabStyle.stack([MetalLabStyle.label("Размер", size: 12), sizeControl], axis: .horizontal)
        sizeRow.alignment = .center
        rateControl.widthAnchor.constraint(equalToConstant: 170).isActive = true
        rateControl.accessibilityLabel = "Целевой FPS эмодзи"
        let rateRow = MetalLabStyle.stack([MetalLabStyle.label("Целевая частота", size: 12), rateControl], axis: .horizontal)
        rateRow.alignment = .center
        for (button, title, icon) in [(burstButton, "Всплеск", "sparkles"), (pauseButton, "Пауза", "pause.fill")] {
            var config = UIButton.Configuration.bordered()
            config.title = title
            config.image = UIImage(systemName: icon)
            config.imagePadding = 6
            config.baseForegroundColor = .systemOrange
            button.configuration = config
        }
        let buttons = MetalLabStyle.stack([burstButton, pauseButton], axis: .horizontal, spacing: 12)
        buttons.distribution = .fillEqually
        status.textColor = MetalLabStyle.muted
        let controls = MetalLabStyle.stack([hint, countRow, countSlider, sizeRow, rateRow, buttons, status], spacing: 8)
        controls.setContentHuggingPriority(.required, for: .vertical)
        controls.setContentCompressionResistancePriority(.required, for: .vertical)
        let content = MetalLabStyle.stack([header, modeControl, canvas, controls], spacing: 12)
        let scroll = UIScrollView()
        contentScroll = scroll
        scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll)
        scroll.addSubview(content)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        let width = content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -10),
            content.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor, constant: -22),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 900), width
        ])
    }

    private func format(_ value: Int) -> String { value.formatted(.number.grouping(.automatic)).replacingOccurrences(of: ",", with: " ") }
    private func updateCountLabel() { countLabel.text = format(particleView?.particleCount ?? 0) }
    private func resetMetrics() { [fps, gpu, cpu, active].forEach { $0.show("—") } }

    private func show(_ snapshot: PerformanceSnapshot) {
        fps.show(String(format: "%.1f", snapshot.fps))
        gpu.show(snapshot.render.gpuMS.isEmpty ? "—" : String(format: "%.3f", snapshot.render.gpuMS.mean))
        cpu.show(snapshot.cpuPercent.map { String(format: "%.1f %%", $0) } ?? "—")
        active.show(snapshot.render.activeEntities.map(format) ?? "—")
        let presented = MetalAnimationView.presentationMetricsAvailable ? String(format: "%.1f", Double(snapshot.render.presentedFrames) / snapshot.duration) : "n/a"
        frameStatus.text = "1 draw · \(format(particleView?.particleCount ?? 0)) instances\n"
            + String(format: "Presented %@ · Completed %.1f FPS · %.2f ms interval", presented, snapshot.completedFPS, snapshot.frameMS)
        status.text = "\(BenchmarkRun.isSimulator ? "SIMULATOR" : "DEVICE") · \(BenchmarkRun.buildConfiguration) · CPU main · активные = в границах экрана"
        if snapshot.render.failedFrames > 0 { status.text = "Ошибок GPU: \(snapshot.render.failedFrames). Уменьшите количество или размер." }
    }

    @objc private func modeChanged() { particleView?.mode = EmojiParticleMode(rawValue: UInt32(modeControl.selectedSegmentIndex)) ?? .mixed }
    @objc private func countChanged() {
        particleView?.particleCount = Int((countSlider.value / 1000).rounded()) * 1000
        updateCountLabel()
        active.show("—")
    }
    @objc private func sizeChanged() { particleView?.spriteSizePixels = [16, 32, 48][sizeControl.selectedSegmentIndex] }
    @objc private func rateChanged() { profiler.targetFPS = rateControl.selectedSegmentIndex == 1 ? 120 : 60; profiler.reset(); resetMetrics() }
    @objc private func burst() { particleView?.updateInteraction(at: CGPoint(x: 0.5, y: 0.85), active: false) }
    @objc private func togglePause() {
        isPaused.toggle()
        pauseButton.configuration?.title = isPaused ? "Продолжить" : "Пауза"
        pauseButton.configuration?.image = UIImage(systemName: isPaused ? "play.fill" : "pause.fill")
        if isPaused { suspend(); resetMetrics(); frameStatus.text = "Пауза" } else { resume() }
    }
    @objc private func suspend() { particleView?.stopAnimation(); profiler.stop() }
    @objc private func resume() {
        guard isVisible, !isPaused, particleView?.isAvailable == true else { return }
        particleView?.startAnimation()
        profiler.start()
    }
}
