//
//  ViewController.swift
//  demoApp
//
//  Created by resoul on 08.10.2026.
//

import UIKit

// MARK: - Старый демо-экран с прогресс-барами (закомментирован)
//
// class ViewController: UIViewController {
//
//     // Аватар пока закомментирован, сам класс остаётся в AvatarView.swift
//     // private let avatarView = AvatarView()
//
//     private let scrollView = UIScrollView()
//     private let contentStack = UIStackView()
//
//     /// Демо-карточки: анимация, скорость и нужна ли анимация при смене значения
//     private let demos: [(effect: ProgressEffect, speed: Double, animated: Bool)] = [
//         (.plain, 5, true),
//         (.shimmer, 5, true),
//         (.stripes, 3, true),
//         (.liquidWave, 4, true),
//         (.stretch, 8, true),
//         (.pulseDot, 5, true),
//         (.flowGradient, 2, true),
//         (.particles, 6, true),
//         (.plain, 5, false),
//     ]
//
//     override func viewDidLoad() {
//         super.viewDidLoad()
//         setupViews()
//     }
//
//     private func setupViews() {
//         scrollView.translatesAutoresizingMaskIntoConstraints = false
//         view.addSubview(scrollView)
//
//         contentStack.axis = .vertical
//         contentStack.alignment = .leading
//         contentStack.spacing = 28
//         contentStack.translatesAutoresizingMaskIntoConstraints = false
//         scrollView.addSubview(contentStack)
//
//         let header = UILabel()
//         header.text = "Нажмите «Изменить», чтобы посмотреть анимацию"
//         header.font = .systemFont(ofSize: 15)
//         header.textColor = .secondaryLabel
//         header.numberOfLines = 0
//         contentStack.addArrangedSubview(header)
//
//         for demo in demos {
//             contentStack.addArrangedSubview(makeRow(demo))
//         }
//
//         NSLayoutConstraint.activate([
//             scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
//             scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
//             scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//             scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
//
//             contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
//             contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
//             contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 40),
//             contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
//         ])
//     }
//
//     private func makeRow(_ demo: (effect: ProgressEffect, speed: Double, animated: Bool)) -> UIView {
//         let title = UILabel()
//         title.font = .systemFont(ofSize: 15, weight: .semibold)
//         let mode = demo.animated ? "скорость \(Int(demo.speed))" : "без анимации"
//         title.text = "\(demo.effect.title) · \(mode)"
//
//         let bar = ProgressBarView()
//         bar.effect = demo.effect
//         bar.progressSpeed = demo.speed
//         bar.translatesAutoresizingMaskIntoConstraints = false
//
//         // Трек совпадает с заголовком по левому краю, а шарик уходит в отступ bar слева и справа
//         let barContainer = UIView()
//         barContainer.translatesAutoresizingMaskIntoConstraints = false
//         barContainer.addSubview(bar)
//         NSLayoutConstraint.activate([
//             barContainer.widthAnchor.constraint(equalToConstant: 248),
//             barContainer.heightAnchor.constraint(equalToConstant: 50),
//             bar.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor, constant: -36),
//             bar.topAnchor.constraint(equalTo: barContainer.topAnchor),
//             bar.widthAnchor.constraint(equalToConstant: 320),
//             bar.heightAnchor.constraint(equalToConstant: 50),
//         ])
//
//         let animated = demo.animated
//         let button = UIButton(type: .system)
//         button.setTitle("Изменить", for: .normal)
//         button.addAction(UIAction { [weak bar] _ in
//             bar?.setProgress(CGFloat.random(in: 0...1), animated: animated)
//         }, for: .touchUpInside)
//
//         let row = UIStackView(arrangedSubviews: [title, barContainer, button])
//         row.axis = .vertical
//         row.alignment = .leading
//         row.spacing = 8
//         return row
//     }
// }

// MARK: - Лента с реакциями (закомментирована)

#if false
class ViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var cards: [PostCardView] = []
    /// Дуга реакций, пока палец на пилюле
    private var picker: ReactionPickerView?

    private let posts: [FeedPost] = [
        FeedPost(
            tags: ["Networkers", "Resource"],
            author: "@nightMarlin",
            title: "Cold DM template that got me 4 coffee chats this week",
            body: "Short, specific, and I always name one thing they actually worked on. Happy to share the wording if useful.",
            totalReactions: 214,
            reactionCounts: [.insightful: 40, .supportive: 33, .helpful: 26, .celebrate: 9, .inspiring: 4],
            comments: 38,
            discussing: 34
        ),
        FeedPost(
            tags: ["Posters", "Question"],
            author: "@harbouring",
            title: "Portfolio reviewers who switched careers, what did you cut?",
            body: "Mine has three case studies and still feels long. Curious what made the final cut for you.",
            totalReactions: 58,
            reactionCounts: [.insightful: 12, .supportive: 9, .helpful: 5, .celebrate: 2, .inspiring: 1],
            comments: 14,
            discussing: 6
        ),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setupFeed()
    }

    private func setupFeed() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        for post in posts {
            let card = PostCardView(post: post)
            card.onReactionGesture = { [weak self] gesture, tappedCard in
                self?.handleReaction(gesture, on: tappedCard)
            }
            cards.append(card)
            contentStack.addArrangedSubview(card)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    // MARK: - Жесты реакций

    private func handleReaction(_ gesture: UILongPressGestureRecognizer, on card: PostCardView) {
        switch gesture.state {
        case .began:
            startPicking(on: card)
        case .changed:
            picker?.updateSelection(at: gesture.location(in: view))
        case .ended:
            finishPicking(on: card, commit: true)
        case .cancelled, .failed:
            finishPicking(on: card, commit: false)
        default:
            break
        }
    }

    private func startPicking(on card: PostCardView) {
        let pill = card.reactionPill
        let anchor = pill.convert(CGPoint(x: pill.bounds.midX, y: pill.bounds.midY), to: view)

        let picker = ReactionPickerView(anchor: anchor, reactions: ReactionType.allCases, counts: card.reactionCounts)
        picker.frame = view.bounds
        view.addSubview(picker)
        picker.show()
        self.picker = picker

        // Пока открыта дуга, лента не должна ехать за пальцем
        scrollView.panGestureRecognizer.isEnabled = false
    }

    private func finishPicking(on card: PostCardView, commit: Bool) {
        // Иконка вылетает из выбранного кружка, поэтому координату берём до сворачивания дуги
        if commit, let picker, let reaction = picker.selectedReaction, let center = picker.selectedCenter {
            card.react(with: reaction, from: card.convert(center, from: view))
        }
        picker?.dismiss(commit: commit)
        picker = nil

        scrollView.panGestureRecognizer.isEnabled = true
    }
}
#endif

// MARK: - Экран с карточками направлений (закомментирован)

#if false
class ViewController: UIViewController {

    /// Градиенты вместо фото: верхний и нижний цвет
    private let palettes: [[UIColor]] = [
        [UIColor(red: 0.55, green: 0.38, blue: 0.25, alpha: 1), UIColor(red: 0.28, green: 0.17, blue: 0.10, alpha: 1)],
        [UIColor(red: 0.35, green: 0.55, blue: 0.25, alpha: 1), UIColor(red: 0.12, green: 0.30, blue: 0.14, alpha: 1)],
        [UIColor(red: 0.35, green: 0.78, blue: 0.85, alpha: 1), UIColor(red: 0.10, green: 0.45, blue: 0.65, alpha: 1)],
        [UIColor(red: 0.98, green: 0.78, blue: 0.70, alpha: 1), UIColor(red: 0.75, green: 0.45, blue: 0.60, alpha: 1)],
        [UIColor(red: 0.62, green: 0.80, blue: 0.85, alpha: 1), UIColor(red: 0.20, green: 0.42, blue: 0.35, alpha: 1)],
    ]

    /// Наклон в градусах и сдвиг вниз для каждой карточки: ряд неровный, а не ровная линия
    private let tilts: [CGFloat] = [-4, 2, -1, 3, -3]
    private let lifts: [CGFloat] = [5, 2, 0, 3, 4]

    /// Квадратные карточки с тёмным бордером, соседние наезжают друг на друга
    private let cardSize: CGFloat = 74
    private let cardStep: CGFloat = 65
    private let cardBorderWidth: CGFloat = 3
    private let cardCornerRadius: CGFloat = 18

    private let sideInset: CGFloat = 16
    /// Расстояние от верха safe area до верха ряда карточек
    private let rowTop: CGFloat = 40
    /// На сколько поисковая строка заходит на нижнюю часть карточек
    private let searchOverlap: CGFloat = 24

    private var cardViews: [GradientCardView] = []
    private let searchBar = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCards()
        setupSearchBar()
    }

    private func setupCards() {
        for colors in palettes {
            let card = GradientCardView()
            card.colors = colors
            card.layer.cornerRadius = cardCornerRadius
            card.layer.borderWidth = cardBorderWidth
            card.layer.borderColor = UIColor.black.cgColor
            card.clipsToBounds = true
            view.addSubview(card)
            cardViews.append(card)
        }
    }

    private func setupSearchBar() {
        searchBar.backgroundColor = .white
        searchBar.layer.cornerRadius = 26
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        // Добавлена после карточек, поэтому лежит поверх них
        view.addSubview(searchBar)

        let globe = UIImageView(image: UIImage(systemName: "globe.europe.africa.fill"))
        globe.tintColor = .systemGreen
        globe.contentMode = .scaleAspectFit

        let placeholder = UILabel()
        placeholder.text = "Where would you like to go?"
        placeholder.font = .systemFont(ofSize: 16)
        placeholder.textColor = .darkGray

        let mic = UIImageView(image: UIImage(systemName: "mic.fill"))
        mic.tintColor = .systemGray2
        mic.contentMode = .scaleAspectFit

        let content = UIStackView(arrangedSubviews: [globe, placeholder, UIView(), mic])
        content.spacing = 12
        content.alignment = .center
        content.translatesAutoresizingMaskIntoConstraints = false
        searchBar.addSubview(content)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: rowTop + cardSize - searchOverlap),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: sideInset),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -sideInset),
            searchBar.heightAnchor.constraint(equalToConstant: 52),

            content.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor, constant: -16),
            content.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),

            globe.widthAnchor.constraint(equalToConstant: 24),
            globe.heightAnchor.constraint(equalToConstant: 24),
            mic.widthAnchor.constraint(equalToConstant: 20),
            mic.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCards()
    }

    /// Ряд центрируется, каждая карточка сдвинута по вертикали и повернута на свой угол
    private func layoutCards() {
        let rowWidth = cardSize + cardStep * CGFloat(cardViews.count - 1)
        let startX = (view.bounds.width - rowWidth) / 2
        let top = view.safeAreaInsets.top + rowTop

        for (index, card) in cardViews.enumerated() {
            let x = startX + CGFloat(index) * cardStep
            card.transform = .identity
            card.bounds = CGRect(x: 0, y: 0, width: cardSize, height: cardSize)
            card.center = CGPoint(x: x + cardSize / 2, y: top + cardSize / 2 + lifts[index])
            card.transform = CGAffineTransform(rotationAngle: tilts[index] * .pi / 180)
        }
    }
}
#endif

// MARK: - Слайдер поездок (закомментирован)

#if false
class ViewController: UIViewController {

    private let trips: [Trip] = [
        Trip(title: "Trip to Bali", location: "Bali, Indonesia", dates: "28 aug - 03 sep",
             colors: [UIColor(red: 0.35, green: 0.75, blue: 0.85, alpha: 1), UIColor(red: 0.08, green: 0.35, blue: 0.45, alpha: 1)]),
        Trip(title: "Trip to Santorini", location: "Santorini, Greece", dates: "12 sep - 18 sep",
             colors: [UIColor(red: 0.85, green: 0.92, blue: 0.97, alpha: 1), UIColor(red: 0.20, green: 0.40, blue: 0.72, alpha: 1)]),
        Trip(title: "Trip to Kyoto", location: "Kyoto, Japan", dates: "02 oct - 09 oct",
             colors: [UIColor(red: 0.95, green: 0.62, blue: 0.50, alpha: 1), UIColor(red: 0.30, green: 0.15, blue: 0.28, alpha: 1)]),
        Trip(title: "Trip to Iceland", location: "Reykjavik, Iceland", dates: "15 nov - 22 nov",
             colors: [UIColor(red: 0.62, green: 0.78, blue: 0.88, alpha: 1), UIColor(red: 0.18, green: 0.28, blue: 0.38, alpha: 1)]),
        Trip(title: "Trip to Alps", location: "Zermatt, Switzerland", dates: "05 dec - 12 dec",
             colors: [UIColor(red: 0.72, green: 0.86, blue: 0.92, alpha: 1), UIColor(red: 0.28, green: 0.46, blue: 0.38, alpha: 1)]),
    ]

    private var cards: [TripCardView] = []
    /// Позиция карусели: целое число в покое, дробное во время свайпа
    private var position: CGFloat = 0
    private var dragStartPosition: CGFloat = 0

    private var cardWidth: CGFloat { min(view.bounds.width * 0.52, 240) }
    private var cardHeight: CGFloat { cardWidth * 1.45 }
    /// Смещение соседней карточки от центральной: видна лишь её кромка
    private var spacing: CGFloat { view.bounds.width * 0.2 }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        for trip in trips {
            let card = TripCardView(trip: trip)
            view.addSubview(card)
            cards.append(card)
        }

        view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyLayout(position: position)
    }

    /// Центральная карточка крупная, соседние отъезжают назад, в стороны и поворачиваются к центру
    private func applyLayout(position: CGFloat) {
        self.position = position

        for (index, card) in cards.enumerated() {
            let d = CGFloat(index) - position
            let distance = abs(d)
            let direction: CGFloat = d < 0 ? -1 : 1
            let x = distance <= 1 ? d * spacing : direction * (spacing + (distance - 1) * spacing * 0.3)
            // Небольшой наклон и уменьшение соседних карточек; 2D, чтобы порядок слоёв задавали subview
            let tilt = -max(-1, min(1, d)) * 0.12
            let scale = 1 - 0.1 * min(distance, 1)

            card.bounds = CGRect(x: 0, y: 0, width: cardWidth, height: cardHeight)
            card.center = CGPoint(x: view.bounds.midX + x, y: view.bounds.midY)
            card.transform = CGAffineTransform(rotationAngle: tilt).scaledBy(x: scale, y: scale)
            card.alpha = distance > 2 ? 0 : max(0, 1 - 0.25 * distance)
        }

        // Порядок subview задаём по удалённости от центра: самые дальние снизу, центральная сверху
        let farthestFirst = cards.indices.sorted { abs(CGFloat($0) - position) > abs(CGFloat($1) - position) }
        for index in farthestFirst {
            view.bringSubviewToFront(cards[index])
        }
    }

    private func animateTo(_ target: CGFloat) {
        UIView.animate(
            withDuration: 0.55,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.3,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                self.applyLayout(position: target)
            }
        )
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view).x
        let last = CGFloat(cards.count - 1)

        switch pan.state {
        case .began:
            // Останавливаем текущую анимацию, чтобы карусель сразу шла за пальцем
            cards.forEach { $0.layer.removeAllAnimations() }
            dragStartPosition = position
        case .changed:
            var target = dragStartPosition - translation / spacing
            // За крайними карточками карусель тянется, но с сопротивлением
            if target < 0 {
                target *= 0.3
            } else if target > last {
                target = last + (target - last) * 0.3
            }
            applyLayout(position: target)
        case .ended, .cancelled:
            // Скорость свайпа решает, на сколько карточек прокрутить
            let velocity = pan.velocity(in: view).x
            let projected = position - velocity / spacing * 0.2
            animateTo(min(max(round(projected), 0), last))
        default:
            break
        }
    }
}
#endif

// MARK: - Составной экран: главный блок с компонентами и вырезами под кнопку (закомментирован)

#if false
class ViewController: UIViewController {

    private let mainBlock = ShapedView()
    private let photo = GradientCardView()
    private let timerPill = ShapedView()
    private let timerLabel = UILabel()
    private let tripCard = ShapedView()
    private let mapCard = ShapedView()
    private let contourLayer = CAShapeLayer()
    private let routeLayer = CAShapeLayer()
    private let marker = UIView()
    private let expandButton = UIButton(type: .system)

    private let inset: CGFloat = 16
    /// Радиус выреза в углу карты и размер кнопки: кнопка сидит в вырезе с зазором
    private let notchRadius: CGFloat = 34
    private let buttonSize: CGFloat = 52
    private let accent = UIColor(red: 1.0, green: 0.42, blue: 0.22, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupMainBlock()
        setupTimer()
        setupTripCard()
        setupMapCard()
        setupExpandButton()
    }

    private func setupMainBlock() {
        mainBlock.corners = CornerShape(
            topLeft: .rounded(36), topRight: .rounded(36),
            bottomRight: .rounded(36), bottomLeft: .rounded(36)
        )
        view.addSubview(mainBlock)

        // Фото-заглушка: градиент вместо картинки, обрезается формой главного блока
        photo.colors = [
            UIColor(red: 0.62, green: 0.74, blue: 0.62, alpha: 1),
            UIColor(red: 0.40, green: 0.42, blue: 0.38, alpha: 1),
            UIColor(red: 0.20, green: 0.27, blue: 0.20, alpha: 1),
        ]
        mainBlock.addSubview(photo)
    }

    private func setupTimer() {
        timerPill.corners = CornerShape(
            topLeft: .rounded(17), topRight: .rounded(17),
            bottomRight: .rounded(17), bottomLeft: .rounded(17)
        )
        timerPill.backgroundColor = .white

        let icon = UIImageView(image: UIImage(systemName: "timer"))
        icon.tintColor = accent
        timerLabel.text = "00:45:24"
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)

        let row = UIStackView(arrangedSubviews: [icon, timerLabel])
        row.spacing = 6
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        timerPill.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: timerPill.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: timerPill.centerYAnchor),
        ])
        mainBlock.addSubview(timerPill)
    }

    private func setupTripCard() {
        tripCard.corners = CornerShape(
            topLeft: .rounded(24), topRight: .rounded(24),
            bottomRight: .rounded(24), bottomLeft: .rounded(24)
        )
        tripCard.backgroundColor = .white

        let caption = UILabel()
        caption.text = "Current trip"
        caption.font = .systemFont(ofSize: 13)
        caption.textColor = .secondaryLabel

        let title = UILabel()
        title.text = "Ponto de Sao Lorenzo"
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.numberOfLines = 0

        // Аватары наезжают друг на друга, последним идёт счётчик «+12»
        let avatarColors: [UIColor] = [.systemOrange, .systemTeal, .systemIndigo]
        var avatarViews: [UIView] = avatarColors.map { color in
            let avatar = UIView()
            avatar.backgroundColor = color
            avatar.layer.cornerRadius = 15
            avatar.layer.borderWidth = 2
            avatar.layer.borderColor = UIColor.white.cgColor
            avatar.translatesAutoresizingMaskIntoConstraints = false
            avatar.widthAnchor.constraint(equalToConstant: 30).isActive = true
            avatar.heightAnchor.constraint(equalToConstant: 30).isActive = true
            return avatar
        }
        let chip = UILabel()
        chip.text = "+12"
        chip.font = .systemFont(ofSize: 12, weight: .semibold)
        chip.textColor = .white
        chip.backgroundColor = .black
        chip.textAlignment = .center
        chip.layer.cornerRadius = 15
        chip.clipsToBounds = true
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.widthAnchor.constraint(equalToConstant: 38).isActive = true
        chip.heightAnchor.constraint(equalToConstant: 30).isActive = true
        avatarViews.append(chip)

        let avatarRow = UIStackView(arrangedSubviews: avatarViews)
        avatarRow.spacing = -8
        avatarRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [caption, title, avatarRow])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        tripCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: tripCard.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: tripCard.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: tripCard.bottomAnchor, constant: -14),
        ])
        mainBlock.addSubview(tripCard)
    }

    private func setupMapCard() {
        // Правый нижний угол вырезан под кнопку, остальные скруглены
        mapCard.corners = CornerShape(
            topLeft: .rounded(24), topRight: .rounded(24),
            bottomRight: .cut(notchRadius), bottomLeft: .rounded(24)
        )
        mapCard.backgroundColor = UIColor(red: 0.93, green: 0.94, blue: 0.86, alpha: 1)

        // Контурные линии и маршрут рисуются слоями внутри карты, маска их обрезает
        contourLayer.fillColor = nil
        contourLayer.strokeColor = UIColor(white: 0.6, alpha: 0.35).cgColor
        contourLayer.lineWidth = 1
        routeLayer.fillColor = nil
        routeLayer.strokeColor = accent.cgColor
        routeLayer.lineWidth = 3
        routeLayer.lineCap = .round
        mapCard.layer.addSublayer(contourLayer)
        mapCard.layer.addSublayer(routeLayer)

        marker.backgroundColor = .white
        marker.layer.cornerRadius = 17
        marker.layer.shadowColor = UIColor.black.cgColor
        marker.layer.shadowOpacity = 0.15
        marker.layer.shadowRadius = 6
        marker.layer.shadowOffset = CGSize(width: 0, height: 2)
        let pin = UIImageView(image: UIImage(systemName: "location.fill"))
        pin.tintColor = accent
        pin.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        pin.contentMode = .center
        marker.addSubview(pin)
        mapCard.addSubview(marker)

        mainBlock.addSubview(mapCard)
    }

    private func setupExpandButton() {
        expandButton.backgroundColor = accent
        expandButton.tintColor = .white
        expandButton.setImage(
            UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal
        )
        expandButton.layer.cornerRadius = buttonSize / 2
        // Добавлена после карты, поэтому не обрезается её формой
        mainBlock.addSubview(expandButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = view.bounds.width - inset * 2
        let height = width * 1.1
        mainBlock.frame = CGRect(x: inset, y: view.safeAreaInsets.top + inset, width: width, height: height)
        photo.frame = mainBlock.bounds

        timerPill.frame = CGRect(x: width - 14 - 124, y: 14, width: 124, height: 34)
        tripCard.frame = CGRect(x: 14, y: height * 0.5, width: width * 0.56, height: height * 0.5 - 14)
        // Правый край карты отступает так, чтобы кнопка в её углу целиком помещалась в главном блоке
        mapCard.frame = CGRect(x: width * 0.46, y: height * 0.36, width: width - 34 - width * 0.46, height: height * 0.52)

        // Кнопка центрируется в углу карты, где вырез, поэтому зазор вокруг неё одинаковый
        expandButton.frame = CGRect(
            x: mapCard.frame.maxX - buttonSize / 2,
            y: mapCard.frame.maxY - buttonSize / 2,
            width: buttonSize,
            height: buttonSize
        )

        layoutMapContent()
    }

    /// Контуры, маршрут и маркер внутри карты, зависят от её размера
    private func layoutMapContent() {
        let size = mapCard.bounds.size
        contourLayer.frame = mapCard.bounds
        routeLayer.frame = mapCard.bounds

        let contours = UIBezierPath()
        for step in 0..<5 {
            let y = size.height * CGFloat(step) / 4
            contours.move(to: CGPoint(x: -10, y: y))
            contours.addQuadCurve(
                to: CGPoint(x: size.width + 10, y: y + 24),
                controlPoint: CGPoint(x: size.width / 2, y: y - 30)
            )
        }
        contourLayer.path = contours.cgPath

        let route = UIBezierPath()
        route.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.85))
        route.addCurve(
            to: CGPoint(x: size.width * 0.9, y: size.height * 0.2),
            controlPoint1: CGPoint(x: size.width * 0.5, y: size.height * 0.95),
            controlPoint2: CGPoint(x: size.width * 0.55, y: size.height * 0.05)
        )
        routeLayer.path = route.cgPath

        marker.frame = CGRect(x: size.width * 0.42 - 17, y: size.height * 0.36 - 17, width: 34, height: 34)
    }
}
#endif

// MARK: - Карточка места на белом фоне (закомментирована)

#if false
class ViewController: UIViewController {

    private let card = LandmarkCardView(city: "Bangkok", place: "Ratchawararam Temple")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        view.addSubview(card)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = min(view.bounds.width - 64, 280)
        let height = width * 1.1
        card.frame = CGRect(
            x: (view.bounds.width - width) / 2,
            y: (view.bounds.height - height) / 2,
            width: width,
            height: height
        )
    }
}
#endif

// MARK: - Коллекция карточек достопримечательностей

class ViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    private let models: [DestinationCardModel] = [
        DestinationCardModel(
            title: "Bangkok", landmark: "Ratchaworaram Temple",
            image: .gradientPlaceholder([UIColor(red: 0.80, green: 0.86, blue: 0.90, alpha: 1), UIColor(red: 0.12, green: 0.38, blue: 0.52, alpha: 1), UIColor(red: 0.22, green: 0.42, blue: 0.24, alpha: 1)])
        ),
        DestinationCardModel(
            title: "Bergen", landmark: "Fjord Bridge",
            image: .gradientPlaceholder([UIColor(red: 0.85, green: 0.92, blue: 0.96, alpha: 1), UIColor(red: 0.20, green: 0.45, blue: 0.60, alpha: 1), UIColor(red: 0.18, green: 0.36, blue: 0.22, alpha: 1)])
        ),
        DestinationCardModel(
            title: "Kyoto", landmark: "Fushimi Inari",
            image: .gradientPlaceholder([UIColor(red: 0.98, green: 0.80, blue: 0.70, alpha: 1), UIColor(red: 0.70, green: 0.25, blue: 0.20, alpha: 1), UIColor(red: 0.25, green: 0.18, blue: 0.20, alpha: 1)])
        ),
    ]

    /// Ширина карточки относительно экрана: соседние видны по краям
    private let cardWidthRatio: CGFloat = 0.8

    private lazy var collectionView: UICollectionView = {
        let view = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        view.backgroundColor = .white
        view.showsHorizontalScrollIndicator = false
        view.dataSource = self
        view.register(DestinationCardCell.self, forCellWithReuseIdentifier: DestinationCardCell.reuseIdentifier)
        return view
    }()

    /// Одна секция с горизонтальной прокруткой: карточки листаются по одной и центрируются
    private func makeLayout() -> UICollectionViewLayout {
        // Высота группы берётся от ширины по aspectRatio карточки (1.2) с учётом отступов ячейки
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(cardWidthRatio),
            heightDimension: .fractionalWidth(cardWidthRatio * DestinationCardCell.aspectRatio)
        )
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1)
        ))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .groupPagingCentered
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        return UICollectionViewCompositionalLayout(section: section)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    /// Ряд на каждый силуэт: сверху ступенчатый вырез, снизу прямоугольный
    private let shapes: [DestinationShapeConfiguration] = [.stepped, .squareNotch()]

    // MARK: - UICollectionViewDataSource

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        shapes.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        models.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DestinationCardCell.reuseIdentifier, for: indexPath)
        if let cell = cell as? DestinationCardCell {
            cell.cardView.shapeConfiguration = shapes[indexPath.section]
            cell.configure(with: models[indexPath.item])
        }
        return cell
    }

}

// MARK: - Заглушка изображения

extension UIImage {
    /// Градиент вместо фото, пока нет настоящих изображений
    static func gradientPlaceholder(_ colors: [UIColor], size: CGSize = CGSize(width: 400, height: 500)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space, colors: colors.map { $0.cgColor } as CFArray, locations: nil) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }
}
