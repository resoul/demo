//
//  DynamicIslandComponentDemos.swift
//  controller
//
//  Demo screens for the Dynamic Island UI components built on IslandFluidView: undo drop, pocket,
//  quick reply, gooey menu, notification beads, coach marks, jelly scroll, orbit loader,
//  live progress and island eyes. The liquid is island-black, so these demos stay light.
//

import UIKit

/// A rounded card with a symbol, a title and a subtitle.
private func makeCard(symbol: String, title: String, subtitle: String, color: UIColor) -> UIView {
    let card = UIView()
    card.backgroundColor = .secondarySystemBackground
    card.layer.cornerRadius = 20
    card.layer.cornerCurve = .continuous
    let icon = UIImageView(image: UIImage(systemName: symbol))
    icon.tintColor = color
    icon.contentMode = .scaleAspectFit
    icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)
    let titleLabel = UILabel()
    titleLabel.text = title
    titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
    let subtitleLabel = UILabel()
    subtitleLabel.text = subtitle
    subtitleLabel.font = .systemFont(ofSize: 14)
    subtitleLabel.textColor = .secondaryLabel
    let stack = UIStackView(arrangedSubviews: [icon, titleLabel, subtitleLabel])
    stack.axis = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    stack.setCustomSpacing(14, after: icon)
    stack.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
        stack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),
        stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
        stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -14),
    ])
    return card
}

private func makeLabel(_ text: String, style: UIFont.TextStyle = .body, color: UIColor = .secondaryLabel) -> UILabel {
    let label = UILabel()
    label.text = text
    label.numberOfLines = 0
    label.textAlignment = .center
    label.font = .preferredFont(forTextStyle: style)
    label.textColor = color
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

// MARK: - Undo drop

final class UndoDropDemoViewController: UITableViewController {
    private let animator = GravityBlackHoleAnimator()
    private var items = ["Weekly report.pdf", "Vacation photos", "Draft: Q4 plan", "Invoice #2041",
                         "Meeting notes", "Old backups", "Screenshot 12", "Podcast episode"]

    init() {
        super.init(style: .insetGrouped)
        title = "Undo Drop"
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
        "Tap a row to delete it into the island. The drop's neck is the timer: tap the drop before it tears to undo."
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = items[indexPath.row]
        content.image = UIImage(systemName: "doc.fill")
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard let window = view.window else { return }
        let removed = items[indexPath.row]
        animator.deleteRow(at: indexPath, in: tableView) {
            items.remove(at: indexPath.row)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            IslandUndoDrop.show(in: window, duration: 5, onUndo: {
                guard let self else { return }
                let row = min(indexPath.row, self.items.count)
                self.items.insert(removed, at: row)
                self.tableView.insertRows(at: [IndexPath(row: row, section: 0)], with: .top)
            })
        }
    }
}

// MARK: - Pocket

final class PocketDemoViewController: UIViewController {
    private let pocket = IslandPocket()
    private let products: [(symbol: String, name: String, price: String, color: UIColor)] = [
        ("headphones", "Studio Headphones", "$249", .systemIndigo), ("camera.fill", "Instant Camera", "$119", .systemPink),
        ("applewatch", "Sport Watch", "$399", .systemOrange), ("gamecontroller.fill", "Controller", "$69", .systemTeal),
        ("keyboard.fill", "Keyboard", "$149", .systemPurple), ("hifispeaker.fill", "Speaker", "$99", .systemGreen),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Add to Cart"
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Clear", primaryAction: UIAction { [weak self] _ in
            self?.pocket.empty()
        })

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(grid)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            grid.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            grid.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
        ])
        grid.addArrangedSubview(makeLabel("Tap “Add”: the card flies into the island.\nTap the swollen island to see the cart.",
                                          style: .footnote))
        for pair in stride(from: 0, to: products.count, by: 2) {
            let row = UIStackView()
            row.spacing = 12
            row.distribution = .fillEqually
            for product in products[pair..<min(pair + 2, products.count)] {
                let card = makeCard(symbol: product.symbol, title: product.name, subtitle: product.price, color: product.color)
                card.heightAnchor.constraint(equalToConstant: 170).isActive = true
                var config = UIButton.Configuration.filled()
                config.title = "Add"
                config.image = UIImage(systemName: "plus")
                config.imagePadding = 4
                config.cornerStyle = .capsule
                config.buttonSize = .small
                let button = UIButton(configuration: config, primaryAction: UIAction { [weak self, weak card] _ in
                    guard let card else { return }
                    self?.pocket.add(card)
                })
                button.translatesAutoresizingMaskIntoConstraints = false
                card.addSubview(button)
                NSLayoutConstraint.activate([
                    button.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
                    button.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
                ])
                row.addArrangedSubview(card)
            }
            grid.addArrangedSubview(row)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let window = view.window {
            pocket.install(in: window)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pocket.removeFromSuperview()
    }
}

// MARK: - Quick reply

final class QuickReplyDemoViewController: UITableViewController {
    private let senders: [(name: String, message: String)] = [
        ("Anna", "Are we still on for tonight?"), ("Max", "Can you send me the deck?"),
        ("Mom", "Call me when you land ❤️"), ("Team", "Standup moved to 10:30"),
    ]
    private var replies: [String] = []

    init() {
        super.init(style: .insetGrouped)
        title = "Quick Reply"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Incoming" : "Sent replies"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "Tap a message, then tap the toast: it flows into a reply field. Send shoots it back into the island." : nil
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? senders.count : replies.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            content.text = senders[indexPath.row].name
            content.secondaryText = senders[indexPath.row].message
            content.image = UIImage(systemName: "message.fill")
        } else {
            content.text = replies[indexPath.row]
            content.image = UIImage(systemName: "arrowshape.turn.up.left.fill")
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0, let window = view.window else { return }
        let sender = senders[indexPath.row]
        LiquidIslandToast.show(in: window, title: sender.name, message: sender.message, symbol: "message.fill",
                               onReply: { [weak self] text in
            guard let self else { return }
            self.replies.insert("To \(sender.name): \(text)", at: 0)
            self.tableView.insertRows(at: [IndexPath(row: 0, section: 1)], with: .top)
        })
    }
}

// MARK: - Gooey menu

final class GooeyMenuDemoViewController: IslandStageViewController {
    private lazy var menu = IslandGooeyMenu(items: [
        .init(symbol: "camera.fill", title: "Camera") { [weak self] in self?.picked("Camera") },
        .init(symbol: "doc.viewfinder", title: "Scan") { [weak self] in self?.picked("Scan") },
        .init(symbol: "square.and.pencil", title: "Note") { [weak self] in self?.picked("Note") },
        .init(symbol: "mic.fill", title: "Voice memo") { [weak self] in self?.picked("Voice memo") },
        .init(symbol: "square.and.arrow.up", title: "Share") { [weak self] in self?.picked("Share") },
    ])
    private let result = makeLabel("Press and hold anywhere.\nSlide onto a bubble and let go.", style: .title3)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Gooey Menu"
        view.addSubview(result)
        NSLayoutConstraint.activate([
            result.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            result.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 60),
            result.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0.25
        press.allowableMovement = .greatestFiniteMagnitude
        view.addGestureRecognizer(press)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let window = view.window {
            menu.install(in: window)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        menu.removeFromSuperview()
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: nil)
        switch gesture.state {
        case .began:
            menu.begin(at: point)
        case .changed:
            menu.move(to: point)
        default:
            menu.end()
        }
    }

    private func picked(_ title: String) {
        result.text = "Picked: \(title)"
        result.textColor = .label
    }
}

// MARK: - Notification beads

final class BeadStackDemoViewController: IslandStageViewController {
    private let beads = IslandBeadStack()
    private let samples: [(title: String, message: String, symbol: String)] = [
        ("Anna", "Are we still on for tonight?", "message.fill"), ("Calendar", "Design review in 10 min", "calendar"),
        ("Bank", "Card payment: $12.40", "creditcard.fill"), ("Delivery", "Your order is out for delivery", "shippingbox.fill"),
        ("Weather", "Rain starting in 15 min", "cloud.rain.fill"), ("Max", "Sent you a photo", "photo.fill"),
        ("Fitness", "Ring closed! 🎉", "figure.run"),
    ]
    private var sampleIndex = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Notification Beads"
        let hint = makeLabel("New notifications string up under the island.\nTap the string to read them, swipe up to string them back.",
                             style: .callout)
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 120),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
        addToolbarButton(title: "Notify", symbol: "bell.fill") { [weak self] in self?.notify() }
        addToolbarButton(title: "Clear", symbol: "xmark") { [weak self] in self?.beads.clear() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let window = view.window else { return }
        beads.install(in: window)
        for delay in [0.2, 0.6, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.notify() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        beads.removeFromSuperview()
    }

    private func notify() {
        let sample = samples[sampleIndex % samples.count]
        sampleIndex += 1
        beads.push(title: sample.title, message: sample.message, symbol: sample.symbol)
    }
}

// MARK: - Coach marks

final class CoachMarksDemoViewController: UIViewController {
    private let tour = IslandCoachMarks()
    private let search = UISearchBar()
    private let filter = UIButton(configuration: .tinted())
    private let compose = UIButton(configuration: .filled())
    private let avatar = UIImageView(image: UIImage(systemName: "person.crop.circle.fill"))

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Coach Marks"
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Start tour", primaryAction: UIAction { [weak self] _ in
            self?.startTour()
        })

        search.placeholder = "Search notes"
        search.searchBarStyle = .minimal
        filter.configuration?.image = UIImage(systemName: "line.3.horizontal.decrease")
        filter.configuration?.title = "Filter"
        filter.configuration?.imagePadding = 6
        compose.configuration?.image = UIImage(systemName: "square.and.pencil")
        compose.configuration?.cornerStyle = .capsule
        compose.configuration?.buttonSize = .large
        avatar.tintColor = .systemIndigo
        avatar.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44)

        let header = UIStackView(arrangedSubviews: [search, filter])
        header.spacing = 8
        header.alignment = .center
        let notes = UIStackView(arrangedSubviews: (1...3).map { index in
            makeCard(symbol: "note.text", title: "Note \(index)", subtitle: "Edited today", color: .systemYellow)
        })
        notes.axis = .vertical
        notes.spacing = 10
        notes.arrangedSubviews.forEach { $0.heightAnchor.constraint(equalToConstant: 96).isActive = true }
        for view in [header, notes, compose, avatar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(view)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 8),
            header.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            notes.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            notes.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            notes.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            avatar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            avatar.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -20),
            compose.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            compose.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -20),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.startTour() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        tour.removeFromSuperview()
    }

    private func startTour() {
        guard let window = view.window, tour.superview == nil else { return }
        tour.start([
            .init(target: search, text: "Search across every note — even text inside photos."),
            .init(target: filter, text: "Filter by tag, date or who you shared it with."),
            .init(target: compose, text: "Start a new note. Long-press for a checklist."),
            .init(target: avatar, text: "Your profile and sync settings live here."),
        ], in: window)
    }
}

// MARK: - Jelly scroll

final class JellyScrollDemoViewController: UITableViewController {
    private let jelly = IslandScrollJelly()

    init() {
        super.init(style: .plain)
        title = "Jelly Scroll"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        jelly.attach(to: tableView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        jelly.detach()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        80
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = "Row \(indexPath.row + 1)"
        content.secondaryText = indexPath.row == 0
            ? "Fling, pull down past the top, or tap the status bar"
            : "The island wobbles with the scroll"
        cell.contentConfiguration = content
        return cell
    }

    override func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        jelly.pulse()
        return true
    }
}

// MARK: - Orbit loader

final class OrbitLoaderDemoViewController: UITableViewController {
    private let loader = IslandOrbitLoader()
    private var stories = (1...12).map { "Story \($0)" }
    private var batch = 0

    init() {
        super.init(style: .insetGrouped)
        title = "Orbit Loader"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"), primaryAction: UIAction { [weak self] _ in self?.reload() })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let window = view.window {
            loader.install(in: window)
        }
        reload()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        loader.stop()
        loader.removeFromSuperview()
    }

    /// Fake network call: the moons orbit for ~3 s.
    private func reload() {
        guard !loader.isLoading else { return }
        loader.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.loader.stop()
            self.batch += 1
            self.stories.insert("Fresh story \(self.batch)", at: 0)
            self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .top)
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Tap ↻ to load: moons orbit the island and melt into it on close passes."
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        stories.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = stories[indexPath.row]
        content.image = UIImage(systemName: "newspaper.fill")
        cell.contentConfiguration = content
        return cell
    }
}

// MARK: - Live progress

final class LiveProgressDemoViewController: IslandStageViewController {
    private let live = IslandLiveProgress()
    private var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Live Progress"
        let hint = makeLabel("The island stretches into a Live Activity\nwith a tube of liquid that fills and sloshes.",
                             style: .callout)
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
        addToolbarButton(title: "Download", symbol: "arrow.down.circle") { [weak self] in self?.download() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let window = view.window {
            live.install(in: window)
        }
        download()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        live.removeFromSuperview()
    }

    /// Fake download: progress arrives in uneven chunks, so the liquid sloshes.
    private func download() {
        timer?.invalidate()
        live.progress = 0
        live.show(symbol: "arrow.down.circle.fill")
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.live.progress += .random(in: 0.03...0.16)
                if self.live.progress >= 1 {
                    timer.invalidate()
                    self.live.complete()
                }
            }
        }
    }
}

// MARK: - Island eyes

final class IslandEyesDemoViewController: IslandStageViewController, UITextFieldDelegate {
    private let eyes = IslandEyes()
    private let email = UITextField()
    private let password = UITextField()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Island Eyes"
        let heading = makeLabel("Sign in", style: .largeTitle, color: .label)
        heading.font = .systemFont(ofSize: 34, weight: .bold)
        let hint = makeLabel("Hint: the password is “metal”.", style: .footnote)
        for (field, placeholder) in [(email, "Email"), (password, "Password")] {
            field.placeholder = placeholder
            field.borderStyle = .roundedRect
            field.font = .systemFont(ofSize: 17)
            field.delegate = self
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.heightAnchor.constraint(equalToConstant: 48).isActive = true
            field.addTarget(self, action: #selector(textChanged(_:)), for: .editingChanged)
        }
        email.keyboardType = .emailAddress
        password.isSecureTextEntry = true
        var config = UIButton.Configuration.filled()
        config.title = "Sign in"
        config.cornerStyle = .large
        config.buttonSize = .large
        let signIn = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.signIn() })

        let form = UIStackView(arrangedSubviews: [heading, email, password, signIn, hint])
        form.axis = .vertical
        form.spacing = 14
        form.setCustomSpacing(28, after: heading)
        form.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(form)
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            form.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            form.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 90),
        ])

        // The eyes follow any finger on the screen.
        let watch = UILongPressGestureRecognizer(target: self, action: #selector(watchFinger(_:)))
        watch.minimumPressDuration = 0
        watch.cancelsTouchesInView = false
        view.addGestureRecognizer(watch)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let window = view.window else { return }
        eyes.install(in: window)
        eyes.show()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        eyes.removeFromSuperview()
    }

    @objc private func watchFinger(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            eyes.look(at: gesture.location(in: nil))
        default:
            lookAtCaret()
        }
    }

    @objc private func textChanged(_ field: UITextField) {
        lookAtCaret()
    }

    /// While typing the email, the eyes read along with the caret.
    private func lookAtCaret() {
        guard email.isFirstResponder, let end = email.selectedTextRange?.end else {
            eyes.look(at: nil)
            return
        }
        let caret = email.caretRect(for: end)
        eyes.look(at: email.convert(CGPoint(x: caret.midX, y: caret.midY), to: nil))
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        eyes.cover(textField === password)
        lookAtCaret()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField === password {
            eyes.cover(false)
        }
    }

    private func signIn() {
        view.endEditing(true)
        if password.text == "metal" {
            eyes.approve()
        } else {
            eyes.disapprove()
        }
    }
}

// MARK: - Pull-down search

final class PullSearchDemoViewController: UITableViewController {
    private let search = IslandPullSearch()
    private let all = ["Anna Petrova", "Apple Music", "Archive", "Barcelona trip", "Battery", "Bluetooth",
                       "Calendar", "Camera", "Coffee notes", "Design review", "Downloads", "Dynamic Island",
                       "Fitness", "Flights", "Focus", "Gym plan", "Invoices", "Keynote", "Maps", "Max Ivanov",
                       "Metal shaders", "Notes", "Passwords", "Photos", "Podcasts", "Recipes", "Reminders",
                       "Settings", "Shortcuts", "Swift", "Tickets", "Wallet", "Weather", "Wi-Fi"]
    private var shown: [String] = []

    init() {
        super.init(style: .insetGrouped)
        title = "Island Search"
        shown = all
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.keyboardDismissMode = .onDrag
        search.placeholder = "Search everything"
        search.onQueryChange = { [weak self] query in
            guard let self else { return }
            self.shown = query.isEmpty ? self.all : self.all.filter { $0.localizedCaseInsensitiveContains(query) }
            self.tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        search.attach(to: tableView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        search.detach()
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Pull down: search flows out of the island"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        shown.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = shown[indexPath.row]
        content.image = UIImage(systemName: "magnifyingglass.circle.fill")
        cell.contentConfiguration = content
        return cell
    }
}

// MARK: - Typing indicator

final class TypingDemoViewController: UITableViewController {
    private let typing = IslandTypingIndicator()
    private var messages: [(text: String, mine: Bool)] = [
        ("Hey! Did you see the new island effects?", true),
        ("Not yet, send me a video", false),
        ("Recording one now", true),
    ]
    private let replies = ["Wow, the toast is so smooth 😍", "How does the ink one work?", "Ship it!",
                           "Can it do confetti too?", "My phone looks alive now"]
    private var replyIndex = 0

    init() {
        super.init(style: .plain)
        title = "Typing…"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.separatorStyle = .none
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.bubble.fill"), primaryAction: UIAction { [weak self] _ in self?.simulate() })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let window = view.window {
            typing.install(in: window)
        }
        simulate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        typing.removeFromSuperview()
    }

    /// Anna types for a bit, then the message boils over into a toast and lands in the chat.
    private func simulate() {
        guard !typing.isTyping else { return }
        typing.startTyping()
        let text = replies[replyIndex % replies.count]
        replyIndex += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self else { return }
            self.typing.deliver(title: "Anna", message: text, symbol: "message.fill")
            self.messages.append((text, false))
            self.tableView.insertRows(at: [IndexPath(row: self.messages.count - 1, section: 0)], with: .bottom)
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let message = messages[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = message.text
        content.textProperties.alignment = message.mine ? .natural : .natural
        content.secondaryText = message.mine ? "You" : "Anna"
        content.image = UIImage(systemName: message.mine ? "person.circle.fill" : "person.crop.circle")
        content.imageProperties.tintColor = message.mine ? .systemBlue : .systemPink
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }
}

// MARK: - Confetti

final class ConfettiDemoViewController: IslandStageViewController {
    private let status = makeLabel("Tap Pay: the island celebrates.\nOn an HDR screen the sparks glow brighter than white.",
                                   style: .callout)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Confetti"
        let amount = makeLabel("$49.00", style: .largeTitle, color: .label)
        amount.font = .systemFont(ofSize: 56, weight: .heavy)
        var config = UIButton.Configuration.filled()
        config.title = "Pay with Face ID"
        config.image = UIImage(systemName: "faceid")
        config.imagePadding = 8
        config.cornerStyle = .capsule
        config.buttonSize = .large
        let pay = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.pay() })
        let stack = UIStackView(arrangedSubviews: [amount, pay, status])
        stack.axis = .vertical
        stack.spacing = 24
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 40),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
        addToolbarButton(title: "Again", symbol: "sparkles") { [weak self] in self?.pay() }
    }

    private func pay() {
        guard let window = view.window else { return }
        IslandConfetti.burst(in: window)
        status.text = "Payment complete 🎉"
        status.textColor = .label
    }
}

// MARK: - Minimize to island

final class MiniPlayerDemoViewController: IslandStageViewController {
    private let player = IslandMiniPlayer()
    private let card = UIView()
    private lazy var artwork: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { context in
            let colors = [UIColor.systemPink.cgColor, UIColor.systemIndigo.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 240, y: 240), options: [])
            let note = UIImage(systemName: "music.note", withConfiguration: UIImage.SymbolConfiguration(pointSize: 90, weight: .bold))?
                .withTintColor(.white.withAlphaComponent(0.9), renderingMode: .alwaysOriginal)
            note?.draw(at: CGPoint(x: 120 - (note?.size.width ?? 0) / 2, y: 120 - (note?.size.height ?? 0) / 2))
        }
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Minimize to Island"
        view.backgroundColor = .systemGroupedBackground
        buildCard()
        let hint = makeLabel("Flick the player up: it drains into the island.\nTap the island to pour it back.", style: .footnote)
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 20),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
        addToolbarButton(title: "Minimize", symbol: "arrow.up.to.line") { [weak self] in self?.minimize() }
        player.onRestore = { [weak self] in self?.card.transform = .identity }
    }

    private func buildCard() {
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 28
        card.layer.cornerCurve = .continuous
        let art = UIImageView(image: artwork)
        art.layer.cornerRadius = 20
        art.layer.cornerCurve = .continuous
        art.clipsToBounds = true
        art.translatesAutoresizingMaskIntoConstraints = false
        art.heightAnchor.constraint(equalTo: art.widthAnchor).isActive = true
        let title = makeLabel("Liquid Dreams", style: .title2, color: .label)
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let artist = makeLabel("The Metal Shaders", style: .body)
        let progress = UIProgressView(progressViewStyle: .default)
        progress.progress = 0.38
        progress.tintColor = .systemPink
        let controls = UIStackView(arrangedSubviews: ["backward.fill", "pause.fill", "forward.fill"].map { name in
            let button = UIImageView(image: UIImage(systemName: name))
            button.tintColor = .label
            button.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: name == "pause.fill" ? 34 : 24)
            return button
        })
        controls.distribution = .equalSpacing
        controls.alignment = .center
        let stack = UIStackView(arrangedSubviews: [art, title, artist, progress, controls])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(18, after: art)
        stack.setCustomSpacing(22, after: progress)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            card.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            controls.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.7),
        ])
        card.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let window = view.window {
            player.install(in: window)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player.removeFromSuperview()
        card.alpha = 1
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let t = gesture.translation(in: view)
        switch gesture.state {
        case .changed:
            // Follows the finger up, shrinking a little; resists going down.
            let lift = min(t.y, 0) + max(t.y, 0) * 0.2
            let shrink = 1 + max(lift, -300) / 1200
            card.transform = CGAffineTransform(translationX: 0, y: lift).scaledBy(x: shrink, y: shrink)
        case .ended, .cancelled:
            if gesture.velocity(in: view).y < -500 || t.y < -140 {
                minimize()
            } else {
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
                    self.card.transform = .identity
                }
            }
        default:
            break
        }
    }

    private func minimize() {
        guard card.alpha > 0 else { return }
        player.minimize(card, artwork: artwork)
    }
}
