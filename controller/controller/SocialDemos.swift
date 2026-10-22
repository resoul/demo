//
//  SocialDemos.swift
//  controller
//
//  The "Social" section of the VFX menu (MetalVFXEngine/Social):
//  - Timeline, X-style: new posts drip out of the Dynamic Island as a pill, the write button pours
//    into the composer with its liquid character ring, replies run down the thread's liquid stream,
//    reposts spin and carry the post off, likes pop.
//  - Photo Feed, Instagram-style: living story rings that open into stories (liquid tubes, cube
//    between people), gooey carousel dots, saving into the bookmark, filters washing over as a wave.
//

import UIKit

// MARK: - Timeline (X-style)

final class TimelineDemoViewController: UIViewController {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let fab = UIButton(type: .system)
    private let pill = IslandNewPostsPill()
    private let repostLiquid = FeedLiquidLayer(color: TimelinePalette.repost, gloss: 0.5)
    private let me = ChannelPerson(name: "Вы", hue: 0.55)
    private var nextFresh = 0

    private let people = [
        ChannelPerson(name: "Анна Смирнова", hue: 0.93), ChannelPerson(name: "Михаил Орлов", hue: 0.58),
        ChannelPerson(name: "Катя Лебедева", hue: 0.08), ChannelPerson(name: "Игорь Ким", hue: 0.36),
        ChannelPerson(name: "Ольга Белова", hue: 0.75), ChannelPerson(name: "Дмитрий Волков", hue: 0.15),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Главная"
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = TimelinePalette.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "sparkles"), menu: UIMenu(children: [
            UIAction(title: "Новые посты из острова", image: UIImage(systemName: "arrow.up.circle")) { [weak self] _ in
                self?.announceNewPosts()
            },
        ]))

        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -90),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
        for thread in initialThreads() {
            stack.addArrangedSubview(makeThread(thread))
        }

        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .bold))
        config.cornerStyle = .capsule
        config.baseBackgroundColor = TimelinePalette.accent
        fab.configuration = config
        fab.layer.shadowColor = UIColor.black.cgColor
        fab.layer.shadowOpacity = 0.35
        fab.layer.shadowRadius = 8
        fab.layer.shadowOffset = CGSize(width: 0, height: 4)
        fab.addAction(UIAction { [weak self] _ in self?.compose(replyTo: nil, in: nil) }, for: .touchUpInside)
        view.addSubview(fab)

        repostLiquid.frame = view.bounds
        repostLiquid.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(repostLiquid)
        pill.onTap = { [weak self] in self?.showNewPosts() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let window = view.window {
            pill.install(in: window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.announceNewPosts() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .unspecified
        pill.removeFromSuperview()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        fab.frame = CGRect(x: view.bounds.width - 76, y: view.bounds.height - max(safe.bottom, 16) - 70, width: 58, height: 58)
    }

    // MARK: Content

    private func initialThreads() -> [[TweetModel]] {
        let p = people
        return [
            [TweetModel(author: p[0], handle: "anna_motion", time: "12 мин",
                        text: "Тред о том, почему пружинные анимации ощущаются «дороже» линейных 🧵", replies: 2, reposts: 14,
                        likes: 182, views: 9400),
             TweetModel(author: p[0], handle: "anna_motion", time: "11 мин",
                        text: "1/ Пружина продолжает движение пальца: у неё есть скорость, а не только длительность.",
                        replies: 1, reposts: 3, likes: 64, views: 5100),
             TweetModel(author: p[0], handle: "anna_motion", time: "10 мин",
                        text: "2/ Лёгкий перелёт за цель читается как вес. Без него интерфейс кажется картонным.",
                        replies: 0, reposts: 5, likes: 71, views: 4800)],
            [TweetModel(author: p[1], handle: "orlov_dev", time: "34 мин",
                        text: "Закат с крыши офиса. Иногда стоит оторваться от Metal-шейдеров 🌅", photo: .sunset,
                        replies: 12, reposts: 31, likes: 904, views: 23_000)],
            [TweetModel(author: p[2], handle: "katya_ui", time: "1 ч",
                        text: "Сделали кнопку «написать», которая растекается в редактор. Пользователи тыкают просто чтобы посмотреть 😅",
                        replies: 8, reposts: 22, likes: 410, views: 15_800)],
            [TweetModel(author: p[3], handle: "kim_igor", time: "2 ч",
                        text: "Ночной город для обоев — нарисован целиком в Core Graphics, без единой картинки.", photo: .city,
                        replies: 4, reposts: 9, likes: 233, views: 8700)],
            [TweetModel(author: p[4], handle: "olga_b", time: "3 ч",
                        text: "Счётчик символов кольцом — лучший микро-UX твиттера. Держу пари, вы смотрите на него чаще, чем думаете.",
                        replies: 19, reposts: 40, likes: 1290, views: 41_000)],
        ]
    }

    private func freshThreads() -> [[TweetModel]] {
        let p = people
        return [
            [TweetModel(author: p[5], handle: "volkov_d", time: "сейчас",
                        text: "Только что: новая сборка с жидкими реакциями уже в TestFlight 🚀", replies: 0, reposts: 2, likes: 12,
                        views: 300)],
            [TweetModel(author: p[1], handle: "orlov_dev", time: "сейчас",
                        text: "Аврора над горами — тоже Core Graphics, честно.", photo: .aurora, replies: 1, reposts: 4, likes: 38,
                        views: 900)],
        ]
    }

    private func makeThread(_ models: [TweetModel]) -> ThreadView {
        let thread = ThreadView(models: models)
        thread.onReply = { [weak self, weak thread] tweet in self?.compose(replyTo: tweet, in: thread) }
        thread.onRepost = { [weak self] tweet, on in
            if on {
                self?.carryOff(tweet)
            }
        }
        return thread
    }

    // MARK: New posts from the island

    private func announceNewPosts() {
        guard pill.window != nil else { return }
        pill.show(people: Array(people.shuffled().prefix(3)), count: Int.random(in: 3...14))
    }

    private func showNewPosts() {
        scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: true)
        let models = freshThreads()[nextFresh % 2]
        nextFresh += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let thread = makeThread(models)
            thread.alpha = 0
            thread.transform = CGAffineTransform(translationX: 0, y: -30)
            stack.insertArrangedSubview(thread, at: 0)
            UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.2) {
                self.stack.layoutIfNeeded()
                thread.alpha = 1
                thread.transform = .identity
            }
            thread.tweets.first?.revealContent()
        }
    }

    // MARK: Compose and reply

    private func compose(replyTo tweet: TweetView?, in thread: ThreadView?) {
        let source: CGRect
        if let tweet {
            source = tweet.reply.convert(CGRect(x: -2, y: 4, width: 26, height: 26), to: view)
        } else {
            source = fab.frame
            fab.alpha = 0
        }
        // The island's pill would float over the sheet: hide it while writing.
        pill.isHidden = true
        let sheet = ComposeSheet(in: view, from: source, author: me, replyingTo: tweet?.model.handle)
        sheet.onClose = { [weak self, weak thread] text in
            guard let self else { return }
            pill.isHidden = false
            if tweet == nil {
                fab.alpha = 1
                fab.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.4) {
                    self.fab.transform = .identity
                }
            }
            guard let text, !text.isEmpty else { return }
            let model = TweetModel(author: me, handle: "you", time: "сейчас", text: text)
            if let thread {
                thread.appendReply(model)
            } else {
                scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: true)
                let new = makeThread([model])
                new.alpha = 0
                stack.insertArrangedSubview(new, at: 0)
                UIView.animate(withDuration: 0.5, delay: 0.2, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                    self.stack.layoutIfNeeded()
                    new.alpha = 1
                }
                new.tweets.first?.revealContent()
            }
        }
    }

    // MARK: Repost

    /// A copy of the post shrinks away to your profile while a green drop leaps off the arrows and splashes.
    private func carryOff(_ tweet: TweetView) {
        if let copy = tweet.snapshotView(afterScreenUpdates: false) {
            copy.frame = tweet.convert(tweet.bounds, to: view)
            copy.layer.cornerRadius = 16
            copy.clipsToBounds = true
            copy.backgroundColor = TimelinePalette.panel
            view.addSubview(copy)
            UIView.animate(withDuration: 0.6, delay: 0, options: [.curveEaseIn]) {
                copy.transform = CGAffineTransform(translationX: self.view.bounds.width * 0.42, y: -copy.frame.minY + 40)
                    .scaledBy(x: 0.08, y: 0.08)
                copy.alpha = 0.2
            } completion: { _ in
                copy.removeFromSuperview()
            }
        }
        let origin = tweet.repost.icon.convert(CGPoint(x: 11, y: 11), to: view)
        var t: CGFloat = 0
        let splash = (0..<4).map { _ in CGVector(dx: CGFloat.random(in: -70...70), dy: CGFloat.random(in: -90 ... -20)) }
        view.bringSubviewToFront(repostLiquid)
        repostLiquid.add { dt in
            t += CGFloat(dt)
            guard t < 0.85 else { return nil }
            let rise = min(t / 0.35, 1)
            let eased = 1 - (1 - rise) * (1 - rise)
            let top = CGPoint(x: origin.x, y: origin.y - 70 * eased)
            var shapes: [IslandFluidShape] = []
            var spikes: [IslandFluidSpike] = []
            if t < 0.38 {
                // The drop leaps up, still tied to the arrows by a strand.
                shapes.append(.circle(center: top, radius: 6 + 2 * eased, blend: 0))
                spikes.append(IslandFluidSpike(base: origin, tip: top, baseRadius: 3 * (1 - eased) + 1, tipRadius: 4, blend: 4))
            } else {
                // ...and bursts into droplets.
                let s = (t - 0.38) / 0.47
                for v in splash {
                    shapes.append(.circle(center: CGPoint(x: top.x + v.dx * s, y: top.y + v.dy * s + 120 * s * s),
                                          radius: 4.5 * (1 - s), blend: 0))
                }
            }
            return (shapes, spikes)
        }
    }
}

// MARK: - Photo Feed (Instagram-style)

final class PhotoFeedDemoViewController: UIViewController {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var stories: StoryRingsView!

    private let people = [
        ChannelPerson(name: "Вы", hue: 0.55), ChannelPerson(name: "Анна Смирнова", hue: 0.93),
        ChannelPerson(name: "Михаил Орлов", hue: 0.58), ChannelPerson(name: "Катя Лебедева", hue: 0.08),
        ChannelPerson(name: "Игорь Ким", hue: 0.36), ChannelPerson(name: "Ольга Белова", hue: 0.75),
        ChannelPerson(name: "Дмитрий Волков", hue: 0.15), ChannelPerson(name: "Софья Ли", hue: 0.5),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = PhotoFeedPalette.background
        let wordmark = UILabel()
        wordmark.text = "Photogram"
        wordmark.font = UIFont(name: "SnellRoundhand-Black", size: 28) ?? .systemFont(ofSize: 24, weight: .heavy)
        wordmark.textColor = .white
        navigationItem.titleView = wordmark
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "paperplane"), style: .plain, target: nil, action: nil),
            UIBarButtonItem(image: UIImage(systemName: "heart"), style: .plain, target: nil, action: nil),
        ]

        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])

        let scenes = DemoPhotos.Scene.allCases
        let users = people.enumerated().map { index, person in
            StoryUser(person: person, photos: (0..<(2 + index % 2)).map { scenes[(index + $0) % scenes.count] },
                      seen: index >= 6)
        }
        stories = StoryRingsView(users: users)
        stories.onOpen = { [weak self] index in self?.openStories(at: index) }
        stack.addArrangedSubview(stories)
        let separator = UIView()
        separator.backgroundColor = UIColor(white: 1, alpha: 0.12)
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(separator)

        let posts = [
            PhotoPostModel(author: people[2], location: "Домбай", photos: [.sunset, .aurora, .forest], likes: 1284,
                           caption: "Три вечера в горах. Листайте → и попробуйте фильтры 👇", comments: 48, time: "2 часа назад",
                           showsFilters: true),
            PhotoPostModel(author: people[3], location: "Москва-Сити", photos: [.city, .ocean], likes: 932,
                           caption: "Огни после дождя", comments: 17, time: "5 часов назад"),
            PhotoPostModel(author: people[5], location: "Ботанический сад", photos: [.bloom, .desert, .ocean, .forest], likes: 2410,
                           caption: "Весна наступила раньше календаря 🌸", comments: 96, time: "вчера"),
        ]
        for post in posts {
            stack.addArrangedSubview(PhotoPostView(model: post))
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .unspecified
    }

    private func openStories(at index: Int) {
        // Over the navigation bar too: the story takes the whole screen.
        let host: UIView = navigationController?.view ?? view
        let viewer = StoryViewer(in: host, users: stories.users, start: index) { [weak self, weak host] user in
            guard let self, let host else { return .zero }
            return stories.avatarFrame(user, in: host)
        }
        viewer.onSeen = { [weak self] user in self?.stories.markSeen(user) }
    }
}
