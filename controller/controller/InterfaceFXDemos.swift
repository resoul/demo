//
//  InterfaceFXDemos.swift
//  controller
//
//  Demo screens for the effects that work on top of live UI (MetalVFXEngine/InterfaceFX).
//

import UIKit

private func makeDemoHint(_ text: String, color: UIColor = .secondaryLabel) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .preferredFont(forTextStyle: .footnote)
    label.textColor = color
    label.textAlignment = .center
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

private final class DemoGradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    init(_ colors: [UIColor], start: CGPoint = CGPoint(x: 0, y: 0), end: CGPoint = CGPoint(x: 1, y: 1)) {
        super.init(frame: .zero)
        let gradient = layer as! CAGradientLayer
        gradient.colors = colors.map(\.cgColor)
        gradient.startPoint = start
        gradient.endPoint = end
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// A colorful sample card used by several demos.
private func makeSampleCard(title: String, subtitle: String, symbol: String, colors: [UIColor]) -> UIView {
    let card = UIView()
    card.backgroundColor = .secondarySystemGroupedBackground
    card.layer.cornerRadius = 24
    card.layer.cornerCurve = .continuous
    card.clipsToBounds = true
    let header = DemoGradientView(colors)
    let icon = UIImageView(image: UIImage(systemName: symbol,
                                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .bold)))
    icon.tintColor = .white
    let titleLabel = UILabel()
    titleLabel.text = title
    titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
    let subtitleLabel = UILabel()
    subtitleLabel.text = subtitle
    subtitleLabel.font = .systemFont(ofSize: 14)
    subtitleLabel.textColor = .secondaryLabel
    for subview in [header, icon, titleLabel, subtitleLabel] {
        subview.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(subview)
    }
    NSLayoutConstraint.activate([
        header.topAnchor.constraint(equalTo: card.topAnchor),
        header.leadingAnchor.constraint(equalTo: card.leadingAnchor),
        header.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        header.heightAnchor.constraint(equalTo: card.heightAnchor, multiplier: 0.6),
        icon.centerXAnchor.constraint(equalTo: header.centerXAnchor),
        icon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        titleLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
        titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
        subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
        subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
    ])
    return card
}

/// Dark demo screens also darken the navigation bar while they are visible, so the title stays legible.
class DarkDemoViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.overrideUserInterfaceStyle = .dark
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.overrideUserInterfaceStyle = .unspecified
    }
}

// MARK: - Holographic card

final class HolographicCardDemoViewController: DarkDemoViewController {
    private let card = HolographicCardView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Holographic Card"
        view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1)
        buildArtwork(in: card.contentView)
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        let hint = makeDemoHint("Tilt the phone, or press and drag on the card", color: UIColor(white: 1, alpha: 0.5))
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            card.widthAnchor.constraint(equalToConstant: 330),
            card.heightAnchor.constraint(equalToConstant: 208),
            hint.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 48),
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    /// A credit-card style artwork: dark gradient, chip, number, name and a logo.
    private func buildArtwork(in content: UIView) {
        let background = DemoGradientView([UIColor(red: 0.1, green: 0.1, blue: 0.22, alpha: 1),
                                           UIColor(red: 0.28, green: 0.12, blue: 0.4, alpha: 1),
                                           UIColor(red: 0.08, green: 0.25, blue: 0.35, alpha: 1)])
        let chip = DemoGradientView([UIColor(red: 0.95, green: 0.82, blue: 0.5, alpha: 1),
                                     UIColor(red: 0.7, green: 0.55, blue: 0.25, alpha: 1)])
        chip.layer.cornerRadius = 7
        chip.clipsToBounds = true
        let logo = UIImageView(image: UIImage(systemName: "sparkles",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)))
        logo.tintColor = .white
        let brand = UILabel()
        brand.text = "AURORA"
        brand.font = .systemFont(ofSize: 18, weight: .heavy)
        brand.textColor = .white
        let number = UILabel()
        number.text = "4716  ••••  ••••  2048"
        number.font = .monospacedDigitSystemFont(ofSize: 21, weight: .semibold)
        number.textColor = .white
        let name = UILabel()
        name.text = "ALEX MORGAN"
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.textColor = UIColor(white: 1, alpha: 0.8)
        let expiry = UILabel()
        expiry.text = "12/29"
        expiry.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        expiry.textColor = UIColor(white: 1, alpha: 0.8)
        for subview in [background, chip, logo, brand, number, name, expiry] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            brand.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            brand.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            logo.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
            logo.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            chip.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 22),
            chip.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            chip.widthAnchor.constraint(equalToConstant: 46),
            chip.heightAnchor.constraint(equalToConstant: 34),
            number.topAnchor.constraint(equalTo: chip.bottomAnchor, constant: 16),
            number.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            name.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            name.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            expiry.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            expiry.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
        ])
    }
}

// MARK: - Liquid glass lens

final class LiquidGlassDemoViewController: UIViewController {
    private let backdrop = UIView()
    private let scrollView = UIScrollView()
    private let lens = LiquidGlassLensView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Liquid Glass"
        view.backgroundColor = .systemBackground
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(scrollView)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: backdrop.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
        ])
        buildContent()

        // The lens is a sibling above the backdrop, so it refracts the UI without capturing itself.
        lens.backdropView = backdrop
        lens.bounds = CGRect(origin: .zero, size: lens.intrinsicContentSize)
        view.addSubview(lens)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if lens.center == .zero {
            lens.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        }
    }

    private func buildContent() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
        ])
        let title = UILabel()
        title.text = "Drag the glass.\nScroll under it."
        title.numberOfLines = 0
        title.font = .systemFont(ofSize: 34, weight: .heavy)
        stack.addArrangedSubview(title)

        let palettes: [[UIColor]] = [
            [.systemPink, .systemOrange], [.systemBlue, .systemTeal], [.systemPurple, .systemIndigo],
            [.systemGreen, .systemMint], [.systemYellow, .systemRed], [.systemCyan, .systemBlue],
        ]
        let symbols = ["sun.max.fill", "cloud.rain.fill", "moon.stars.fill", "leaf.fill", "flame.fill", "drop.fill"]
        for row in 0..<3 {
            let pair = UIStackView()
            pair.spacing = 12
            pair.distribution = .fillEqually
            for column in 0..<2 {
                let index = row * 2 + column
                let tile = DemoGradientView(palettes[index])
                tile.layer.cornerRadius = 20
                tile.layer.cornerCurve = .continuous
                tile.clipsToBounds = true
                let icon = UIImageView(image: UIImage(systemName: symbols[index],
                                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .bold)))
                icon.tintColor = .white
                icon.translatesAutoresizingMaskIntoConstraints = false
                tile.addSubview(icon)
                NSLayoutConstraint.activate([
                    icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
                    icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
                    tile.heightAnchor.constraint(equalToConstant: 130),
                ])
                pair.addArrangedSubview(tile)
            }
            stack.addArrangedSubview(pair)
        }
        let body = UILabel()
        body.numberOfLines = 0
        body.font = .preferredFont(forTextStyle: .body)
        body.text = String(repeating: "Glass bends light at its rounded rim and magnifies what is behind it. "
                           + "Each frame the area under the lens is snapshotted and refracted on the GPU, "
                           + "with a little chromatic dispersion and a frosted blur from mipmaps. ", count: 4)
        stack.addArrangedSubview(body)
    }
}

// MARK: - Water ripples

final class WaterRippleDemoViewController: UIViewController, UITableViewDataSource {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let water = WaterRippleOverlay()
    private let rows = ["Wi-Fi", "Bluetooth", "Airplane Mode", "Do Not Disturb", "Dark Mode", "Haptics",
                        "Low Power Mode", "Location", "Notifications", "Auto-Brightness"]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Water Ripples"
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tableView)
        let header = makeDemoHint("Touch anywhere: the controls still work under the water")
        header.frame = CGRect(x: 0, y: 0, width: 300, height: 44)
        tableView.tableHeaderView = header
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        water.attach(to: tableView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        water.detach()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = rows[indexPath.row]
        content.image = UIImage(systemName: ["wifi", "dot.radiowaves.left.and.right", "airplane", "moon.fill",
                                             "circle.lefthalf.filled", "waveform", "battery.25", "location.fill",
                                             "bell.badge.fill", "sun.max.fill"][indexPath.row])
        cell.contentConfiguration = content
        let toggle = UISwitch()
        toggle.isOn = indexPath.row % 3 == 0
        cell.accessoryView = toggle
        cell.selectionStyle = .none
        return cell
    }
}

// MARK: - Glass shatter

final class GlassShatterDemoViewController: UIViewController {
    private let animator = GlassShatterAnimator()
    private let card = makeSampleCard(title: "Fragile.png", subtitle: "Tap anywhere on it to break it",
                                      symbol: "photo.fill",
                                      colors: [.systemTeal, .systemBlue, .systemIndigo])

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Glass Shatter"
        view.backgroundColor = .systemGroupedBackground
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            card.widthAnchor.constraint(equalToConstant: 320),
            card.heightAnchor.constraint(equalToConstant: 260),
        ])
        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard card.alpha > 0 else { return }
        animator.shatter(card, at: gesture.location(in: card)) { [weak self] in
            UIView.animate(withDuration: 0.4, delay: 0.3) { self?.card.alpha = 1 }
        }
    }
}

// MARK: - Genie

final class GenieDemoViewController: UIViewController {
    private let animator = GenieAnimator()
    private let window = UIView()
    private var dockIcons: [UIButton] = []
    private var minimizedInto: UIButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Genie"
        view.backgroundColor = UIColor(red: 0.35, green: 0.45, blue: 0.75, alpha: 1)
        let wallpaper = DemoGradientView([UIColor(red: 0.98, green: 0.6, blue: 0.4, alpha: 1),
                                          UIColor(red: 0.55, green: 0.35, blue: 0.85, alpha: 1),
                                          UIColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1)],
                                         start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0.3, y: 1))
        wallpaper.frame = view.bounds
        wallpaper.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(wallpaper)
        buildWindow()
        buildDock()
    }

    private func buildWindow() {
        window.backgroundColor = .systemBackground
        window.layer.cornerRadius = 16
        window.layer.cornerCurve = .continuous
        window.clipsToBounds = true
        window.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(window)

        let titleBar = UIView()
        titleBar.backgroundColor = .secondarySystemBackground
        let dots = UIStackView(arrangedSubviews: [UIColor.systemRed, .systemYellow, .systemGreen].map { color in
            let dot = UIButton(type: .custom)
            dot.backgroundColor = color
            dot.layer.cornerRadius = 7
            dot.widthAnchor.constraint(equalToConstant: 14).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 14).isActive = true
            return dot
        })
        dots.spacing = 8
        (dots.arrangedSubviews[1] as? UIButton)?.addTarget(self, action: #selector(minimize), for: .touchUpInside)
        let titleLabel = UILabel()
        titleLabel.text = "Notes"
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        let body = UILabel()
        body.numberOfLines = 0
        body.font = .preferredFont(forTextStyle: .body)
        body.text = "Tap the yellow button to minimize this window into the dock.\n\n"
            + "Tap the icon in the dock to bring it back.\n\n• Genie bends a strip mesh in the vertex shader\n"
            + "• The bottom pours in first, the top follows"
        for subview in [titleBar, dots, titleLabel, body] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            window.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            window.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            window.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            window.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            window.heightAnchor.constraint(equalToConstant: 360),
            titleBar.topAnchor.constraint(equalTo: window.topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: 40),
            dots.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            dots.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: titleBar.centerXAnchor),
            body.topAnchor.constraint(equalTo: titleBar.bottomAnchor, constant: 18),
            body.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 18),
            body.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -18),
        ])
    }

    private func buildDock() {
        let dock = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        dock.layer.cornerRadius = 26
        dock.layer.cornerCurve = .continuous
        dock.clipsToBounds = true
        dock.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dock)
        let icons: [(String, UIColor)] = [("note.text", .systemYellow), ("folder.fill", .systemBlue),
                                          ("music.note", .systemPink), ("gearshape.fill", .systemGray)]
        dockIcons = icons.map { symbol, color in
            var configuration = UIButton.Configuration.filled()
            configuration.image = UIImage(systemName: symbol)
            configuration.baseBackgroundColor = color
            configuration.baseForegroundColor = .white
            configuration.cornerStyle = .large
            let button = UIButton(configuration: configuration)
            button.widthAnchor.constraint(equalToConstant: 52).isActive = true
            button.heightAnchor.constraint(equalToConstant: 52).isActive = true
            button.addTarget(self, action: #selector(restore(_:)), for: .touchUpInside)
            return button
        }
        let stack = UIStackView(arrangedSubviews: dockIcons)
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        dock.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            dock.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dock.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: dock.contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: dock.contentView.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: dock.contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: dock.contentView.trailingAnchor, constant: -14),
        ])
    }

    @objc private func minimize() {
        guard minimizedInto == nil, let icon = dockIcons.first else { return }
        minimizedInto = icon
        animator.minimize(window, into: icon)
    }

    @objc private func restore(_ sender: UIButton) {
        guard let icon = minimizedInto else { return }
        minimizedInto = nil
        animator.restore(window, from: icon)
    }
}

// MARK: - Paper burn

final class PaperBurnDemoViewController: DarkDemoViewController {
    private let animator = PaperBurnAnimator()
    private let letter = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Paper Burn"
        view.backgroundColor = UIColor(red: 0.12, green: 0.11, blue: 0.1, alpha: 1)
        letter.backgroundColor = UIColor(red: 0.96, green: 0.92, blue: 0.82, alpha: 1)
        letter.layer.cornerRadius = 6
        letter.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(letter)
        let text = UILabel()
        text.numberOfLines = 0
        text.font = UIFont(name: "Snell Roundhand", size: 24) ?? .italicSystemFont(ofSize: 20)
        text.textColor = UIColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 1)
        text.text = "My dear friend,\n\nShould this letter fall into the wrong hands, touch it, and it shall burn "
            + "from wherever your finger rests.\n\nYours in secrecy,\nM."
        text.translatesAutoresizingMaskIntoConstraints = false
        letter.addSubview(text)
        let hint = makeDemoHint("Tap the letter where the fire should start", color: UIColor(white: 1, alpha: 0.5))
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            letter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            letter.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            letter.widthAnchor.constraint(equalToConstant: 320),
            letter.heightAnchor.constraint(equalToConstant: 380),
            text.topAnchor.constraint(equalTo: letter.topAnchor, constant: 28),
            text.leadingAnchor.constraint(equalTo: letter.leadingAnchor, constant: 26),
            text.trailingAnchor.constraint(equalTo: letter.trailingAnchor, constant: -26),
            hint.topAnchor.constraint(equalTo: letter.bottomAnchor, constant: 24),
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
        letter.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard letter.alpha > 0 else { return }
        animator.burn(letter, from: gesture.location(in: letter)) { [weak self] in
            UIView.animate(withDuration: 0.5, delay: 0.4) { self?.letter.alpha = 1 }
        }
    }
}
