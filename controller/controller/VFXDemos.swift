//
//  VFXDemos.swift
//  controller
//
//  Demo screens for MetalVFXEngine, opened from the "VFX" button on the first screen.
//

import UIKit

final class VFXDemoMenuViewController: UITableViewController {
    private typealias Demo = (title: String, symbol: String, make: () -> UIViewController)

    private let sections: [(title: String, demos: [Demo])] = [
        ("Dynamic Island", [
            ("Liquid Pull-to-Refresh", "drop.fill", { LiquidRefreshDemoViewController() }),
            ("Black Hole", "circle.dashed", { BlackHoleDemoViewController() }),
            ("Ferrofluid", "atom", { FerrofluidDemoViewController() }),
            ("Liquid Toast", "capsule.portrait.fill", { LiquidToastDemoViewController() }),
            ("Sand Vacuum", "aqi.medium", { SandVacuumDemoViewController() }),
            ("Sand Hourglass", "hourglass", { SandHourglassDemoViewController() }),
            ("Ink Well", "paintbrush.pointed.fill", { InkWellDemoViewController() }),
            ("Undo Drop", "arrow.uturn.backward.circle.fill", { UndoDropDemoViewController() }),
            ("Add to Cart", "cart.fill", { PocketDemoViewController() }),
            ("Quick Reply", "arrowshape.turn.up.left.fill", { QuickReplyDemoViewController() }),
            ("Gooey Menu", "circle.grid.cross.fill", { GooeyMenuDemoViewController() }),
            ("Notification Beads", "circle.dotted.and.circle", { BeadStackDemoViewController() }),
            ("Coach Marks", "hand.point.up.left.fill", { CoachMarksDemoViewController() }),
            ("Jelly Scroll", "scroll.fill", { JellyScrollDemoViewController() }),
            ("Orbit Loader", "moon.stars.fill", { OrbitLoaderDemoViewController() }),
            ("Live Progress", "chart.bar.fill", { LiveProgressDemoViewController() }),
            ("Island Eyes", "eyes", { IslandEyesDemoViewController() }),
            ("Island Search", "magnifyingglass", { PullSearchDemoViewController() }),
            ("Typing…", "ellipsis.bubble.fill", { TypingDemoViewController() }),
            ("Confetti", "party.popper.fill", { ConfettiDemoViewController() }),
            ("Minimize to Island", "pip.enter", { MiniPlayerDemoViewController() }),
        ]),
        ("Liquid UI", [
            ("Liquid Switch", "switch.2", { LiquidSwitchDemoViewController() }),
            ("Slide to Pay", "creditcard.fill", { SlideToPayDemoViewController() }),
            ("Liquid Slider", "slider.horizontal.3", { LiquidSliderDemoViewController() }),
            ("Odometer Stepper", "plusminus.circle.fill", { OdometerStepperDemoViewController() }),
            ("Clay Buttons", "hand.tap.fill", { ClayButtonsDemoViewController() }),
            ("Magnetic Buttons", "dot.circle.and.hand.point.up.left.fill", { MagneticButtonsDemoViewController() }),
            ("Like Burst", "heart.fill", { LikeDemoViewController() }),
            ("PIN Drops", "circle.grid.3x3.fill", { PinDropsDemoViewController() }),
            ("Ink Password", "key.fill", { InkPasswordDemoViewController() }),
            ("Theme Reveal", "circle.lefthalf.filled", { ThemeRevealDemoViewController() }),
            ("Tilt Skeletons", "rectangle.stack.fill", { SkeletonDemoViewController() }),
            ("Kinetic Type", "textformat.size", { KineticTypeDemoViewController() }),
        ]),
        ("Channel", [
            ("Telegram Post", "bubble.left.and.text.bubble.right.fill", { ChannelFeedDemoViewController() }),
        ]),
        ("Social", [
            ("Timeline · X-style", "text.bubble.fill", { TimelineDemoViewController() }),
            ("Photo Feed · Instagram-style", "camera.fill", { PhotoFeedDemoViewController() }),
        ]),
        ("Effects", [
            ("Matrix Digital Rain", "chevron.left.forwardslash.chevron.right", { MatrixRainDemoViewController() }),
            ("Fluid Mesh Gradient", "paintpalette.fill", { FluidGradientDemoViewController() }),
            ("Particle Morph", "circle.hexagongrid.fill", { ParticleMorphDemoViewController() }),
            ("Particle Charts", "chart.pie.fill", { ParticleChartsDemoViewController() }),
        ]),
        ("On top of live UI", [
            ("Holographic Card", "creditcard.fill", { HolographicCardDemoViewController() }),
            ("Liquid Glass Lens", "capsule.fill", { LiquidGlassDemoViewController() }),
            ("Water Ripples", "water.waves", { WaterRippleDemoViewController() }),
            ("Glass Shatter", "burst.fill", { GlassShatterDemoViewController() }),
            ("Genie", "dock.arrow.down.rectangle", { GenieDemoViewController() }),
            ("Paper Burn", "flame.fill", { PaperBurnDemoViewController() }),
        ]),
    ]

    init() {
        super.init(style: .insetGrouped)
        title = "Metal VFX"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].demos.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let demo = sections[indexPath.section].demos[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = demo.title
        content.image = UIImage(systemName: demo.symbol)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(sections[indexPath.section].demos[indexPath.row].make(), animated: true)
    }
}

// MARK: - Liquid pull-to-refresh

final class LiquidRefreshDemoViewController: UITableViewController {
    private let refresh = DynamicIslandRefreshControl()
    private var items = (1...30).map { "Message \($0)" }
    private var newCount = 0

    init() {
        super.init(style: .plain)
        title = "Pull Down"
        // The liquid is island-black, so this demo stays light.
        overrideUserInterfaceStyle = .light
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        refresh.onRefresh = { [weak self] in
            // Pretend to load for a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let self else { return }
                self.newCount += 1
                self.items.insert("New message \(self.newCount)", at: 0)
                self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .top)
                self.refresh.endRefreshing()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refresh.attach(to: tableView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refresh.detach()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = items[indexPath.row]
        content.secondaryText = "Pull down: the drop comes out of the Dynamic Island"
        cell.contentConfiguration = content
        return cell
    }
}

// MARK: - Black hole

final class BlackHoleDemoViewController: UITableViewController {
    private let animator = GravityBlackHoleAnimator()
    private var items = (1...12).map { "Card \($0)" }
    private let card = UILabel()

    init() {
        super.init(style: .insetGrouped)
        title = "Black Hole"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        setUpCard()
    }

    /// A floating card: fling it up toward the island to swallow it.
    private func setUpCard() {
        card.text = "Fling me up ↑"
        card.textAlignment = .center
        card.font = .preferredFont(forTextStyle: .headline)
        card.textColor = .white
        card.backgroundColor = .systemIndigo
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        card.isUserInteractionEnabled = true
        card.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleCardPan(_:))))
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            card.widthAnchor.constraint(equalToConstant: 220),
            card.heightAnchor.constraint(equalToConstant: 120),
        ])
    }

    @objc private func handleCardPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .changed:
            card.transform = CGAffineTransform(translationX: translation.x, y: translation.y)
        case .ended, .cancelled:
            if gesture.velocity(in: view).y < -600 || translation.y < -200 {
                animator.swallow(card) { [weak self] in
                    guard let self else { return }
                    self.card.transform = .identity
                    UIView.animate(withDuration: 0.3, delay: 0.3) { self.card.alpha = 1 }
                }
            } else {
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
                    self.card.transform = .identity
                }
            }
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = items[indexPath.row]
        content.secondaryText = "Tap or swipe to delete into the island"
        content.image = UIImage(systemName: "sparkles")
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        swallowRow(at: indexPath)
    }

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Swallow") { [weak self] _, _, done in
            self?.swallowRow(at: indexPath)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func swallowRow(at indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)   // don't snapshot the highlight
        animator.deleteRow(at: indexPath, in: tableView) {
            items.remove(at: indexPath.row)
        }
    }
}

// MARK: - Matrix rain

final class MatrixRainDemoViewController: UIViewController {
    private let rain = MatrixDigitalRainView()

    override func loadView() {
        view = rain
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tap to Pause"
        rain.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(togglePause)))
    }

    @objc private func togglePause() {
        rain.isPaused.toggle()
    }
}

// MARK: - Fluid gradient

final class FluidGradientDemoViewController: UIViewController {
    private let gradient = FluidMeshGradientView()

    override func loadView() {
        view = gradient
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tilt the Phone"
        let hint = UILabel()
        hint.text = "No motion sensor? Drag to tilt."
        hint.font = .preferredFont(forTextStyle: .footnote)
        hint.textColor = UIColor.white.withAlphaComponent(0.8)
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }
}
