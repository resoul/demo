//
//  TelegramTrickDemos.swift
//  controller
//
//  Telegram tricks, one screen each (VFX menu → "Telegram · приёмы"):
//  1. Profile avatar that sinks into the Dynamic Island as you scroll.
//  2. A collectible gift: shake the box open, a pattern bursts out, the card catches the light.
//  3. Pull up at the end of a channel to go on to the next one.
//  4. Pull down the chat list to reveal the archive.
//  5. Message effects: hold Send, pick an effect, the message lands with a burst.
//  6. A round video message: hold to record into a circle, tap it to play big.
//  7. Swipe a message to reply: a drop stretches out of the bubble and snaps into the reply arrow.
//

import UIKit

// MARK: - 1. Avatar into the Dynamic Island

/// The black liquid joining the avatar to the island: `progress` 0 (avatar in the header) … 1 (inside).
private final class AvatarIslandLiquid: IslandFluidView {
    func update(avatarCenter: CGPoint, avatarRadius: CGFloat, progress p: CGFloat) {
        let cover = islandSmoothstep(0.7, 0.98, p)
        var newShapes: [IslandFluidShape] = []
        var newSpikes: [IslandFluidSpike] = []
        if cover > 0.01 {
            newShapes.append(.circle(center: avatarCenter, radius: avatarRadius * (0.35 + 0.65 * cover) * min(1, cover * 3),
                                     blend: 16))
        }
        let neck = islandSmoothstep(0.55, 0.85, p)
        if neck > 0.01, p < 0.999 {
            newSpikes.append(IslandFluidSpike(base: CGPoint(x: islandMouth.x, y: islandMouth.y - 4), tip: avatarCenter,
                                              baseRadius: 6 + 8 * neck, tipRadius: avatarRadius * 0.5 * neck, blend: 12))
        }
        shapes = newShapes
        spikes = newSpikes
        renderFrame()
    }
}

final class ProfileIslandDemoViewController: TrickPage, UIScrollViewDelegate {
    private let person = trickPeople[0]
    private let scroll = UIScrollView()
    private let avatar = UIImageView()
    private let darken = UIView()
    private let liquid = AvatarIslandLiquid()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let titleLabel = UILabel()
    private let avatarSize: CGFloat = 110
    private let headerHeight: CGFloat = 250

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.alwaysBounceVertical = true
        scroll.delegate = self
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
        let header = UIView()
        header.heightAnchor.constraint(equalToConstant: headerHeight).isActive = true
        nameLabel.text = person.name
        nameLabel.font = .systemFont(ofSize: 26, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        statusLabel.text = "в сети"
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = TrickPalette.telegramBlue
        statusLabel.textAlignment = .center
        for label in [nameLabel, statusLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(label)
        }
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: avatarSize + 26),
            nameLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            statusLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
        ])
        stack.addArrangedSubview(header)
        let actions = UIStackView(arrangedSubviews: [("message.fill", "Чат"), ("phone.fill", "Звонок"), ("video.fill", "Видео"),
                                                     ("bell.slash.fill", "Звук")].map { symbol, title in
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: symbol)
            config.title = title
            config.imagePlacement = .top
            config.imagePadding = 4
            config.baseBackgroundColor = TrickPalette.telegramPanel
            config.baseForegroundColor = TrickPalette.telegramBlue
            config.cornerStyle = .large
            return UIButton(configuration: config)
        })
        actions.distribution = .fillEqually
        actions.spacing = 8
        actions.isLayoutMarginsRelativeArrangement = true
        actions.layoutMargins = UIEdgeInsets(top: 0, left: 14, bottom: 16, right: 14)
        stack.addArrangedSubview(actions)
        let infos = [("+7 912 345-67-89", "Мобильный"), ("@anna_motion", "Имя пользователя"),
                     ("Дизайнер интерфейсов. Люблю пружины и шейдеры.", "О себе"), ("12 марта", "День рождения")]
        for (value, caption) in infos + infos.map({ ($0.0, $0.1 + " · ещё") }) {
            let row = UIStackView()
            row.axis = .vertical
            row.spacing = 2
            row.isLayoutMarginsRelativeArrangement = true
            row.layoutMargins = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
            let v = UILabel()
            v.text = value
            v.textColor = .white
            v.font = .systemFont(ofSize: 17)
            v.numberOfLines = 0
            let c = UILabel()
            c.text = caption
            c.textColor = TrickPalette.secondary
            c.font = .systemFont(ofSize: 14)
            row.addArrangedSubview(v)
            row.addArrangedSubview(c)
            stack.addArrangedSubview(row)
        }
        avatar.image = ChannelAvatar.image(for: person, size: 220)
        avatar.clipsToBounds = true
        darken.backgroundColor = .black
        darken.alpha = 0
        avatar.addSubview(darken)
        titleLabel.text = person.name
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alpha = 0
        navigationItem.titleView = titleLabel
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let window = view.window else { return }
        window.addSubview(avatar)
        liquid.install(in: window)
        update()
        showHint("Прокрутите вверх — аватар уйдёт в Dynamic Island")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        avatar.removeFromSuperview()
        liquid.removeFromSuperview()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        update()
    }

    private func update() {
        guard let window = view.window else { return }
        let offset = scroll.contentOffset.y + scroll.adjustedContentInset.top
        let island = DynamicIslandGeometry.frame(in: window)
        let start = view.convert(CGPoint(x: view.bounds.midX, y: scroll.adjustedContentInset.top + 8 + avatarSize / 2), to: window)
        // Pulling down grows the avatar a little; scrolling up sends it into the island.
        if offset < 0 {
            let s = 1 + min(-offset / 300, 0.25)
            avatar.bounds = CGRect(x: 0, y: 0, width: avatarSize * s, height: avatarSize * s)
            avatar.center = CGPoint(x: start.x, y: start.y - offset * 0.5)
            avatar.layer.cornerRadius = avatarSize * s / 2
            avatar.alpha = 1
            darken.alpha = 0
            darken.frame = avatar.bounds
            liquid.update(avatarCenter: avatar.center, avatarRadius: 0, progress: 0)
            return
        }
        // The avatar rides up with the content and shrinks on the way; it is fully in when it reaches the island.
        let target = CGPoint(x: island.midX, y: island.midY)
        let travel = max(start.y - target.y, 1)
        let p = min(max(offset / travel, 0), 1)
        let size = avatarSize + (island.height - avatarSize) * p
        let center = CGPoint(x: start.x + (target.x - start.x) * p, y: max(start.y - offset, target.y))
        avatar.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        avatar.center = center
        avatar.layer.cornerRadius = size / 2
        darken.frame = avatar.bounds
        darken.alpha = islandSmoothstep(0.55, 0.95, p)
        avatar.alpha = 1 - islandSmoothstep(0.9, 1, p)
        liquid.update(avatarCenter: center, avatarRadius: size / 2, progress: p)
        let headerFade = 1 - islandSmoothstep(0.1, 0.5, p)
        nameLabel.alpha = headerFade
        statusLabel.alpha = headerFade
        titleLabel.alpha = islandSmoothstep(0.7, 1, p)
        if p >= 1, titleLabel.tag == 0 {
            titleLabel.tag = 1
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } else if p < 0.9 {
            titleLabel.tag = 0
        }
    }
}

// MARK: - 2. Collectible gift

final class CollectibleGiftDemoViewController: TrickPage {
    private let box = UILabel()
    private let card = UIView()
    private let backdrop = CAGradientLayer()
    private let pattern = UIView()
    private let model = UILabel()
    private let sheen = CAGradientLayer()
    private let giftTitle = UILabel()
    private let rarity = UILabel()
    private var taps = 0
    private var link: CADisplayLink?
    private var opened = false
    private var sparkTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Подарок"
        box.text = "🎁"
        box.font = .systemFont(ofSize: 130)
        box.sizeToFit()
        box.isUserInteractionEnabled = true
        box.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapBox)))
        view.addSubview(box)

        card.layer.cornerRadius = 34
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        card.alpha = 0
        backdrop.type = .radial
        backdrop.colors = [UIColor(red: 0.98, green: 0.66, blue: 0.35, alpha: 1).cgColor,
                           UIColor(red: 0.62, green: 0.2, blue: 0.42, alpha: 1).cgColor,
                           UIColor(red: 0.2, green: 0.06, blue: 0.2, alpha: 1).cgColor]
        backdrop.locations = [0, 0.55, 1]
        backdrop.startPoint = CGPoint(x: 0.5, y: 0.4)
        backdrop.endPoint = CGPoint(x: 1.1, y: 1.1)
        card.layer.addSublayer(backdrop)
        card.addSubview(pattern)
        model.text = "🧸"
        model.font = .systemFont(ofSize: 120)
        model.sizeToFit()
        model.layer.shadowColor = UIColor(red: 1, green: 0.8, blue: 0.4, alpha: 1).cgColor
        model.layer.shadowRadius = 24
        model.layer.shadowOpacity = 0.8
        model.layer.shadowOffset = .zero
        card.addSubview(model)
        giftTitle.text = "Плюшевый мишка #4 128"
        giftTitle.font = .systemFont(ofSize: 22, weight: .bold)
        giftTitle.textColor = .white
        giftTitle.textAlignment = .center
        card.addSubview(giftTitle)
        rarity.text = "  ✦ Редкость 0,4%  "
        rarity.font = .systemFont(ofSize: 14, weight: .semibold)
        rarity.textColor = UIColor(red: 1, green: 0.9, blue: 0.6, alpha: 1)
        rarity.backgroundColor = UIColor(white: 0, alpha: 0.3)
        rarity.layer.cornerRadius = 14
        rarity.clipsToBounds = true
        rarity.textAlignment = .center
        card.addSubview(rarity)
        sheen.colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.35).cgColor,
                        UIColor(red: 0.7, green: 0.9, blue: 1, alpha: 0.2).cgColor, UIColor(white: 1, alpha: 0).cgColor]
        sheen.locations = [0.35, 0.47, 0.53, 0.65]
        sheen.startPoint = CGPoint(x: 0, y: 0)
        sheen.endPoint = CGPoint(x: 1, y: 1)
        card.layer.addSublayer(sheen)
        view.addSubview(card)

        var config = UIButton.Configuration.filled()
        config.title = "Ещё раз"
        config.cornerStyle = .capsule
        config.baseBackgroundColor = TrickPalette.telegramPanel
        let again = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.reset() })
        again.tag = 77
        again.alpha = 0
        view.addSubview(again)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width - 48
        card.bounds = CGRect(x: 0, y: 0, width: width, height: width * 1.25)
        card.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY - 10)
        if !opened {
            box.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = card.bounds
        sheen.frame = card.bounds.insetBy(dx: -card.bounds.width, dy: -card.bounds.height)
        CATransaction.commit()
        pattern.bounds = CGRect(x: 0, y: 0, width: width * 1.6, height: width * 1.6)
        pattern.center = CGPoint(x: card.bounds.midX, y: card.bounds.height * 0.4)
        if pattern.subviews.isEmpty {
            buildPattern(radius: width * 0.8)
        }
        model.center = CGPoint(x: card.bounds.midX, y: card.bounds.height * 0.4)
        giftTitle.frame = CGRect(x: 16, y: card.bounds.height * 0.72, width: card.bounds.width - 32, height: 28)
        rarity.sizeToFit()
        rarity.bounds.size = CGSize(width: rarity.bounds.width, height: 28)
        rarity.center = CGPoint(x: card.bounds.midX, y: giftTitle.frame.maxY + 26)
        view.viewWithTag(77)?.frame = CGRect(x: view.bounds.midX - 70, y: card.frame.maxY + 24, width: 140, height: 44)
    }

    /// Rings of little symbols around the model, like the pattern of a collectible gift.
    private func buildPattern(radius: CGFloat) {
        let center = CGPoint(x: pattern.bounds.midX, y: pattern.bounds.midY)
        for ring in 0..<4 {
            let r = radius * (0.32 + CGFloat(ring) * 0.2)
            let count = 8 + ring * 4
            for i in 0..<count {
                let icon = UIImageView(image: UIImage(systemName: ring % 2 == 0 ? "star.fill" : "heart.fill"))
                icon.tintColor = UIColor(white: 1, alpha: 0.22 - CGFloat(ring) * 0.03)
                let s = 14 + CGFloat(3 - ring) * 2
                icon.bounds = CGRect(x: 0, y: 0, width: s, height: s)
                let a = CGFloat(i) / CGFloat(count) * .pi * 2 + CGFloat(ring) * 0.3
                icon.center = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
                icon.transform = CGAffineTransform(rotationAngle: a)
                pattern.addSubview(icon)
            }
        }
    }

    @objc private func tapBox() {
        guard !opened else { return }
        taps += 1
        let strength = CGFloat(taps)
        UIImpactFeedbackGenerator(style: taps < 3 ? .medium : .heavy).impactOccurred()
        let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        shake.values = [0, -0.12 * strength, 0.12 * strength, -0.08 * strength, 0.05 * strength, 0]
        shake.duration = 0.45
        box.layer.add(shake, forKey: "shake")
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.6) {
            self.box.transform = CGAffineTransform(scaleX: 1 + strength * 0.08, y: 1 + strength * 0.08)
        }
        if taps >= 3 {
            open()
        }
    }

    private func open() {
        opened = true
        guard let window = view.window else { return }
        let center = box.convert(CGPoint(x: box.bounds.midX, y: box.bounds.midY), to: window)
        IslandConfetti.burst(in: window, from: center, direction: -.pi / 2, spread: 2 * .pi, particles: 600, sparkShare: 0.5,
                             sparkColor: TrickPalette.gold, speedScale: 0.75)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIView.animate(withDuration: 0.25) {
            self.box.transform = CGAffineTransform(scaleX: 1.6, y: 1.6)
            self.box.alpha = 0
        }
        // The card opens out; the pattern bursts from the middle and keeps turning.
        card.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        pattern.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        model.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        UIView.animate(withDuration: 0.7, delay: 0.1, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.4) {
            self.card.alpha = 1
            self.card.transform = .identity
        }
        UIView.animate(withDuration: 1.1, delay: 0.25, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.2) {
            self.pattern.transform = .identity
        }
        UIView.animate(withDuration: 0.8, delay: 0.35, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.6) {
            self.model.transform = .identity
        }
        UIView.animate(withDuration: 0.4, delay: 1.2) { self.view.viewWithTag(77)?.alpha = 1 }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.byValue = CGFloat.pi * 2
        spin.duration = 60
        spin.repeatCount = .infinity
        pattern.layer.add(spin, forKey: "spin")
        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        bob.fromValue = -6
        bob.toValue = 6
        bob.duration = 1.8
        bob.autoreverses = true
        bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        model.layer.add(bob, forKey: "bob")
        startTilt()
        // Every now and then the rarity badge throws off golden sparks.
        sparkTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.view.window else { return }
                let point = self.rarity.convert(CGPoint(x: self.rarity.bounds.midX, y: self.rarity.bounds.midY), to: window)
                IslandConfetti.burst(in: window, from: point, direction: -.pi / 2, spread: 2 * .pi, particles: 40, sparkShare: 1,
                                     sparkColor: TrickPalette.gold, speedScale: 0.2)
            }
        }
    }

    /// The card turns a little with the phone and the sheen slides across it.
    private func startTilt() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        let g = LiquidUIMotion.shared.gravity
        var transform = CATransform3DIdentity
        transform.m34 = -1 / 900
        transform = CATransform3DRotate(transform, g.x * 0.35, 0, 1, 0)
        transform = CATransform3DRotate(transform, -(g.y - 0.85) * 0.5, 1, 0, 0)
        card.layer.transform = transform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sheen.transform = CATransform3DMakeTranslation(g.x * card.bounds.width * 0.9, (g.y - 0.85) * card.bounds.height, 0)
        CATransaction.commit()
    }

    private func reset() {
        link?.invalidate()
        sparkTimer?.invalidate()
        opened = false
        taps = 0
        pattern.layer.removeAllAnimations()
        model.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.3) {
            self.card.alpha = 0
            self.view.viewWithTag(77)?.alpha = 0
        }
        box.alpha = 1
        box.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        UIView.animate(withDuration: 0.5, delay: 0.1, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
            self.box.transform = .identity
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showHint("Нажмите на подарок три раза")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        link?.invalidate()
        sparkTimer?.invalidate()
    }
}

// MARK: - 3. Next channel

final class NextChannelDemoViewController: TrickPage, UIScrollViewDelegate {
    private let channels = [("VFX Daily", trickPeople[1]), ("Motion Lab", trickPeople[2]), ("Metal Notes", trickPeople[3]),
                            ("UI Kitchen", trickPeople[4])]
    private var current = 0
    private let scroll = UIScrollView()
    private var stack = UIStackView()
    private let indicator = UIView()
    private let ring = CAShapeLayer()
    private let track = CAShapeLayer()
    private let nextAvatar = UIImageView()
    private let nextLabel = UILabel()
    private var armed = false
    private let threshold: CGFloat = 110

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.alwaysBounceVertical = true
        scroll.delegate = self
        view.addSubview(scroll)
        indicator.isUserInteractionEnabled = false
        for layer in [track, ring] {
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = 3
            layer.lineCap = .round
            indicator.layer.addSublayer(layer)
        }
        track.strokeColor = UIColor(white: 1, alpha: 0.15).cgColor
        ring.strokeColor = TrickPalette.telegramBlue.cgColor
        ring.strokeEnd = 0
        indicator.addSubview(nextAvatar)
        nextLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nextLabel.textColor = TrickPalette.secondary
        nextLabel.textAlignment = .center
        indicator.addSubview(nextLabel)
        view.addSubview(indicator)
        load(channel: 0)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToBottom()
        showHint("Долистайте до конца и потяните вверх", bottom: 170)
    }

    private func makeStack(for index: Int) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        let texts = ["Добро пожаловать в «\(channels[index].0)»!", "Сегодня разбираем пружинные анимации 🌀",
                     "Главное — не длительность, а затухание.", "Вот пример с Dynamic Island 👆",
                     "Чем мягче пружина, тем «дороже» интерфейс.", "Завтра — стекло и Metal ✨",
                     "Вопросы пишите в комментарии 💬", "Спасибо, что читаете!"]
        for (i, text) in texts.enumerated() {
            stack.addArrangedSubview(TrickViews.row(TrickViews.bubble(text, outgoing: false, width: 300), outgoing: i % 5 == 4))
        }
        return stack
    }

    private func load(channel index: Int) {
        current = index
        let (name, person) = channels[index]
        navigationItem.title = name
        let next = channels[(index + 1) % channels.count]
        nextAvatar.image = ChannelAvatar.image(for: next.1, size: 44)
        nextLabel.text = "Следующий: \(next.0) · 12 непрочитанных"
        _ = person
        stack.removeFromSuperview()
        stack = makeStack(for: index)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
    }

    private func scrollToBottom() {
        view.layoutIfNeeded()
        let y = max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
        scroll.setContentOffset(CGPoint(x: 0, y: y), animated: false)
    }

    private var overscroll: CGFloat {
        let bottom = max(scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height,
                         -scroll.adjustedContentInset.top)
        return scroll.contentOffset.y - bottom
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutIndicator()
    }

    private func layoutIndicator() {
        let pull = max(overscroll, 0)
        let size: CGFloat = 54
        indicator.frame = CGRect(x: 0, y: view.bounds.height - pull - 10, width: view.bounds.width, height: 100)
        let center = CGPoint(x: indicator.bounds.midX, y: size / 2)
        let path = UIBezierPath(arcCenter: center, radius: size / 2, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
        track.path = path
        ring.path = path
        nextAvatar.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        nextAvatar.center = center
        nextLabel.frame = CGRect(x: 0, y: size + 8, width: indicator.bounds.width, height: 18)
        let progress = min(pull / threshold, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = progress
        CATransaction.commit()
        indicator.alpha = min(1, pull / 30)
        let s = 0.6 + 0.4 * progress + (armed ? 0.1 : 0)
        nextAvatar.transform = CGAffineTransform(scaleX: s, y: s)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let now = overscroll >= threshold
        if now != armed {
            armed = now
            UIImpactFeedbackGenerator(style: now ? .medium : .light).impactOccurred()
            if now {
                let next = channels[(current + 1) % channels.count]
                nextLabel.text = "Отпустите — \(next.0)"
            } else {
                nextLabel.text = "Следующий: \(channels[(current + 1) % channels.count].0) · 12 непрочитанных"
            }
        }
        layoutIndicator()
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard armed else { return }
        armed = false
        goNext()
    }

    /// The old channel slides up and away, the next one rises in on a spring.
    private func goNext() {
        guard let old = scroll.snapshotView(afterScreenUpdates: false) else { return }
        old.frame = scroll.frame
        view.insertSubview(old, belowSubview: indicator)
        let flyer = UIImageView(image: nextAvatar.image)
        flyer.frame = nextAvatar.convert(nextAvatar.bounds, to: view)
        view.addSubview(flyer)
        load(channel: (current + 1) % channels.count)
        scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
        scroll.transform = CGAffineTransform(translationX: 0, y: view.bounds.height * 0.6)
        scroll.alpha = 0
        indicator.alpha = 0
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseIn]) {
            old.transform = CGAffineTransform(translationX: 0, y: -self.view.bounds.height * 0.4).scaledBy(x: 0.92, y: 0.92)
            old.alpha = 0
        } completion: { _ in old.removeFromSuperview() }
        UIView.animate(withDuration: 0.7, delay: 0.1, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.2) {
            self.scroll.transform = .identity
            self.scroll.alpha = 1
        }
        // The next channel's avatar flies up into the title.
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            flyer.center = CGPoint(x: self.view.bounds.midX, y: self.view.safeAreaInsets.top - 22)
            flyer.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            flyer.alpha = 0
        } completion: { _ in flyer.removeFromSuperview() }
    }
}

// MARK: - 4. Archive pull

final class ArchivePullDemoViewController: TrickPage, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let reveal = UIView()
    private let capsule = UIView()
    private let arrow = UIImageView(image: UIImage(systemName: "arrow.down"))
    private let flood = CAGradientLayer()
    private let floodMask = CAShapeLayer()
    private let label = UILabel()
    private let archiveRow = UIView()
    private var armed = false
    private var archiveShown = false
    private let threshold: CGFloat = 86
    private let rowHeight: CGFloat = 76

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Чаты"
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.alwaysBounceVertical = true
        scroll.delegate = self
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
        let messages = ["Отправила макеты, посмотри 🙏", "Созвон в 15:00?", "Ха-ха, это гениально", "Голосовое сообщение",
                        "Фото", "Ок, договорились!", "Где встречаемся?", "Спасибо!", "👍", "Завтра в силе?"]
        for (i, person) in trickPeople.enumerated() {
            stack.addArrangedSubview(TrickViews.chatRow(person, message: messages[i], time: "\(10 + i):\(10 + i * 4)",
                                                        unread: i % 3 == 0 ? i + 1 : 0))
        }

        reveal.clipsToBounds = true
        flood.colors = [UIColor(red: 0.25, green: 0.55, blue: 1, alpha: 1).cgColor, UIColor(red: 0.45, green: 0.35, blue: 0.95, alpha: 1).cgColor]
        flood.startPoint = CGPoint(x: 0, y: 0.5)
        flood.endPoint = CGPoint(x: 1, y: 0.5)
        flood.mask = floodMask
        reveal.layer.addSublayer(flood)
        capsule.backgroundColor = UIColor(white: 1, alpha: 0.2)
        reveal.addSubview(capsule)
        arrow.tintColor = .white
        arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        arrow.contentMode = .center
        reveal.addSubview(arrow)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        reveal.addSubview(label)
        scroll.addSubview(reveal)

        let folder = UIImageView(image: UIImage(systemName: "archivebox.fill"))
        folder.tintColor = .white
        folder.contentMode = .center
        folder.backgroundColor = UIColor(white: 1, alpha: 0.18)
        folder.layer.cornerRadius = 28
        folder.clipsToBounds = true
        folder.frame = CGRect(x: 14, y: 10, width: 56, height: 56)
        archiveRow.addSubview(folder)
        let title = UILabel()
        title.text = "Архив"
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .white
        title.frame = CGRect(x: 82, y: 14, width: 200, height: 22)
        archiveRow.addSubview(title)
        let sub = UILabel()
        sub.text = "Рустам, Вера, Лев…"
        sub.font = .systemFont(ofSize: 15)
        sub.textColor = TrickPalette.secondary
        sub.frame = CGRect(x: 82, y: 38, width: 240, height: 20)
        archiveRow.addSubview(sub)
        archiveRow.alpha = 0
        archiveRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideArchive)))
        scroll.addSubview(archiveRow)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showHint("Потяните список вниз")
    }

    private var pull: CGFloat {
        -(scroll.contentOffset.y + scroll.adjustedContentInset.top) + (archiveShown ? rowHeight : 0)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let p = max(pull - (archiveShown ? rowHeight : 0), 0)
        let width = view.bounds.width
        archiveRow.frame = CGRect(x: 0, y: -rowHeight, width: width, height: rowHeight)
        guard !archiveShown else {
            reveal.frame = .zero
            return
        }
        reveal.frame = CGRect(x: 0, y: -p, width: width, height: p)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flood.frame = reveal.bounds
        CATransaction.commit()
        // The grey capsule grows down from the top with the finger, the arrow riding its bottom.
        let capsuleHeight = max(p - 18, 0)
        capsule.frame = CGRect(x: 14 + 28 - 13, y: 9, width: 26, height: max(capsuleHeight, 26))
        capsule.layer.cornerRadius = 13
        capsule.alpha = min(1, p / 30)
        arrow.frame = CGRect(x: capsule.frame.minX, y: capsule.frame.maxY - 26, width: 26, height: 26)
        arrow.alpha = capsule.alpha
        label.frame = CGRect(x: 82, y: max(p - 46, 0), width: 260, height: 22)
        label.alpha = min(1, max(0, (p - 30) / 30))
        let now = p >= threshold
        if now != armed {
            armed = now
            UIImpactFeedbackGenerator(style: now ? .medium : .light).impactOccurred()
            setFlood(now)
        }
        if !now {
            label.text = "Потяните, чтобы открыть архив"
        }
    }

    /// Blue floods out of the arrow's circle when the pull is far enough, and drains back if not.
    private func setFlood(_ on: Bool) {
        let center = arrow.center
        let small = UIBezierPath(arcCenter: center, radius: 1, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        let big = UIBezierPath(arcCenter: center, radius: view.bounds.width * 1.2, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = on ? small : big
        animation.toValue = on ? big : small
        animation.duration = on ? 0.35 : 0.25
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        floodMask.path = on ? big : small
        floodMask.add(animation, forKey: "flood")
        label.text = on ? "Отпустите, чтобы открыть архив" : "Потяните, чтобы открыть архив"
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
            self.arrow.transform = on ? CGAffineTransform(rotationAngle: .pi) : .identity
        }
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard armed, !archiveShown else { return }
        armed = false
        archiveShown = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        scroll.contentInset.top = rowHeight
        targetContentOffset.pointee.y = -scroll.adjustedContentInset.top
        archiveRow.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        UIView.animate(withDuration: 0.5, delay: 0.05, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.4) {
            self.archiveRow.alpha = 1
            self.archiveRow.transform = .identity
        }
        setFlood(false)
    }

    @objc private func hideArchive() {
        archiveShown = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            self.scroll.contentInset.top = 0
            self.archiveRow.alpha = 0
            self.scroll.contentOffset.y = -self.scroll.adjustedContentInset.top
        }
    }
}

// MARK: - Chat screen base (5, 6, 7)

/// A chat with an input bar; subclasses add their trick.
class TrickChatPage: TrickPage, UITextFieldDelegate {
    let scroll = UIScrollView()
    let stack = UIStackView()
    let inputBar = UIView()
    let input = UITextField()
    let sendButton = UIButton(type: .custom)

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = trickPeople[0].name
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.backgroundColor = TrickPalette.telegramBackground
        view.addSubview(inputBar)
        input.placeholder = "Сообщение"
        input.textColor = .white
        input.backgroundColor = TrickPalette.telegramPanel
        input.layer.cornerRadius = 20
        input.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 10))
        input.leftViewMode = .always
        input.keyboardAppearance = .dark
        input.returnKeyType = .send
        input.delegate = self
        input.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(input)
        sendButton.backgroundColor = TrickPalette.telegramBlue
        sendButton.tintColor = .white
        sendButton.layer.cornerRadius = 20
        sendButton.setImage(UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)),
                            for: .normal)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(sendButton)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: inputBar.topAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            inputBar.heightAnchor.constraint(equalToConstant: 58),
            input.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 10),
            input.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            input.heightAnchor.constraint(equalToConstant: 40),
            sendButton.leadingAnchor.constraint(equalTo: input.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -10),
            sendButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        let seed = [("Привет! Как тебе новые эффекты?", false), ("Очень круто, особенно жидкие реакции 😍", true),
                    ("А попробуй эффекты сообщений и кружки", false), ("Сейчас попробую!", true)]
        for (text, outgoing) in seed {
            addBubble(text, outgoing: outgoing)
        }
    }

    @discardableResult
    func addBubble(_ text: String, outgoing: Bool) -> UIView {
        let bubble = TrickViews.bubble(text, outgoing: outgoing)
        stack.addArrangedSubview(TrickViews.row(bubble, outgoing: outgoing))
        return bubble
    }

    func scrollToBottom(animated: Bool) {
        view.layoutIfNeeded()
        let y = max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
        scroll.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return false
    }

    func sendTapped() {}
}

// MARK: - 5. Message effects

final class MessageEffectsDemoViewController: TrickChatPage {
    private let effects = ["🎉", "❤️", "👍", "🔥", "💩", "🤯"]
    private var menu: UIView?
    private var effectFor: [ObjectIdentifier: String] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        sendButton.addAction(UIAction { [weak self] _ in self?.sendTapped() }, for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(holdSend(_:)))
        hold.minimumPressDuration = 0.3
        sendButton.addGestureRecognizer(hold)
        input.text = "С днём рождения!"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showHint("Удерживайте кнопку отправки, чтобы выбрать эффект", bottom: 90)
    }

    override func sendTapped() {
        send(effect: nil)
    }

    @objc private func holdSend(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, menu == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let dim = UIView(frame: view.bounds)
        dim.backgroundColor = UIColor(white: 0, alpha: 0.4)
        dim.alpha = 0
        let panel = UIView()
        panel.backgroundColor = TrickPalette.telegramPanel
        panel.layer.cornerRadius = 26
        let size: CGFloat = 52
        let origin = sendButton.convert(CGPoint(x: 20, y: 0), to: view)
        panel.frame = CGRect(x: origin.x - size / 2, y: origin.y - CGFloat(effects.count) * size - 14, width: size,
                             height: CGFloat(effects.count) * size + 6)
        for (index, emoji) in effects.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 30)
            button.frame = CGRect(x: 0, y: 3 + CGFloat(index) * size, width: size, height: size)
            button.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            button.addAction(UIAction { [weak self] _ in self?.pick(emoji) }, for: .touchUpInside)
            panel.addSubview(button)
            UIView.animate(withDuration: 0.45, delay: 0.03 * Double(effects.count - index), usingSpringWithDamping: 0.5,
                           initialSpringVelocity: 0.6) {
                button.transform = .identity
            }
        }
        dim.addSubview(panel)
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeMenu)))
        view.addSubview(dim)
        panel.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        panel.frame.origin.y += panel.bounds.height / 2
        panel.transform = CGAffineTransform(scaleX: 0.3, y: 0.1)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            dim.alpha = 1
            panel.transform = .identity
        }
        menu = dim
    }

    @objc private func closeMenu() {
        guard let menu else { return }
        self.menu = nil
        UIView.animate(withDuration: 0.2) { menu.alpha = 0 } completion: { _ in menu.removeFromSuperview() }
    }

    private func pick(_ emoji: String) {
        closeMenu()
        send(effect: emoji)
    }

    private func send(effect: String?) {
        let text = (input.text ?? "").isEmpty ? "С днём рождения!" : input.text!
        input.text = ""
        let bubble = addBubble(text + (effect.map { " \($0)" } ?? ""), outgoing: true)
        bubble.alpha = 0
        bubble.transform = CGAffineTransform(translationX: 0, y: 40).scaledBy(x: 0.8, y: 0.8)
        scrollToBottom(animated: true)
        UIView.animate(withDuration: 0.4, delay: 0.05, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.4) {
            bubble.alpha = 1
            bubble.transform = .identity
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let effect {
            effectFor[ObjectIdentifier(bubble)] = effect
            bubble.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(replay(_:))))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak bubble] in
                guard let self, let bubble else { return }
                play(effect, on: bubble)
            }
        }
    }

    @objc private func replay(_ gesture: UITapGestureRecognizer) {
        guard let bubble = gesture.view, let effect = effectFor[ObjectIdentifier(bubble)] else { return }
        play(effect, on: bubble)
    }

    /// A big emoji pops at the bubble and bursts across the screen.
    private func play(_ effect: String, on bubble: UIView) {
        guard let window = view.window else { return }
        let point = bubble.convert(CGPoint(x: 0, y: bubble.bounds.midY), to: window)
        let big = UILabel()
        big.text = effect
        big.font = .systemFont(ofSize: 90)
        big.sizeToFit()
        big.center = point
        big.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        window.addSubview(big)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.8) {
            big.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        }
        UIView.animate(withDuration: 0.4, delay: 0.7) {
            big.alpha = 0
            big.transform = CGAffineTransform(scaleX: 2, y: 2)
        } completion: { _ in big.removeFromSuperview() }
        TrickViews.emojiBurst(effect, in: window, at: point, count: 55, duration: 0.4)
        if effect == "🎉" {
            IslandConfetti.burst(in: window, from: point, direction: -.pi / 2, spread: 2.6, particles: 500, sparkShare: 0.3,
                                 speedScale: 0.8)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        bubble.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.5) {
            bubble.transform = .identity
        }
    }
}

// MARK: - 6. Round video message

/// A round "video": a living gradient in a circle, with a progress ring.
private final class RoundVideoView: UIView {
    let video = FluidMeshGradientView()
    let ring = CAShapeLayer()

    init(seed: Int) {
        super.init(frame: .zero)
        let palettes: [[UIColor]] = [
            [.systemPink, .systemOrange, .systemPurple, .systemYellow],
            [.systemTeal, .systemBlue, .systemIndigo, .systemMint],
            [.systemGreen, .systemYellow, .systemTeal, .systemOrange],
        ]
        video.colors = palettes[seed % palettes.count]
        video.speed = 1.6
        video.clipsToBounds = true
        addSubview(video)
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = 3
        ring.lineCap = .round
        ring.strokeEnd = 0
        layer.addSublayer(ring)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        video.frame = bounds.insetBy(dx: 5, dy: 5)
        video.layer.cornerRadius = video.bounds.width / 2
        ring.frame = bounds
        ring.path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: bounds.width / 2 - 1.5,
                                 startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
    }
}

final class RoundVideoDemoViewController: TrickChatPage {
    private var recorder: RoundVideoView?
    private var dim: UIView?
    private var recordStart: CFTimeInterval = 0
    private var link: CADisplayLink?
    private var count = 0
    private let maxDuration: CFTimeInterval = 15

    override func viewDidLoad() {
        super.viewDidLoad()
        sendButton.setImage(UIImage(systemName: "video.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22)),
                            for: .normal)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(hold(_:)))
        hold.minimumPressDuration = 0.15
        sendButton.addGestureRecognizer(hold)
        addRound(animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showHint("Удерживайте кнопку камеры, чтобы записать кружок. Тап по кружку — воспроизвести", bottom: 90)
    }

    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            startRecording()
        case .ended, .cancelled, .failed:
            stopRecording()
        default:
            break
        }
    }

    private func startRecording() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let dim = UIView(frame: view.bounds)
        dim.backgroundColor = UIColor(white: 0, alpha: 0.6)
        dim.alpha = 0
        view.addSubview(dim)
        let round = RoundVideoView(seed: count)
        round.ring.strokeColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1).cgColor
        let size = view.bounds.width - 70
        round.frame = CGRect(x: 0, y: 0, width: size, height: size)
        round.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY - 40)
        round.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        dim.addSubview(round)
        UIView.animate(withDuration: 0.25) { dim.alpha = 1 }
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.5) {
            round.transform = .identity
        }
        self.dim = dim
        recorder = round
        recordStart = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        let t = CACurrentMediaTime() - recordStart
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        recorder?.ring.strokeEnd = CGFloat(min(t / maxDuration, 1))
        CATransaction.commit()
        if t >= maxDuration {
            stopRecording()
        }
    }

    private func stopRecording() {
        link?.invalidate()
        link = nil
        guard let round = recorder, let dim else { return }
        recorder = nil
        self.dim = nil
        let bubble = addRound(animated: true)
        view.layoutIfNeeded()
        scrollToBottom(animated: false)
        view.layoutIfNeeded()
        let target = bubble.convert(bubble.bounds, to: dim)
        bubble.alpha = 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // The circle shrinks into its place in the chat.
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.2) {
            round.center = CGPoint(x: target.midX, y: target.midY)
            let s = target.width / round.bounds.width
            round.transform = CGAffineTransform(scaleX: s, y: s)
            dim.backgroundColor = .clear
        } completion: { _ in
            bubble.alpha = 1
            dim.removeFromSuperview()
        }
    }

    @discardableResult
    private func addRound(animated: Bool) -> UIView {
        let round = RoundVideoView(seed: count)
        count += 1
        round.translatesAutoresizingMaskIntoConstraints = false
        round.widthAnchor.constraint(equalToConstant: 200).isActive = true
        round.heightAnchor.constraint(equalToConstant: 200).isActive = true
        round.video.isPaused = true
        round.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(play(_:))))
        stack.addArrangedSubview(TrickViews.row(round, outgoing: true))
        return round
    }

    /// The round grows big and plays, a white ring running around it, then shrinks back.
    @objc private func play(_ gesture: UITapGestureRecognizer) {
        guard let round = gesture.view as? RoundVideoView, round.layer.animation(forKey: "play") == nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        round.video.isPaused = false
        let center = round.convert(CGPoint(x: round.bounds.midX, y: round.bounds.midY), to: view)
        let move = CGAffineTransform(translationX: view.bounds.midX - center.x, y: view.bounds.midY - 60 - center.y)
        let s = (view.bounds.width - 60) / round.bounds.width
        round.superview?.bringSubviewToFront(round)
        round.ring.strokeEnd = 0
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.3) {
            round.transform = move.scaledBy(x: s, y: s)
        }
        let progress = CABasicAnimation(keyPath: "strokeEnd")
        progress.fromValue = 0
        progress.toValue = 1
        progress.duration = 5
        round.ring.add(progress, forKey: "play")
        round.layer.add(CABasicAnimation(keyPath: "opacity"), forKey: "play")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            round.layer.removeAnimation(forKey: "play")
            round.video.isPaused = true
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.2) {
                round.transform = .identity
            }
        }
    }
}

// MARK: - 7. Swipe to reply

final class SwipeReplyDemoViewController: TrickChatPage, UIGestureRecognizerDelegate {
    private let liquid = LiquidCanvasView()
    private let arrow = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left.fill"))
    private var dragged: UIView?
    private var pull: CGFloat = 0
    private var snapped = false
    private var dropRadius = Spring1D(0, stiffness: 18, dampingRatio: 0.45)
    private let replyPanel = UIView()
    private let replyText = UILabel()
    private let threshold: CGFloat = 70

    override func viewDidLoad() {
        super.viewDidLoad()
        for (text, outgoing) in [("Смахните любое сообщение влево ←", false), ("Капля оторвётся от пузыря и станет стрелкой", false),
                                 ("Работает и с моими сообщениями", true)] {
            addBubble(text, outgoing: outgoing)
        }
        liquid.liquidColor = UIColor(white: 1, alpha: 0.16)
        liquid.gloss = 0.5
        liquid.rimWidth = 6
        liquid.onUpdate = { [weak self] dt in self?.step(dt) }
        view.addSubview(liquid)
        arrow.tintColor = .white
        arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        arrow.sizeToFit()
        arrow.alpha = 0
        view.addSubview(arrow)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.delegate = self
        scroll.addGestureRecognizer(pan)
        sendButton.addAction(UIAction { [weak self] _ in self?.sendTapped() }, for: .touchUpInside)

        replyPanel.backgroundColor = TrickPalette.telegramPanel
        replyPanel.translatesAutoresizingMaskIntoConstraints = false
        let bar = UIView()
        bar.backgroundColor = TrickPalette.telegramBlue
        bar.layer.cornerRadius = 1.5
        bar.translatesAutoresizingMaskIntoConstraints = false
        replyText.font = .systemFont(ofSize: 14)
        replyText.textColor = .white
        replyText.numberOfLines = 2
        replyText.translatesAutoresizingMaskIntoConstraints = false
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = TrickPalette.secondary
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addAction(UIAction { [weak self] _ in self?.setReply(nil) }, for: .touchUpInside)
        for v in [bar, replyText, close] {
            replyPanel.addSubview(v)
        }
        view.insertSubview(replyPanel, belowSubview: inputBar)
        NSLayoutConstraint.activate([
            replyPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            replyPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            replyPanel.bottomAnchor.constraint(equalTo: inputBar.topAnchor),
            replyPanel.heightAnchor.constraint(equalToConstant: 52),
            bar.leadingAnchor.constraint(equalTo: replyPanel.leadingAnchor, constant: 16),
            bar.topAnchor.constraint(equalTo: replyPanel.topAnchor, constant: 9),
            bar.bottomAnchor.constraint(equalTo: replyPanel.bottomAnchor, constant: -9),
            bar.widthAnchor.constraint(equalToConstant: 3),
            replyText.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 10),
            replyText.centerYAnchor.constraint(equalTo: replyPanel.centerYAnchor),
            replyText.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -10),
            close.trailingAnchor.constraint(equalTo: replyPanel.trailingAnchor, constant: -12),
            close.centerYAnchor.constraint(equalTo: replyPanel.centerYAnchor),
        ])
        replyPanel.transform = CGAffineTransform(translationX: 0, y: 60)
        replyPanel.alpha = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToBottom(animated: false)
        showHint("Смахните сообщение влево, чтобы ответить", bottom: 90)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        liquid.frame = view.bounds
    }

    override func sendTapped() {
        guard let text = input.text, !text.isEmpty else { return }
        input.text = ""
        addBubble(text, outgoing: true)
        setReply(nil)
        scrollToBottom(animated: true)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let v = pan.velocity(in: view)
        return v.x < 0 && abs(v.x) > abs(v.y) * 1.3
    }

    private func bubble(at point: CGPoint) -> UIView? {
        for row in stack.arrangedSubviews {
            guard let bubble = row.subviews.first else { continue }
            let frame = bubble.convert(bubble.bounds, to: scroll)
            if frame.minY - 6 <= point.y, point.y <= frame.maxY + 6 {
                return bubble
            }
        }
        return nil
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragged = bubble(at: gesture.location(in: scroll))
            snapped = false
            liquid.isPaused = false
        case .changed:
            let raw = -gesture.translation(in: view).x
            // Rubber band past the threshold.
            pull = raw < threshold ? raw : threshold + (raw - threshold) * 0.3
            dragged?.transform = CGAffineTransform(translationX: -max(pull, 0), y: 0)
            if !snapped, pull >= threshold {
                snapped = true
                dropRadius.velocity += 60
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        default:
            if snapped, let bubble = dragged {
                setReply(bubble)
            }
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.3) {
                self.dragged?.transform = .identity
            }
            pull = 0
            snapped = false
            dragged = nil
        }
    }

    private func step(_ dt: CFTimeInterval) {
        dropRadius.step(toward: dragged != nil ? (snapped ? 15 : min(pull / threshold, 1) * 12) : 0, deltaTime: dt)
        guard let bubble = dragged ?? nil else {
            let r = max(dropRadius.value, 0)
            liquid.shapes = r > 0.4 ? [.circle(center: arrow.center, radius: r, blend: 0)] : []
            liquid.spikes = []
            arrow.alpha = min(1, r / 10)
            if r < 0.4 {
                liquid.renderFrame()
                liquid.isPaused = true
            }
            return
        }
        let frame = bubble.convert(bubble.bounds, to: view)
        let edge = CGPoint(x: frame.maxX, y: frame.midY)
        let rowRight = view.bounds.width - 12
        let dropCenter = CGPoint(x: min(edge.x + 10 + pull * 0.35, rowRight - 18), y: frame.midY)
        let r = max(dropRadius.value, 0)
        arrow.center = dropCenter
        arrow.alpha = snapped ? 1 : 0
        arrow.transform = snapped ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        liquid.shapes = r > 0.4 ? [.circle(center: dropCenter, radius: r, blend: 0)] : []
        // Until it snaps, the drop is tied to the bubble's edge by a neck that thins as it stretches.
        if !snapped, r > 1 {
            liquid.spikes = [IslandFluidSpike(base: CGPoint(x: edge.x - 4, y: edge.y), tip: dropCenter,
                                              baseRadius: max(2, 8 - pull / 14), tipRadius: r * 0.6, blend: 5)]
        } else {
            liquid.spikes = []
        }
    }

    private func setReply(_ bubble: UIView?) {
        if let bubble, let label = bubble.subviews.first as? UILabel {
            replyText.text = "Ответ: \(label.text ?? "")"
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.3) {
                self.replyPanel.transform = .identity
                self.replyPanel.alpha = 1
            }
            input.becomeFirstResponder()
        } else {
            UIView.animate(withDuration: 0.25) {
                self.replyPanel.transform = CGAffineTransform(translationX: 0, y: 60)
                self.replyPanel.alpha = 0
            }
        }
    }
}
