//
//  LiquidUIDemos.swift
//  controller
//
//  Demo screens for the Liquid UI controls (MetalVFXEngine/LiquidUI), opened from the
//  "Liquid UI" section of the VFX menu.
//

import UIKit

/// A scrolling page with a centered vertical stack of demo rows.
class LiquidUIDemoPage: UIViewController {
    let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = false   // so horizontal drags inside the controls are not taken by the page
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 28
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24),
        ])
    }

    func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        return label
    }

    /// Stretches `view` to the stack's width.
    func addFullWidth(_ view: UIView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

// MARK: - Liquid switch

final class LiquidSwitchDemoViewController: LiquidUIDemoPage {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Liquid Switch"
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 0
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 6, left: 18, bottom: 6, right: 18)
        let rows: [(String, String, UIColor, Bool)] = [
            ("Wi-Fi", "wifi", .systemBlue, true), ("Bluetooth", "dot.radiowaves.left.and.right", .systemBlue, false),
            ("Airplane Mode", "airplane", .systemOrange, false), ("Focus", "moon.fill", .systemIndigo, true),
            ("Low Power", "battery.25", .systemYellow, false),
        ]
        for (title, symbol, tint, on) in rows {
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = tint
            icon.contentMode = .scaleAspectFit
            icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
            let label = UILabel()
            label.text = title
            let toggle = LiquidSwitch()
            toggle.onTint = tint == .systemYellow ? .systemGreen : tint
            toggle.setOn(on, animated: false)
            toggle.setContentHuggingPriority(.required, for: .horizontal)
            let row = UIStackView(arrangedSubviews: [icon, label, toggle])
            row.spacing = 14
            row.alignment = .center
            row.heightAnchor.constraint(equalToConstant: 58).isActive = true
            card.addArrangedSubview(row)
        }
        addFullWidth(card)
        stack.addArrangedSubview(caption("The knob is a drop: it stretches across, snaps off and the track floods with color."))
    }
}

// MARK: - Slide to pay

final class SlideToPayDemoViewController: LiquidUIDemoPage {
    private let slider = SlideToPayView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Slide to Pay"
        let amount = UILabel()
        amount.text = "$129.00"
        amount.font = .systemFont(ofSize: 54, weight: .heavy)
        let merchant = caption("Metal Coffee Roasters · Visa •• 4242")
        stack.addArrangedSubview(amount)
        stack.addArrangedSubview(merchant)
        slider.title = "Slide to pay"
        slider.heightAnchor.constraint(equalToConstant: 64).isActive = true
        addFullWidth(slider)
        stack.setCustomSpacing(60, after: merchant)
        var config = UIButton.Configuration.gray()
        config.title = "Reset"
        config.cornerStyle = .capsule
        stack.addArrangedSubview(UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.slider.reset()
        }))
    }
}

// MARK: - Liquid slider

final class LiquidSliderDemoViewController: LiquidUIDemoPage {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Liquid Slider"
        for (name, low, high, color, value) in [("Volume", "speaker.fill", "speaker.wave.3.fill", UIColor.systemBlue, 0.45),
                                                ("Brightness", "sun.min.fill", "sun.max.fill", UIColor.systemOrange, 0.7)] {
            let label = UILabel()
            label.text = name
            label.font = .systemFont(ofSize: 15, weight: .semibold)
            label.textColor = .secondaryLabel
            let slider = LiquidSlider()
            slider.liquidColor = color
            slider.setValue(value, animated: false)
            let lowIcon = UIImageView(image: UIImage(systemName: low))
            let highIcon = UIImageView(image: UIImage(systemName: high))
            for icon in [lowIcon, highIcon] {
                icon.tintColor = .secondaryLabel
                icon.setContentHuggingPriority(.required, for: .horizontal)
            }
            let row = UIStackView(arrangedSubviews: [lowIcon, slider, highIcon])
            row.spacing = 14
            row.alignment = .center
            let block = UIStackView(arrangedSubviews: [label, row])
            block.axis = .vertical
            block.spacing = 10
            addFullWidth(block)
        }
        stack.addArrangedSubview(caption("Yank it to make the liquid slosh. Drag past either end: it stretches like jelly."))
    }
}

// MARK: - Odometer stepper

final class OdometerStepperDemoViewController: LiquidUIDemoPage {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Odometer Stepper"
        for (name, value, range) in [("Guests", 2, 1...12), ("Score (watch the carry)", 97, 0...120)] {
            let label = UILabel()
            label.text = name
            label.font = .systemFont(ofSize: 15, weight: .semibold)
            label.textColor = .secondaryLabel
            stack.addArrangedSubview(label)
            let stepper = OdometerStepper(value: value, range: range)
            stack.addArrangedSubview(stepper)
            stack.setCustomSpacing(12, after: label)
        }
        stack.addArrangedSubview(caption("Digits roll like an odometer with motion blur. At a limit it shakes and the number bounces."))
    }
}

// MARK: - Clay buttons

final class ClayButtonsDemoViewController: LiquidUIDemoPage {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Clay Buttons"
        view.backgroundColor = UIColor(red: 0.95, green: 0.93, blue: 0.90, alpha: 1)
        overrideUserInterfaceStyle = .light
        let buttons: [(String, String, UIColor)] = [
            ("Continue", "arrow.right", UIColor(red: 0.98, green: 0.78, blue: 0.68, alpha: 1)),
            ("Play", "play.fill", UIColor(red: 0.70, green: 0.86, blue: 0.80, alpha: 1)),
            ("Add to bag", "bag.fill", UIColor(red: 0.78, green: 0.78, blue: 0.96, alpha: 1)),
            ("Share", "square.and.arrow.up", UIColor(red: 0.98, green: 0.90, blue: 0.64, alpha: 1)),
        ]
        for (title, symbol, color) in buttons {
            let button = ClayButton(title: title, symbol: symbol, color: color)
            button.heightAnchor.constraint(equalToConstant: 64).isActive = true
            addFullWidth(button)
        }
        stack.addArrangedSubview(caption("Press and slide your finger: the dent follows it. The light stays put as you tilt the phone."))
    }
}

// MARK: - Magnetic buttons

final class MagneticButtonsDemoViewController: LiquidUIDemoPage {
    override func loadView() {
        view = MagneticField()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Magnetic Buttons"
        let items: [(String, String, UIColor)] = [
            ("Photos", "photo.fill", .systemPink), ("Music", "music.note", .systemRed), ("Maps", "map.fill", .systemGreen),
            ("Mail", "envelope.fill", .systemBlue), ("Notes", "note.text", .systemOrange), ("Wallet", "wallet.pass.fill", .systemIndigo),
        ]
        for pair in stride(from: 0, to: items.count, by: 3) {
            let row = UIStackView()
            row.spacing = 22
            row.distribution = .fillEqually
            for (title, symbol, color) in items[pair..<pair + 3] {
                let button = MagneticButton(title: title, symbol: symbol, color: color)
                button.heightAnchor.constraint(equalTo: button.widthAnchor).isActive = true
                row.addArrangedSubview(button)
            }
            addFullWidth(row)
        }
        stack.addArrangedSubview(caption("Drag a finger around: buttons lean toward it and a glare follows it across their surface."))
    }
}

// MARK: - Like

final class LikeDemoViewController: LiquidUIDemoPage {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Like Burst"
        let photo = UIView()
        photo.backgroundColor = .systemTeal
        photo.layer.cornerRadius = 24
        photo.layer.cornerCurve = .continuous
        let gradient = CAGradientLayer()
        gradient.colors = [UIColor.systemTeal.cgColor, UIColor.systemIndigo.cgColor]
        gradient.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        photo.layer.insertSublayer(gradient, at: 0)
        photo.clipsToBounds = true
        photo.heightAnchor.constraint(equalToConstant: 260).isActive = true
        addFullWidth(photo)
        let like = LikeButton()
        stack.addArrangedSubview(like)
        stack.addArrangedSubview(caption("Tap the heart: it fills with liquid and bursts into sparks. Tap again to drain it."))
    }
}

// MARK: - PIN drops

final class PinDropsDemoViewController: LiquidUIDemoPage {
    private let pin = PinDropsView(length: 4)
    private var entered = ""
    private let code = "1234"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "PIN Drops"
        stack.addArrangedSubview(caption("Enter 1234. Any other code is rejected."))
        stack.addArrangedSubview(pin)
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 14
        for row in stride(from: 0, to: keys.count, by: 3) {
            let line = UIStackView()
            line.spacing = 22
            line.distribution = .fillEqually
            for key in keys[row..<row + 3] {
                var config = UIButton.Configuration.gray()
                config.title = key
                config.cornerStyle = .capsule
                config.attributedTitle = AttributedString(key, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 28, weight: .medium)]))
                let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.press(key) })
                button.isHidden = key.isEmpty
                button.widthAnchor.constraint(equalToConstant: 76).isActive = true
                button.heightAnchor.constraint(equalToConstant: 76).isActive = true
                line.addArrangedSubview(button)
            }
            grid.addArrangedSubview(line)
        }
        stack.addArrangedSubview(grid)
    }

    private func press(_ key: String) {
        if key == "⌫" {
            guard !entered.isEmpty else { return }
            entered.removeLast()
            pin.deleteLast()
            return
        }
        guard entered.count < code.count else { return }
        entered += key
        pin.append()
        guard entered.count == code.count else { return }
        let correct = entered == code
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            if correct {
                self.pin.accept()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.pin.reset() }
            } else {
                self.pin.reject()
            }
            self.entered = ""
        }
    }
}

// MARK: - Ink password

final class InkPasswordDemoViewController: LiquidUIDemoPage {
    private let field = InkPasswordField()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Ink Password"
        let heading = UILabel()
        heading.text = "Create account"
        heading.font = .systemFont(ofSize: 30, weight: .bold)
        stack.addArrangedSubview(heading)
        field.heightAnchor.constraint(equalToConstant: 56).isActive = true
        addFullWidth(field)
        var config = UIButton.Configuration.filled()
        config.title = "Create"
        config.cornerStyle = .capsule
        config.buttonSize = .large
        let create = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.submit() })
        addFullWidth(create)
        stack.addArrangedSubview(caption("The field fills with liquid as the password gets stronger. Create with a weak one and ink bleeds out of it."))
    }

    private func submit() {
        if field.strength < 0.6 {
            field.rejectInk()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } else {
            field.approveRipple()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - Theme reveal

final class ThemeRevealDemoViewController: LiquidUIDemoPage {
    private let toggle = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Theme Reveal"
        let cards: [(String, String, UIColor)] = [("Morning run", "figure.run", .systemOrange),
                                                  ("Deep work", "laptopcomputer", .systemBlue),
                                                  ("Evening read", "book.fill", .systemPurple)]
        for (title, symbol, color) in cards {
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = color
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
            icon.contentMode = .scaleAspectFit
            icon.setContentHuggingPriority(.required, for: .horizontal)
            icon.widthAnchor.constraint(equalToConstant: 34).isActive = true
            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: 19, weight: .semibold)
            let row = UIStackView(arrangedSubviews: [icon, label])
            row.spacing = 16
            row.isLayoutMarginsRelativeArrangement = true
            row.layoutMargins = UIEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
            row.backgroundColor = .secondarySystemGroupedBackground
            row.layer.cornerRadius = 22
            addFullWidth(row)
        }
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.buttonSize = .large
        toggle.configuration = config
        toggle.addAction(UIAction { [weak self] _ in self?.flip() }, for: .touchUpInside)
        updateToggle()
        stack.addArrangedSubview(toggle)
        stack.addArrangedSubview(caption("The new theme floods in from the button like liquid."))
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.window?.overrideUserInterfaceStyle = .unspecified
    }

    private var isDark: Bool {
        (view.window?.traitCollection.userInterfaceStyle ?? traitCollection.userInterfaceStyle) == .dark
    }

    private func updateToggle() {
        toggle.configuration?.title = isDark ? "Day" : "Night"
        toggle.configuration?.image = UIImage(systemName: isDark ? "sun.max.fill" : "moon.fill")
        toggle.configuration?.imagePadding = 8
    }

    private func flip() {
        guard let window = view.window else { return }
        let point = toggle.convert(CGPoint(x: toggle.bounds.midX, y: toggle.bounds.midY), to: window)
        let dark = !isDark
        LiquidThemeReveal.transition(in: window, from: point, apply: {
            window.overrideUserInterfaceStyle = dark ? .dark : .light
        }, completion: { [weak self] in self?.updateToggle() })
    }
}

// MARK: - Tilt skeletons

final class SkeletonDemoViewController: LiquidUIDemoPage {
    private let shimmer = SkeletonShimmerView()
    private var placeholders: [(UIView, CGFloat)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tilt Skeletons"
        for _ in 0..<4 {
            let card = UIView()
            card.heightAnchor.constraint(equalToConstant: 104).isActive = true
            let avatar = UIView(), line1 = UIView(), line2 = UIView(), line3 = UIView()
            for (view, radius) in [(avatar, CGFloat(26)), (line1, 7), (line2, 7), (line3, 7)] {
                view.translatesAutoresizingMaskIntoConstraints = false
                card.addSubview(view)
                placeholders.append((view, radius))
            }
            NSLayoutConstraint.activate([
                avatar.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                avatar.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                avatar.widthAnchor.constraint(equalToConstant: 52),
                avatar.heightAnchor.constraint(equalToConstant: 52),
                line1.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 16),
                line1.topAnchor.constraint(equalTo: avatar.topAnchor, constant: 4),
                line1.widthAnchor.constraint(equalTo: card.widthAnchor, multiplier: 0.45),
                line1.heightAnchor.constraint(equalToConstant: 14),
                line2.leadingAnchor.constraint(equalTo: line1.leadingAnchor),
                line2.topAnchor.constraint(equalTo: line1.bottomAnchor, constant: 12),
                line2.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                line2.heightAnchor.constraint(equalToConstant: 14),
                line3.leadingAnchor.constraint(equalTo: line1.leadingAnchor),
                line3.topAnchor.constraint(equalTo: line2.bottomAnchor, constant: 10),
                line3.widthAnchor.constraint(equalTo: card.widthAnchor, multiplier: 0.6),
                line3.heightAnchor.constraint(equalToConstant: 14),
            ])
            addFullWidth(card)
        }
        stack.addArrangedSubview(caption("No running shimmer: the highlight sits where the light falls and slides as you tilt the phone."))
        view.addSubview(shimmer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        shimmer.frame = view.bounds
        shimmer.blocks = placeholders.map { ($0.0.convert($0.0.bounds, to: shimmer), $0.1) }
    }
}

// MARK: - Kinetic type

final class KineticTypeDemoViewController: LiquidUIDemoPage {
    private let headline = KineticTextView()
    private let lines = ["Liquid UI", "Metal shaders", "Feel the type", "Hold to breathe", "Hello, iOS 27"]
    private var index = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Kinetic Type"
        headline.heightAnchor.constraint(equalToConstant: 120).isActive = true
        addFullWidth(headline)
        var config = UIButton.Configuration.filled()
        config.title = "Next headline"
        config.cornerStyle = .capsule
        stack.addArrangedSubview(UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.showNext() }))
        stack.addArrangedSubview(caption("New text fills its letters with liquid; the old one crumbles away. Press and hold the headline: it breathes."))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if headline.text.isEmpty {
            headline.setText(lines[0])
        }
    }

    private func showNext() {
        index = (index + 1) % lines.count
        headline.setText(lines[index])
    }
}
