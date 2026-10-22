//
//  DynamicIslandDemos.swift
//  controller
//
//  Demo screens for the effects that live in the Dynamic Island (MetalVFXEngine/DynamicIsland).
//  The liquid is island-black, so these demos stay light.
//

import UIKit

/// Big centered hint text shared by the island demos.
private func makeHint(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.numberOfLines = 0
    label.textAlignment = .center
    label.font = .systemFont(ofSize: 17, weight: .medium)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

/// Full-screen stage without a navigation bar, so touches right under the island reach the demo.
/// A floating button at the bottom goes back.
class IslandStageViewController: UIViewController {
    let toolbar = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .systemBackground

        toolbar.axis = .horizontal
        toolbar.spacing = 12
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        addToolbarButton(title: "Back", symbol: "chevron.left") { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    func addToolbarButton(title: String, symbol: String, action: @escaping () -> Void) {
        var config = UIButton.Configuration.glass()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 6
        toolbar.addArrangedSubview(UIButton(configuration: config, primaryAction: UIAction { _ in action() }))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
}

// MARK: - Ferrofluid

final class FerrofluidDemoViewController: IslandStageViewController {
    private let ferro = FerrofluidIslandView()
    private var beat: Timer?
    private var beatStart: CFTimeInterval = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Ferrofluid"

        let hint = makeHint("Your finger is a magnet.\n\nTouch anywhere to raise spikes.\nPress right under the island and pull\nto tear off a drop, let go to send it back.")
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])

        let magnet = UILongPressGestureRecognizer(target: self, action: #selector(handleMagnet(_:)))
        magnet.minimumPressDuration = 0
        magnet.allowableMovement = .greatestFiniteMagnitude
        magnet.cancelsTouchesInView = false
        view.addGestureRecognizer(magnet)

        addToolbarButton(title: "Beat", symbol: "music.note") { [weak self] in self?.toggleBeat() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let window = view.window {
            ferro.install(in: window)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        beat?.invalidate()
        beat = nil
        ferro.removeFromSuperview()
    }

    @objc private func handleMagnet(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            ferro.magnet(at: gesture.location(in: nil), pressed: true)
        default:
            ferro.magnet(at: nil, pressed: false)
        }
    }

    /// Speaker mode: a synthetic 120 BPM kick drives `pulse`, as an audio level would.
    private func toggleBeat() {
        if let beat {
            beat.invalidate()
            self.beat = nil
            ferro.pulse = 0
            return
        }
        beatStart = CACurrentMediaTime()
        beat = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = CACurrentMediaTime() - self.beatStart
                let kick = exp(-fmod(t, 0.5) * 9)
                let offbeat = exp(-fmod(t + 0.25, 0.5) * 14) * 0.35
                self.ferro.pulse = CGFloat(max(kick, offbeat))
            }
        }
    }
}

// MARK: - Liquid toast

final class LiquidToastDemoViewController: UITableViewController {
    private let samples: [(title: String, message: String, symbol: String)] = [
        ("New message", "Anna: are we still on for tonight?", "message.fill"),
        ("Download complete", "Metal by Example.pdf · 12 MB", "arrow.down.circle.fill"),
        ("AirPods Pro", "Connected · 87%", "airpodspro"),
        ("Payment failed", "Tap to update your card", "exclamationmark.triangle.fill"),
        ("Timer", "Pasta is ready", "timer"),
    ]

    init() {
        super.init(style: .insetGrouped)
        title = "Liquid Toast"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Tap a row. Drag the toast down to stretch it, tap it to squash it, flick it up to send it home."
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        samples.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let sample = samples[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = sample.title
        content.secondaryText = sample.message
        content.image = UIImage(systemName: sample.symbol)
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let window = view.window else { return }
        let sample = samples[indexPath.row]
        LiquidIslandToast.show(in: window, title: sample.title, message: sample.message, symbol: sample.symbol)
    }
}

// MARK: - Sand vacuum

final class SandVacuumDemoViewController: UITableViewController {
    private let animator = SandVacuumAnimator()
    private var items: [(title: String, symbol: String, color: UIColor)] = [
        ("Old screenshots", "photo.fill", .systemOrange), ("Spam", "envelope.badge.fill", .systemRed),
        ("Downloads", "arrow.down.circle.fill", .systemBlue), ("Cache", "internaldrive.fill", .systemGray),
        ("Duplicates", "square.on.square", .systemPurple), ("Logs", "doc.text.fill", .systemGreen),
        ("Temp files", "clock.fill", .systemTeal), ("Big videos", "video.fill", .systemPink),
        ("Archives", "archivebox.fill", .systemBrown), ("Trash", "trash.fill", .systemIndigo),
    ]

    init() {
        super.init(style: .insetGrouped)
        title = "Sand Vacuum"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Tap a row: it crumbles to sand and the island vacuums it up."
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = items[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.secondaryText = "\(Int.random(in: 12...980)) MB"
        content.image = UIImage(systemName: item.symbol)
        content.imageProperties.tintColor = item.color
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)   // don't snapshot the highlight
        animator.deleteRow(at: indexPath, in: tableView) {
            items.remove(at: indexPath.row)
        }
    }
}

// MARK: - Sand hourglass

final class SandHourglassDemoViewController: IslandStageViewController {
    private let hourglass = SandHourglassView()
    private let basin = UIView()
    private let result = UILabel()
    private var loader: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Hourglass"

        basin.backgroundColor = .secondarySystemBackground
        basin.layer.cornerRadius = 28
        basin.layer.cornerCurve = .continuous
        basin.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(basin)

        result.text = "Loaded ✓"
        result.font = .systemFont(ofSize: 28, weight: .bold)
        result.textAlignment = .center
        result.alpha = 0
        result.translatesAutoresizingMaskIntoConstraints = false
        basin.addSubview(result)

        NSLayoutConstraint.activate([
            basin.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            basin.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            basin.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 260),
            basin.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -24),
            result.centerXAnchor.constraint(equalTo: basin.centerXAnchor),
            result.centerYAnchor.constraint(equalTo: basin.centerYAnchor),
        ])

        addToolbarButton(title: "Load", symbol: "hourglass") { [weak self] in self?.startLoading() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startLoading()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        loader?.invalidate()
        hourglass.detach()
    }

    /// Fake download: progress creeps up in uneven steps for ~5 s, then the sand vanishes.
    private func startLoading() {
        loader?.invalidate()
        hourglass.detach()
        result.alpha = 0
        hourglass.progress = 0
        hourglass.attach(to: basin)
        hourglass.onFinish = { [weak self] in
            UIView.animate(withDuration: 0.35) { self?.result.alpha = 1 }
        }
        var progress: CGFloat = 0
        loader = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                progress = min(1, progress + .random(in: 0.02...0.08))
                self.hourglass.progress = progress
                if progress >= 1 {
                    timer.invalidate()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.hourglass.finish() }
                }
            }
        }
    }
}

// MARK: - Ink well

final class InkWellDemoViewController: IslandStageViewController {
    private let ink = InkWellOverlay()
    private let canvas = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Ink Well"

        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(canvas, at: 0)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: view.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let hint = makeHint("Draw with your finger.\nPause, and the island drinks the ink back.\n\n“Pour” floods the screen with ink\nand reveals the next one.")
        canvas.addSubview(hint)
        let colors: [UIColor] = [.systemPink, .systemOrange, .systemTeal, .systemIndigo]
        let swatches = UIStackView(arrangedSubviews: colors.map { color in
            let swatch = UIView()
            swatch.backgroundColor = color
            swatch.layer.cornerRadius = 18
            swatch.layer.cornerCurve = .continuous
            swatch.heightAnchor.constraint(equalToConstant: 72).isActive = true
            return swatch
        })
        swatches.axis = .horizontal
        swatches.spacing = 12
        swatches.distribution = .fillEqually
        swatches.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(swatches)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: canvas.centerYAnchor, constant: -40),
            swatches.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 24),
            swatches.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -24),
            swatches.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 40),
        ])

        addToolbarButton(title: "Pour", symbol: "drop.fill") { [weak self] in self?.pour() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ink.attach(to: canvas)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ink.detach()
    }

    private func pour() {
        guard let window = view.window, let navigationController else { return }
        InkWellOverlay.transition(in: window) {
            navigationController.pushViewController(InkDestinationViewController(), animated: false)
        }
    }
}

/// The screen the ink reveals.
private final class InkDestinationViewController: IslandStageViewController {
    private let gradient = CAGradientLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Fresh Page"
        gradient.colors = [UIColor.systemIndigo.cgColor, UIColor.systemPink.cgColor, UIColor.systemOrange.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(gradient, at: 0)

        let title = UILabel()
        title.text = "Fresh page"
        title.font = .systemFont(ofSize: 44, weight: .heavy)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient.frame = view.bounds
    }
}
