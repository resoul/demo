//
//  ChannelFeedDemos.swift
//  controller
//
//  A Telegram-style channel with liquid reactions (MetalVFXEngine/ChannelFeed), opened from the
//  "Channel" section of the VFX menu. Everything on it is interactive:
//  long-press a post → liquid reaction picker (slide to an emoji, or the trash to delete the post
//  into the Dynamic Island; ⌄ opens the accordion with more reactions); double-tap → a liquid heart
//  flies into ❤️; tap a chip to react or take it back (dust); hold ⭐ to send stars; tap the avatars to spread them, the comments row to pour
//  the post into the comments; drag the share button onto a contact; wipe the ink spoiler.
//  The channel avatar's menu posts new messages, drops in commenters and toggles live reactions.
//

import UIKit

final class ChannelFeedDemoViewController: UIViewController, UIScrollViewDelegate {
    private let wallpaper = ChannelWallpaperView()
    private let bubbleLiquid = FeedLiquidLayer(color: ChannelPalette.bubble, gloss: 0.04)
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let topGlass = ChannelGlassView()
    private let bottomGlass = ChannelGlassView()
    private let accentLiquid = FeedLiquidLayer(color: ChannelPalette.accent, gloss: 0.5)

    private let backButton = UIButton(type: .system)
    private let titlePill = UIView()
    private let avatarButton = UIButton(type: .custom)
    private let giftButton = UIButton(type: .system)
    private let unmuteButton = UIButton(type: .system)
    private let searchButton = UIButton(type: .system)
    private let scrollDown = ScrollDownButton()
    private let hint = UILabel()

    private var posts: [ChannelPostView] = []
    private var picker: ReactionPickerOverlay?
    private var forward: ForwardDropOverlay?
    private let vacuum = SandVacuumAnimator()
    /// Post snapshots for the glass, shared by the header and the bottom bar.
    private let snapshots = FeedSnapshotCache()
    private var unread = 0
    private var muted = true
    private var liveReactions = true
    private var liveTimer: Timer?
    private var didScrollToBottom = false
    private var nextPost = 0

    private let people = [
        ChannelPerson(name: "Анна Смирнова", hue: 0.93), ChannelPerson(name: "Михаил Орлов", hue: 0.58),
        ChannelPerson(name: "Катя Лебедева", hue: 0.08), ChannelPerson(name: "Игорь Ким", hue: 0.36),
        ChannelPerson(name: "Ольга Белова", hue: 0.75), ChannelPerson(name: "Дмитрий Волков", hue: 0.15),
        ChannelPerson(name: "Софья Ли", hue: 0.5), ChannelPerson(name: "Рустам Ахмедов", hue: 0.02),
    ]
    private let channel = ChannelPerson(name: "VFX Daily", hue: 0.72)
    private let pickerEmojis = ["❤️", "👍", "🔥", "😁", "🙏", "👏", "🤯"]
    /// The accordion under the ⌄: 4 rows of 8.
    private let moreEmojis = ["😂", "🥰", "😍", "🤩", "😎", "🤔", "😱", "🥳",
                              "😭", "🤝", "💯", "⚡", "🎉", "🙈", "😇", "🤗",
                              "👀", "💔", "🤡", "🏆", "🍾", "🌚", "🥱", "🤓",
                              "✍️", "💅", "🫡", "🦄", "🐳", "🍓", "🌭", "👻"]

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black

        wallpaper.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wallpaper.frame = view.bounds
        view.addSubview(wallpaper)
        // Under the feed: a new post's liquid shows through until the real bubble fades in over it.
        bubbleLiquid.frame = view.bounds
        bubbleLiquid.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(bubbleLiquid)

        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.alwaysBounceVertical = true
        scroll.delegate = self
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
        for post in initialPosts() {
            addPost(post)
        }

        for glass in [topGlass, bottomGlass] {
            glass.backdropViews = { [weak self] in self?.posts ?? [] }
            glass.snapshots = snapshots
            glass.wallpaper = wallpaper
            view.addSubview(glass)
        }
        buildHeader()
        buildBottomBar()
        accentLiquid.frame = view.bounds
        accentLiquid.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(accentLiquid)

        let observer = TouchObserverGestureRecognizer()
        observer.onTouch = { [weak self] point, phase in
            guard let self else { return }
            scrollDown.attract(to: phase == .ended || phase == .cancelled ? nil : point)
        }
        view.addGestureRecognizer(observer)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startLiveReactions()
        showHint()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        liveTimer?.invalidate()
        liveTimer = nil
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        let width = view.bounds.width, height = view.bounds.height
        let headerY = safe.top + 2
        backButton.frame = CGRect(x: 14, y: headerY, width: 46, height: 46)
        avatarButton.frame = CGRect(x: width - 60, y: headerY, width: 46, height: 46)
        titlePill.frame = CGRect(x: 76, y: headerY, width: width - 152, height: 46)
        topGlass.frame = CGRect(x: 0, y: 0, width: width, height: headerY + 60)

        let bottomY = height - max(safe.bottom, 14) - 48
        giftButton.frame = CGRect(x: 14, y: bottomY, width: 46, height: 46)
        searchButton.frame = CGRect(x: width - 60, y: bottomY, width: 46, height: 46)
        unmuteButton.frame = CGRect(x: 76, y: bottomY, width: width - 152, height: 46)
        scrollDown.bounds = CGRect(x: 0, y: 0, width: 46, height: 46)
        scrollDown.center = CGPoint(x: width - 37, y: bottomY - 34)
        bottomGlass.frame = CGRect(x: 0, y: bottomY - 70, width: width, height: height - bottomY + 70)

        let insets = UIEdgeInsets(top: headerY + 58, left: 0, bottom: height - bottomY + 12, right: 0)
        if scroll.contentInset != insets {
            scroll.contentInset = insets
            scroll.verticalScrollIndicatorInsets = insets
        }
        if !didScrollToBottom, stack.bounds.height > 0 {
            didScrollToBottom = true
            scroll.layoutIfNeeded()
            scroll.contentOffset = bottomOffset
        }
    }

    // MARK: Building

    private func circleButton(_ button: UIButton, symbol: String) {
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)),
                        for: .normal)
        button.tintColor = .white
        view.addSubview(button)
    }

    private func buildHeader() {
        circleButton(backButton, symbol: "chevron.left")
        backButton.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) },
                             for: .touchUpInside)

        let title = UILabel()
        title.text = "VFX Daily"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .white
        let mute = UIImageView(image: UIImage(systemName: "speaker.slash.fill"))
        mute.tintColor = ChannelPalette.secondaryText
        mute.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11)
        let titleRow = UIStackView(arrangedSubviews: [title, mute])
        titleRow.spacing = 5
        titleRow.alignment = .center
        let subtitle = UILabel()
        subtitle.text = "304.600 subscribers"
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = ChannelPalette.secondaryText
        let column = UIStackView(arrangedSubviews: [titleRow, subtitle])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 0
        column.translatesAutoresizingMaskIntoConstraints = false
        titlePill.addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: titlePill.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: titlePill.centerYAnchor),
        ])
        view.addSubview(titlePill)

        avatarButton.setImage(ChannelAvatar.image(for: channel, size: 38), for: .normal)
        avatarButton.menu = demoMenu()
        avatarButton.showsMenuAsPrimaryAction = true
        view.addSubview(avatarButton)

        topGlass.shapeProvider = { [weak self] in
            guard let self else { return [] }
            return [backButton, titlePill, avatarButton].map { control in
                let frame = control.convert(control.bounds, to: self.topGlass)
                return ChannelGlassView.Shape(rect: frame, cornerRadius: frame.height / 2)
            }
        }
    }

    private func buildBottomBar() {
        circleButton(giftButton, symbol: "gift")
        circleButton(searchButton, symbol: "magnifyingglass")
        for button in [giftButton, searchButton] {
            button.addAction(UIAction { _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                button.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.6) {
                    button.transform = .identity
                }
            }, for: .touchUpInside)
        }
        unmuteButton.setTitle("Unmute", for: .normal)
        unmuteButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        unmuteButton.tintColor = .white
        unmuteButton.addAction(UIAction { [weak self] _ in self?.toggleMute() }, for: .touchUpInside)
        view.addSubview(unmuteButton)
        scrollDown.addAction(UIAction { [weak self] _ in self?.scrollToBottom() }, for: .touchUpInside)
        view.addSubview(scrollDown)

        bottomGlass.shapeProvider = { [weak self] in
            guard let self else { return [] }
            var shapes = [giftButton, unmuteButton, searchButton].map { control in
                let frame = control.convert(control.bounds, to: self.bottomGlass)
                return ChannelGlassView.Shape(rect: frame, cornerRadius: frame.height / 2)
            }
            let frame = view.convert(scrollDown.glassFrame, to: bottomGlass)
            shapes.append(ChannelGlassView.Shape(rect: frame, cornerRadius: frame.height / 2, opacity: scrollDown.glassOpacity))
            return shapes
        }
    }

    private func toggleMute() {
        muted.toggle()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.transition(with: unmuteButton, duration: 0.25, options: [.transitionCrossDissolve]) {
            self.unmuteButton.setTitle(self.muted ? "Unmute" : "Mute", for: .normal)
        }
    }

    private func demoMenu() -> UIMenu {
        UIMenu(title: "Демо", children: [
            UIAction(title: "Новый пост", image: UIImage(systemName: "plus.bubble")) { [weak self] _ in self?.pourNewPost() },
            UIAction(title: "Новый комментатор", image: UIImage(systemName: "person.crop.circle.badge.plus")) { [weak self] _ in
                self?.dropCommenter()
            },
            UIAction(title: "Живые реакции", image: UIImage(systemName: "sparkles"),
                     state: liveReactions ? .on : .off) { [weak self] _ in
                guard let self else { return }
                liveReactions.toggle()
                avatarButton.menu = demoMenu()
            },
            UIAction(title: "Вернуть спойлер", image: UIImage(systemName: "eye.slash")) { [weak self] _ in
                self?.posts.forEach { $0.spoiler?.reset() }
            },
        ])
    }

    private func showHint() {
        guard hint.superview == nil else { return }
        hint.text = "Удерживайте пост · двойной тап · держите ⭐"
        hint.font = .systemFont(ofSize: 12, weight: .semibold)
        hint.textColor = .white
        hint.textAlignment = .center
        hint.backgroundColor = UIColor(white: 0, alpha: 0.45)
        hint.layer.cornerRadius = 13
        hint.clipsToBounds = true
        hint.numberOfLines = 0
        let size = hint.sizeThatFits(CGSize(width: view.bounds.width - 60, height: 100))
        hint.bounds = CGRect(x: 0, y: 0, width: size.width + 24, height: size.height + 10)
        hint.center = CGPoint(x: view.bounds.midX, y: titlePill.frame.maxY + 26)
        hint.alpha = 0
        view.addSubview(hint)
        UIView.animate(withDuration: 0.4) { self.hint.alpha = 1 }
        UIView.animate(withDuration: 0.6, delay: 5) { self.hint.alpha = 0 } completion: { _ in self.hint.removeFromSuperview() }
    }

    // MARK: Posts

    private func initialPosts() -> [ChannelPost] {
        [
            ChannelPost(
                body: "Apple обновила рекомендации по Liquid Glass: стекло должно преломлять контент под собой, а не просто размывать его. Разработчики уже переносят эффект в чаты и плееры.",
                reactions: [("⭐", 3), ("👏", 3300), ("👍", 809), ("🙏", 423), ("❤️", 131), ("🔥", 77), ("😁", 72),
                            ("👌", 22), ("👎", 19), ("😢", 7), ("🤯", 2)].map { ChannelReaction(emoji: $0.0, count: $0.1) },
                views: 101_800, time: "13:48", comments: 70, commenters: Array(people.prefix(6))),
            ChannelPost(
                body: "Интерфейсы с пружинной анимацией кажутся быстрее, чем линейные той же длительности. Совет: держите отклик на касание короче 100 мс и сопровождайте каждое действие тактильным откликом",
                source: "Motion Lab.",
                reactions: [("⭐", 7), ("❤️", 3500), ("👍", 1300), ("🙏", 408), ("🔥", 108), ("😁", 66), ("👏", 38),
                            ("👎", 33), ("👌", 28), ("🤬", 7)].map { ChannelReaction(emoji: $0.0, count: $0.1) },
                views: 88_200, time: "14:21", comments: 67, commenters: Array(people.suffix(6))),
            ChannelPost(
                quote: "«Хорошая анимация не привлекает к себе внимание — она объясняет, что произошло».",
                body: "Что будет в следующем выпуске?",
                spoiler: "Разбираем, как рассыпать сообщение в пыль и засосать его в Dynamic Island — на Metal, в двести строк.",
                reactions: [("❤️", 842), ("🔥", 311), ("👍", 96), ("⭐", 12)].map { ChannelReaction(emoji: $0.0, count: $0.1) },
                views: 41_300, time: "15:02", comments: 24, commenters: Array(people.shuffled().prefix(5))),
        ]
    }

    private func newPosts() -> [ChannelPost] {
        [
            ChannelPost(body: "Прямо сейчас тестируем жидкие реакции на живой ленте. Удерживайте пост — попробуйте сами!",
                        reactions: [ChannelReaction(emoji: "🔥", count: 12), ChannelReaction(emoji: "❤️", count: 5)],
                        views: 1_200, time: "15:40", comments: 3, commenters: Array(people.shuffled().prefix(3))),
            ChannelPost(body: "Совет дня: эффекты — только в ответ на действие. Лента должна оставаться спокойной.",
                        reactions: [ChannelReaction(emoji: "👍", count: 34)],
                        views: 2_900, time: "15:44", comments: 8, commenters: Array(people.shuffled().prefix(4))),
            ChannelPost(body: "Новый выпуск подкаста: как делать эффекты на Metal без просадки FPS. Ссылка в комментариях.",
                        reactions: [ChannelReaction(emoji: "🤯", count: 51), ChannelReaction(emoji: "🔥", count: 20)],
                        views: 4_100, time: "15:51", comments: 12, commenters: Array(people.shuffled().prefix(4))),
        ]
    }

    @discardableResult
    private func addPost(_ post: ChannelPost) -> ChannelPostView {
        let postView = ChannelPostView(post: post)
        postView.onLongPress = { [weak self] in self?.handleLongPress($0, $1) }
        postView.onDoubleTap = { [weak self] in self?.handleDoubleTap($0, $1) }
        postView.onChipTap = { [weak self] in self?.handleChipTap($0, $1) }
        postView.onStarsSent = { [weak self] post, _ in
            guard let self else { return }
            wallpaper.pulse(from: post.bubble.convert(CGPoint(x: post.bubble.bounds.midX, y: post.bubble.bounds.maxY),
                                                      to: wallpaper))
        }
        postView.onComments = { [weak self] in self?.openComments($0) }
        postView.onForward = { [weak self] in self?.handleForward($0, $1) }
        posts.append(postView)
        stack.addArrangedSubview(postView)
        return postView
    }

    // MARK: Reactions

    private func handleLongPress(_ post: ChannelPostView, _ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: view)
        switch gesture.state {
        case .began:
            let picker = ReactionPickerOverlay(in: view, bubble: post.bubble, at: point, emojis: pickerEmojis,
                                               more: moreEmojis)
            picker.onChoice = { [weak self, weak post] choice in
                guard let self, let post else { return }
                self.picker = nil
                switch choice {
                case let .emoji(emoji, from):
                    react(post, emoji: emoji, from: from, size: 30)
                case .delete:
                    delete(post)
                case .dismissed:
                    break
                }
            }
            self.picker = picker
        case .changed:
            picker?.move(to: point)
        default:
            picker?.release()
        }
    }

    /// Flies `emoji` from `point` into its chip on `post`, adding the chip if nobody used it yet.
    private func react(_ post: ChannelPostView, emoji: String, from point: CGPoint, size: CGFloat) {
        let chip: ReactionChip
        let isNew: Bool
        if let existing = post.chips.chip(for: emoji) {
            chip = existing
            isNew = false
        } else {
            chip = post.chips.insertChip(ChannelReaction(emoji: emoji, count: 0))
            isNew = true
        }
        ReactionFlight.fly(emoji, from: point, in: view, liquid: accentLiquid, startSize: size, target: { [weak self, weak chip] in
            guard let self, let chip else { return (point, .zero) }
            return (post.chips.landingPoint(of: chip, in: view), chip.convert(chip.bounds, to: view))
        }, landed: { [weak chip] in
            guard let chip else { return }
            chip.alpha = 1
            if !chip.chosen {
                chip.set(count: chip.count + 1, chosen: true, animated: true)
            }
            chip.gulp(isNew ? 0.3 : 0.2)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        })
    }

    private func handleChipTap(_ post: ChannelPostView, _ chip: ReactionChip) {
        if chip.chosen {
            // Taking it back: the emoji crumbles to dust; an empty chip leaves.
            chip.crumbleEmoji()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if chip.count <= 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { post.chips.remove(chip) }
            } else {
                chip.set(count: chip.count - 1, chosen: false, animated: true)
            }
        } else {
            // A small drop falls into the chip.
            let landing = post.chips.landingPoint(of: chip, in: view)
            react(post, emoji: chip.emoji, from: CGPoint(x: landing.x, y: landing.y - 70), size: 24)
        }
    }

    private func handleDoubleTap(_ post: ChannelPostView, _ point: CGPoint) {
        let origin = post.convert(point, to: view)
        if let chip = post.chips.chip(for: "❤️"), chip.chosen {
            HeartPop.show(at: origin, in: view, target: nil, arrive: nil)
            return
        }
        let chip = post.chips.chip(for: "❤️") ?? post.chips.insertChip(ChannelReaction(emoji: "❤️", count: 0))
        HeartPop.show(at: origin, in: view, target: { [weak self, weak chip] in
            guard let self, let chip else { return origin }
            return post.chips.landingPoint(of: chip, in: view)
        }, arrive: { [weak chip] in
            guard let chip else { return }
            chip.alpha = 1
            chip.set(count: chip.count + 1, chosen: true, animated: true)
            chip.gulp(0.3)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        })
    }

    private func startLiveReactions() {
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1.7, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.liveTick() }
        }
    }

    /// Someone somewhere reacted: a chip on a visible post counts up and a bubble floats out of it.
    private func liveTick() {
        guard liveReactions, picker == nil, Bool.random() || Bool.random() else { return }
        let visible = posts.filter { post in
            guard post.superview != nil, post.alpha > 0.5 else { return false }
            let frame = post.chips.convert(post.chips.bounds, to: view)
            return frame.minY > view.safeAreaInsets.top + 60 && frame.maxY < view.bounds.height - 90
        }
        guard let post = visible.randomElement() else { return }
        let chips = post.chips.chips
        guard !chips.isEmpty else { return }
        // Busier chips get more of the live reactions.
        let weights = chips.map { $0.isStar ? 1 : max(1, Int(log2(Double($0.count + 2)))) }
        var roll = Int.random(in: 0..<weights.reduce(0, +))
        var chip = chips[0]
        for (candidate, weight) in zip(chips, weights) {
            if roll < weight {
                chip = candidate
                break
            }
            roll -= weight
        }
        chip.set(count: chip.count + 1, chosen: chip.chosen, animated: true)
        chip.floatBubble(in: post)
        if Bool.random() {
            post.bumpViews(by: Int.random(in: 100...400))
        }
    }

    // MARK: Comments, forwarding, deleting

    private func openComments(_ post: ChannelPostView) {
        _ = CommentsSheetOverlay(in: view, bubble: post.bubble, buttonPoint: post.commentsPoint(in: view),
                                 count: post.post.comments, people: people)
    }

    private func dropCommenter() {
        let visible = posts.filter { post in
            let frame = post.avatars.convert(post.avatars.bounds, to: view)
            return frame.minY > view.safeAreaInsets.top + 60 && frame.maxY < view.bounds.height - 90
        }
        guard let post = visible.last ?? posts.last else { return }
        let current = Set(post.avatars.people.prefix(3).map(\.name))
        let person = people.first { !current.contains($0.name) } ?? people[0]
        post.addComment(from: person)
    }

    private func handleForward(_ post: ChannelPostView, _ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            forward = ForwardDropOverlay(in: view, button: post.forwardButton, post: post.bubble, people: Array(people.prefix(5)))
        case .changed:
            forward?.move(to: gesture.location(in: view))
        default:
            forward?.release()
            forward = nil
        }
    }

    private func delete(_ post: ChannelPostView) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        vacuum.vacuum(post) { [weak self] in
            guard let self else { return }
            posts.removeAll { $0 === post }
            snapshots.keep(posts)
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                post.isHidden = true
                self.stack.layoutIfNeeded()
            } completion: { _ in
                post.removeFromSuperview()
            }
        }
    }

    // MARK: New posts

    private var distanceFromBottom: CGFloat {
        bottomOffset.y - scroll.contentOffset.y
    }

    private var bottomOffset: CGPoint {
        CGPoint(x: 0, y: max(-scroll.contentInset.top,
                             scroll.contentSize.height + scroll.contentInset.bottom - scroll.bounds.height))
    }

    private func scrollToBottom() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        scroll.setContentOffset(bottomOffset, animated: true)
    }

    /// A new post pours in: liquid wells up from the bottom of its slot, then the bubble fades in over it.
    private func pourNewPost() {
        let model = newPosts()[nextPost % 3]
        nextPost += 1
        let wasAtBottom = distanceFromBottom < 160
        let postView = addPost(model)
        postView.alpha = 0
        view.layoutIfNeeded()
        if wasAtBottom {
            scroll.setContentOffset(bottomOffset, animated: true)
        } else {
            unread += 1
            scrollDown.setUnread(unread)
        }
        wallpaper.pulse(from: postView.bubble.convert(CGPoint(x: 40, y: postView.bubble.bounds.maxY), to: wallpaper))
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        var clock: CFTimeInterval = 0
        var height = Spring1D(0, stiffness: 9, dampingRatio: 0.55)
        var width = Spring1D(0.2, stiffness: 11, dampingRatio: 0.5)
        var revealed = false
        bubbleLiquid.add { [weak self, weak postView] dt in
            guard let self, let postView else { return nil }
            clock += dt
            height.step(toward: 1, deltaTime: dt)
            width.step(toward: 1, deltaTime: dt)
            let frame = postView.bubble.convert(postView.bubble.bounds, to: bubbleLiquid)
            let h = frame.height * max(height.value, 0.04), w = frame.width * max(width.value, 0.12)
            let box = CGRect(x: frame.minX, y: frame.maxY - h, width: w, height: h)
            var shapes = [IslandFluidShape(center: box.center, halfSize: CGSize(width: box.width / 2, height: box.height / 2),
                                           cornerRadius: min(18, box.height / 2), blend: 0)]
            // Drops rising from below into the filling bubble.
            if clock < 0.45 {
                for i in 0..<3 {
                    let rise = CGFloat(clock) * 260 - CGFloat(i) * 22
                    let r = max(0, 9 - CGFloat(clock) * 14) * (1 - CGFloat(i) * 0.2)
                    shapes.append(.circle(center: CGPoint(x: frame.minX + 26 + CGFloat(i) * 34, y: frame.maxY + 34 - rise),
                                          radius: r, blend: 12))
                }
            }
            if !revealed, height.value > 0.82 {
                revealed = true
                UIView.animate(withDuration: 0.2) { postView.alpha = 1 }
                postView.revealContent()
            }
            if clock > 0.5, height.isSettled(at: 1, tolerance: 0.004), width.isSettled(at: 1, tolerance: 0.004) {
                return nil
            }
            return (shapes, [])
        }
    }

    // MARK: Scrolling

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let distance = distanceFromBottom
        scrollDown.setShown(distance > 180)
        if distance < 60, unread > 0 {
            unread = 0
            scrollDown.setUnread(0)
        }
    }
}
