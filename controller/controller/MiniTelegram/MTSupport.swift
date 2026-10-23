//
//  MTSupport.swift
//  controller
//
//  Mini-Telegram: the shared palette (light and dark, so the liquid theme switch works), the demo
//  data (accounts, chats, messages) and a few small views used by several screens.
//

import UIKit

enum MTPalette {
    private static func dynamic(_ light: UIColor, _ dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    static let background = dynamic(.white, UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1))
    static let grouped = dynamic(UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1), .black)
    static let cell = dynamic(.white, UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
    static let bar = dynamic(UIColor(white: 0.98, alpha: 0.82), UIColor(red: 0.09, green: 0.09, blue: 0.1, alpha: 0.82))
    static let text = dynamic(.black, .white)
    static let secondary = dynamic(UIColor(white: 0.45, alpha: 1), UIColor(white: 0.55, alpha: 1))
    static let separator = dynamic(UIColor(white: 0.85, alpha: 1), UIColor(white: 0.2, alpha: 1))
    static let accent = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1)
    static let fill = dynamic(UIColor(white: 0.93, alpha: 1), UIColor(white: 0.17, alpha: 1))
    static let muted = dynamic(UIColor(white: 0.72, alpha: 1), UIColor(white: 0.35, alpha: 1))
    static let online = UIColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
    static let red = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)
    static let orange = UIColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1)
    static let wallpaper = dynamic(UIColor(red: 0.82, green: 0.88, blue: 0.78, alpha: 1), UIColor(red: 0.06, green: 0.08, blue: 0.1, alpha: 1))
    static let incoming = dynamic(.white, UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1))
    /// Your bubbles take the chat theme's color (MTChatTheme.current).
    static let outgoing = UIColor { trait in
        let theme = MTChatTheme.all[MTChatTheme.current]
        return trait.userInterfaceStyle == .dark ? theme.outgoingNight : theme.outgoingDay
    }
    static let outgoingMeta = dynamic(UIColor(red: 0.3, green: 0.65, blue: 0.3, alpha: 1), UIColor(white: 1, alpha: 0.65))
    static let storyRing = UIColor(red: 0.2, green: 0.62, blue: 1.0, alpha: 1)
    /// Dark-only things (calls, the photo gallery) in light mode too.
    static let glass = UIColor(white: 1, alpha: 0.16)
}

// MARK: - Data

struct MTAccount {
    let person: ChannelPerson
    let phone: String
    let username: String
}

enum MTFolder: Int, CaseIterable {
    case all, personal, channels, bots

    var title: String {
        switch self {
        case .all: return "Все"
        case .personal: return "Личные"
        case .channels: return "Каналы"
        case .bots: return "Боты"
        }
    }
}

enum MTChatKind {
    case person, group, channel, bot
}

struct MTChat {
    let id: Int
    let person: ChannelPerson
    let kind: MTChatKind
    var message: String
    var time: String
    var unread = 0
    var muted = false
    var pinned = false
    /// Our last message: nil when the last message is theirs, false = delivered, true = read.
    var outgoingRead: Bool?
    var online = false

    func belongs(to folder: MTFolder) -> Bool {
        switch folder {
        case .all: return true
        case .personal: return kind == .person
        case .channels: return kind == .channel || kind == .group
        case .bots: return kind == .bot
        }
    }
}

enum MTData {
    static let accounts = [
        MTAccount(person: ChannelPerson(name: "Максим Ветров", hue: 0.6), phone: "+7 912 345-67-89", username: "@vetrov"),
        MTAccount(person: ChannelPerson(name: "Студия Ветров", hue: 0.83), phone: "+7 900 111-22-33", username: "@vetrov_studio"),
        MTAccount(person: ChannelPerson(name: "Макс Тест", hue: 0.12), phone: "+44 7700 900123", username: "@max_test"),
    ]

    static let storyUsers: [StoryUser] = trickPeople.prefix(7).enumerated().map { index, person in
        let scenes = DemoPhotos.Scene.allCases
        return StoryUser(person: person, photos: [scenes[index % scenes.count], scenes[(index + 3) % scenes.count]])
    }

    /// A different chat list for every account, so switching accounts visibly changes the screen.
    static func chats(for account: Int) -> [MTChat] {
        let people = trickPeople
        var chats: [MTChat] = [
            MTChat(id: 0, person: ChannelPerson(name: "Дизайн-команда", hue: 0.45), kind: .group,
                   message: "Анна: макеты таб-бара готовы, гляньте 👀", time: "21:04", unread: 12, pinned: true),
            MTChat(id: 1, person: people[0], kind: .person, message: "Завтра в 10 созвон, не забудь", time: "20:51",
                   unread: 2, online: true),
            MTChat(id: 2, person: people[1], kind: .person, message: "Отправил тебе файлы", time: "20:30",
                   outgoingRead: false),
            MTChat(id: 3, person: ChannelPerson(name: "Metal Weekly", hue: 0.02), kind: .channel,
                   message: "Шейдеры SDF: как сделать жидкость за 40 строк", time: "19:12", unread: 48, muted: true),
            MTChat(id: 4, person: people[2], kind: .person, message: "Ахах, это лучшее 😂", time: "18:40", online: true),
            MTChat(id: 5, person: ChannelPerson(name: "Погода Бот", hue: 0.55), kind: .bot,
                   message: "☀️ Завтра +18°, без осадков", time: "18:00", unread: 1),
            MTChat(id: 6, person: people[3], kind: .person, message: "Ок, договорились", time: "17:22", outgoingRead: true),
            MTChat(id: 7, person: ChannelPerson(name: "iOS Dev Chat", hue: 0.7), kind: .group,
                   message: "Игорь: кто пробовал iOS 27 beta?", time: "16:05", unread: 5, muted: true),
            MTChat(id: 8, person: people[4], kind: .person, message: "Фото с выходных 📷", time: "15:47", unread: 3),
            MTChat(id: 9, person: ChannelPerson(name: "Новости Tech", hue: 0.1), kind: .channel,
                   message: "Apple показала новые MacBook", time: "14:30", unread: 210, muted: true),
            MTChat(id: 10, person: people[5], kind: .person, message: "Голосовое сообщение", time: "13:02", outgoingRead: true),
            MTChat(id: 11, person: ChannelPerson(name: "Такси Бот", hue: 0.15), kind: .bot,
                   message: "Ваша поездка завершена. Оцените водителя", time: "12:15"),
            MTChat(id: 12, person: people[6], kind: .person, message: "Спасибо!", time: "Вчера", online: true),
            MTChat(id: 13, person: people[7], kind: .person, message: "Где встречаемся?", time: "Вчера", unread: 1),
            MTChat(id: 14, person: people[8], kind: .person, message: "Стикер", time: "Пн", outgoingRead: true),
            MTChat(id: 15, person: people[9], kind: .person, message: "До встречи 👋", time: "Вс"),
        ]
        guard account > 0 else { return chats }
        // Other accounts: another order, other counters, fewer chats.
        var generator = SplitMix(seed: UInt64(account * 977))
        chats = chats.filter { _ in generator.next() > 0.3 }
        for index in chats.indices {
            chats[index].unread = generator.next() > 0.5 ? Int(generator.next() * 30) : 0
            chats[index].pinned = index == 0
        }
        // Pinned first, the rest in a seeded order.
        return [chats[0]] + chats.dropFirst().map { ($0, generator.next()) }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    static let pinnedMessages = [
        "📌 Правила чата: без спама",
        "Ссылка на макеты в Figma",
        "Созвон по пятницам в 11:00",
        "Релиз 2.0 — 1 ноября 🚀",
    ]
}

// MARK: - Small views

enum MTViews {
    static func label(_ text: String = "", size: CGFloat, weight: UIFont.Weight = .regular,
                      color: UIColor = MTPalette.text) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    /// A plain symbol button in the accent color.
    static func iconButton(_ symbol: String, size: CGFloat = 20, tint: UIColor = MTPalette.accent) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .medium)),
                        for: .normal)
        button.tintColor = tint
        return button
    }

    /// A blurred bar background that follows the theme.
    static func barBackground() -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    }

    /// A pill that drops in at the top of `host`, stays a moment and leaves.
    static func toast(_ text: String, symbol: String, in host: UIView, top: CGFloat? = nil) {
        let pill = UIView()
        pill.backgroundColor = UIColor(white: 0.1, alpha: 0.92)
        pill.layer.cornerRadius = 22
        pill.layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = .white
        icon.contentMode = .center
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        pill.addSubview(icon)
        pill.addSubview(label)
        let width = min(host.bounds.width - 32, label.intrinsicContentSize.width + 66)
        pill.frame = CGRect(x: (host.bounds.width - width) / 2, y: top ?? host.safeAreaInsets.top + 8, width: width, height: 44)
        icon.frame = CGRect(x: 10, y: 0, width: 36, height: 44)
        label.frame = CGRect(x: 48, y: 0, width: width - 60, height: 44)
        host.addSubview(pill)
        pill.transform = CGAffineTransform(translationX: 0, y: -90).scaledBy(x: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4) {
            pill.transform = .identity
        }
        UIView.animate(withDuration: 0.35, delay: 2.2, options: .curveEaseIn, animations: {
            pill.transform = CGAffineTransform(translationX: 0, y: -90).scaledBy(x: 0.7, y: 0.7)
        }, completion: { _ in pill.removeFromSuperview() })
    }

    /// Bounces a view: squash, then spring back.
    static func pop(_ view: UIView, scale: CGFloat = 1.25) {
        view.transform = CGAffineTransform(scaleX: scale, y: scale)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.6) {
            view.transform = .identity
        }
    }
}

/// An avatar with an optional green "online" dot cut out of it.
final class MTAvatarView: UIView {
    let image = UIImageView()
    private let dot = UIView()

    var online = false {
        didSet { dot.isHidden = !online }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(image)
        dot.backgroundColor = MTPalette.online
        dot.layer.borderWidth = 2.5
        dot.isHidden = true
        addSubview(dot)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.dot.layer.borderColor = MTPalette.background.resolvedColor(with: self.traitCollection).cgColor
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(_ person: ChannelPerson, size: CGFloat) {
        image.image = ChannelAvatar.image(for: person, size: size)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        image.frame = bounds
        let size = bounds.width * 0.27
        dot.frame = CGRect(x: bounds.width - size + 1, y: bounds.height - size + 1, width: size, height: size)
        dot.layer.cornerRadius = size / 2
        dot.layer.borderColor = MTPalette.background.resolvedColor(with: traitCollection).cgColor
    }
}

/// One or two checkmarks; the second one slides in when the message is read.
final class MTChecksView: UIView {
    private let first = UIImageView()
    private let second = UIImageView()

    var tint: UIColor = MTPalette.accent {
        didSet {
            first.tintColor = tint
            second.tintColor = tint
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let configuration = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        for check in [first, second] {
            check.image = UIImage(systemName: "checkmark", withConfiguration: configuration)
            check.tintColor = tint
            check.contentMode = .center
            addSubview(check)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize { CGSize(width: 20, height: 14) }

    override func layoutSubviews() {
        super.layoutSubviews()
        first.frame = CGRect(x: 0, y: 0, width: 14, height: bounds.height)
        second.frame = CGRect(x: 5, y: 0, width: 14, height: bounds.height)
    }

    func set(read: Bool, animated: Bool) {
        guard animated else {
            second.alpha = read ? 1 : 0
            second.transform = .identity
            return
        }
        guard read, second.alpha == 0 else { return }
        second.transform = CGAffineTransform(translationX: -6, y: 0).scaledBy(x: 0.3, y: 0.3)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8) {
            self.second.alpha = 1
            self.second.transform = .identity
        }
        MTViews.pop(first, scale: 1.3)
    }
}

/// Three dots bouncing one after another: "печатает…".
final class MTTypingDots: UIView {
    private var dots: [UIView] = []

    var color: UIColor = MTPalette.accent {
        didSet { dots.forEach { $0.backgroundColor = color } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        dots = (0..<3).map { _ in
            let dot = UIView()
            dot.backgroundColor = color
            dot.layer.cornerRadius = 2.5
            addSubview(dot)
            return dot
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize { CGSize(width: 24, height: 10) }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, dot) in dots.enumerated() {
            dot.frame = CGRect(x: CGFloat(index) * 8, y: bounds.midY - 2.5, width: 5, height: 5)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        for (index, dot) in dots.enumerated() {
            dot.layer.removeAllAnimations()
            guard window != nil else { continue }
            let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bounce.values = [0, -3.5, 0, 0]
            bounce.keyTimes = [0, 0.25, 0.5, 1]
            bounce.duration = 0.9
            bounce.repeatCount = .infinity
            bounce.beginTime = CACurrentMediaTime() + Double(index) * 0.15
            dot.layer.add(bounce, forKey: "bounce")
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.4, 1, 0.4, 0.4]
            fade.keyTimes = [0, 0.25, 0.5, 1]
            fade.duration = 0.9
            fade.repeatCount = .infinity
            fade.beginTime = bounce.beginTime
            dot.layer.add(fade, forKey: "fade")
        }
    }
}

/// An unread badge whose number rolls and which pops when it appears.
final class MTBadge: UIView {
    private let label = RollingCounterLabel()
    private(set) var value = 0

    var muted = false {
        didSet { backgroundColor = muted ? MTPalette.muted : MTPalette.accent }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = MTPalette.accent
        layer.cornerRadius = 11
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var width: CGFloat { value == 0 ? 0 : max(22, label.intrinsicContentSize.width + 14) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = label.intrinsicContentSize
        label.frame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                             width: size.width, height: size.height)
    }

    func set(_ count: Int, animated: Bool) {
        let old = value
        value = count
        label.setText(FeedFormat.count(count), animated: animated && old > 0 && count > 0, up: count > old)
        guard animated else {
            alpha = count > 0 ? 1 : 0
            return
        }
        if old == 0, count > 0 {
            alpha = 1
            MTViews.pop(self, scale: 0.3)
        } else if count == 0 {
            UIView.animate(withDuration: 0.25) {
                self.alpha = 0
                self.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            } completion: { _ in self.transform = .identity }
        } else {
            MTViews.pop(self, scale: 1.15)
        }
    }
}
