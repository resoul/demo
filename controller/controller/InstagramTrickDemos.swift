//
//  InstagramTrickDemos.swift
//  controller
//
//  Instagram tricks, one screen each (VFX menu → "Instagram · приёмы"):
//  8. The emoji slider sticker: the emoji swells and wobbles as you drag, then bursts.
//  9. Friend map: avatars that melt together into liquid clusters as you zoom out.
//  10. Profile grid: a photo flies open into the post; hold to peek, slide up to act.
//  11. Notes: thought bubbles blown out of the avatars in the inbox.
//  12. Vanish mode: pull up at the bottom of a chat and it floods dark.
//  13. Reels: jelly paging, hold for 2×, scrub with a frame preview, double-tap hearts.
//  14. A lyrics sticker that fills word by word, karaoke-style.
//

import UIKit
import MapKit

// MARK: - 8. Emoji slider

final class EmojiSliderDemoViewController: TrickPage {
    private let card = UIView()
    private let gradient = CAGradientLayer()
    private let question = UILabel()
    private let track = UIView()
    private let fill = CAGradientLayer()
    private let emoji = UILabel()
    private let average = UIView()
    private var value: CGFloat = 0
    private var wobble = Spring1D(0, stiffness: 10, dampingRatio: 0.3)
    private var link: CADisplayLink?
    private var done = false
    private var burst: [(view: UILabel, velocity: CGVector)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.title = "Эмодзи-слайдер"
        gradient.colors = [UIColor(red: 0.96, green: 0.36, blue: 0.5, alpha: 1).cgColor,
                           UIColor(red: 0.98, green: 0.62, blue: 0.3, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.cornerRadius = 28
        card.layer.addSublayer(gradient)
        question.text = "Насколько вам нравятся жидкие эффекты?"
        question.font = .systemFont(ofSize: 22, weight: .bold)
        question.textColor = .white
        question.numberOfLines = 0
        question.textAlignment = .center
        card.addSubview(question)
        track.backgroundColor = UIColor(white: 1, alpha: 0.35)
        track.layer.cornerRadius = 6
        fill.colors = [UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1).cgColor, UIColor(red: 1, green: 0.3, blue: 0.4, alpha: 1).cgColor]
        fill.startPoint = CGPoint(x: 0, y: 0.5)
        fill.endPoint = CGPoint(x: 1, y: 0.5)
        fill.cornerRadius = 6
        track.layer.addSublayer(fill)
        card.addSubview(track)
        emoji.text = "😍"
        emoji.font = .systemFont(ofSize: 34)
        emoji.sizeToFit()
        card.addSubview(emoji)
        average.alpha = 0
        card.addSubview(average)
        view.addSubview(card)
        let pan = UILongPressGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.minimumPressDuration = 0
        card.addGestureRecognizer(pan)
        var config = UIButton.Configuration.gray()
        config.title = "Ещё раз"
        config.cornerStyle = .capsule
        let again = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.reset() })
        again.tag = 9
        view.addSubview(again)
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showHint("Тяните эмодзи по шкале и отпустите")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        link?.invalidate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width - 48
        card.frame = CGRect(x: 24, y: view.bounds.midY - 150, width: width, height: 250)
        gradient.frame = card.bounds
        question.frame = CGRect(x: 24, y: 30, width: width - 48, height: 70)
        track.frame = CGRect(x: 30, y: 170, width: width - 60, height: 12)
        layoutThumb()
        view.viewWithTag(9)?.frame = CGRect(x: view.bounds.midX - 70, y: card.frame.maxY + 30, width: 140, height: 44)
    }

    private func layoutThumb() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = CGRect(x: 0, y: 0, width: track.bounds.width * value, height: track.bounds.height)
        CATransaction.commit()
        guard !done else { return }
        let x = track.frame.minX + track.bounds.width * value
        emoji.center = CGPoint(x: x, y: track.frame.midY)
        let s = 1 + value * 1.4
        emoji.transform = CGAffineTransform(rotationAngle: wobble.value).scaledBy(x: s, y: s)
    }

    @objc private func drag(_ gesture: UILongPressGestureRecognizer) {
        guard !done else { return }
        let x = gesture.location(in: card).x
        let newValue = min(max((x - track.frame.minX) / track.bounds.width, 0), 1)
        switch gesture.state {
        case .began, .changed:
            // Faster drags tip the emoji further; it wobbles back on a spring.
            wobble.velocity += (newValue - value) * 60
            if Int(newValue * 10) != Int(value * 10) {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            value = newValue
            layoutThumb()
        default:
            if value > 0.05 {
                release()
            }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = min(link.targetTimestamp - link.timestamp, 1.0 / 30)
        wobble.step(toward: 0, deltaTime: dt)
        if !done {
            layoutThumb()
        }
        // Mini emoji falling after the burst.
        for i in burst.indices {
            burst[i].velocity.dy += 900 * dt
            burst[i].view.center.x += burst[i].velocity.dx * dt
            burst[i].view.center.y += burst[i].velocity.dy * dt
            burst[i].view.transform = burst[i].view.transform.rotated(by: CGFloat(dt) * 4)
            burst[i].view.alpha -= CGFloat(dt) * 0.8
        }
        burst.removeAll { item in
            if item.view.alpha <= 0 {
                item.view.removeFromSuperview()
                return true
            }
            return false
        }
    }

    /// The emoji flies up above the card, swells and bursts into little ones; the average shows on the track.
    private func release() {
        done = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let flyer = UILabel()
        flyer.text = emoji.text
        flyer.font = emoji.font
        flyer.sizeToFit()
        flyer.center = card.convert(emoji.center, to: view)
        flyer.transform = emoji.transform
        view.addSubview(flyer)
        emoji.alpha = 0
        let target = CGPoint(x: view.bounds.midX, y: card.frame.minY - 70)
        UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.4) {
            flyer.center = target
            flyer.transform = CGAffineTransform(scaleX: 2.6, y: 2.6)
        } completion: { _ in
            flyer.removeFromSuperview()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            for _ in 0..<18 {
                let mini = UILabel()
                mini.text = "😍"
                mini.font = .systemFont(ofSize: CGFloat.random(in: 18...30))
                mini.sizeToFit()
                mini.center = target
                self.view.addSubview(mini)
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let speed = CGFloat.random(in: 200...520)
                self.burst.append((mini, CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed - 250)))
            }
            self.showAverage()
        }
    }

    private func showAverage() {
        average.subviews.forEach { $0.removeFromSuperview() }
        let x = track.frame.minX + track.bounds.width * 0.74
        average.frame = CGRect(x: x - 40, y: track.frame.maxY + 8, width: 80, height: 56)
        let marker = UIImageView(image: ChannelAvatar.image(for: trickPeople[2], size: 28))
        marker.frame = CGRect(x: 26, y: 0, width: 28, height: 28)
        marker.layer.borderColor = UIColor.white.cgColor
        marker.layer.borderWidth = 2
        marker.layer.cornerRadius = 14
        marker.clipsToBounds = true
        average.addSubview(marker)
        let label = UILabel(frame: CGRect(x: 0, y: 32, width: 80, height: 18))
        label.text = "Среднее"
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        average.addSubview(label)
        let you = UILabel()
        you.text = "Вы: \(Int(value * 100))%"
        you.font = .systemFont(ofSize: 13, weight: .bold)
        you.textColor = .white
        you.sizeToFit()
        you.center = CGPoint(x: track.frame.minX + track.bounds.width * value, y: track.frame.minY - 18)
        you.tag = 5
        card.addSubview(you)
        average.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        UIView.animate(withDuration: 0.5, delay: 0.2, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
            self.average.alpha = 1
            self.average.transform = .identity
        }
    }

    private func reset() {
        done = false
        value = 0
        emoji.alpha = 1
        average.alpha = 0
        card.viewWithTag(5)?.removeFromSuperview()
        layoutThumb()
    }
}

// MARK: - 9. Friend map

final class FriendMapDemoViewController: TrickPage, MKMapViewDelegate {
    private struct Friend {
        let person: ChannelPerson
        let coordinate: CLLocationCoordinate2D
        let avatar: UIImageView
        var offset: IslandSpring
        var hidden = Spring1D(0, stiffness: 14, dampingRatio: 0.9)
    }

    private let map = MKMapView()
    private let overlay = UIView()
    private let liquid = LiquidCanvasView()
    private var friends: [Friend] = []
    private var badges: [UILabel] = []
    private var idle: CFTimeInterval = 0
    private let radius: CGFloat = 23

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Карта друзей"
        map.delegate = self
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        view.addSubview(map)
        overlay.isUserInteractionEnabled = false
        view.addSubview(overlay)
        liquid.liquidColor = .white
        liquid.gloss = 0.5
        liquid.rimWidth = 5
        liquid.onUpdate = { [weak self] dt in self?.step(dt) }
        overlay.addSubview(liquid)
        var random = SplitMix(seed: 11)
        let center = CLLocationCoordinate2D(latitude: 55.751, longitude: 37.618)
        for (index, person) in trickPeople.enumerated() {
            // A few friends close together (they cluster early), the rest spread around the city.
            let spread = index < 4 ? 0.006 : 0.05
            let coordinate = CLLocationCoordinate2D(latitude: center.latitude + (Double(random.next()) - 0.5) * spread,
                                                    longitude: center.longitude + (Double(random.next()) - 0.5) * spread * 1.8)
            let avatar = UIImageView(image: ChannelAvatar.image(for: person, size: radius * 2 - 6))
            avatar.bounds = CGRect(x: 0, y: 0, width: radius * 2 - 6, height: radius * 2 - 6)
            avatar.layer.cornerRadius = radius - 3
            avatar.clipsToBounds = true
            overlay.addSubview(avatar)
            friends.append(Friend(person: person, coordinate: coordinate, avatar: avatar,
                                  offset: IslandSpring(.zero, stiffness: 11, dampingRatio: 0.7)))
        }
        map.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09)),
                      animated: false)
        for (index, (symbol, factor)) in [("plus", 0.4), ("minus", 2.5)].enumerated() {
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold))
            config.cornerStyle = .capsule
            config.baseBackgroundColor = UIColor(white: 0.12, alpha: 0.9)
            config.baseForegroundColor = .white
            let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.zoom(by: factor) })
            button.tag = 100 + index
            view.addSubview(button)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showHint("Отдаляйте карту (щипком или «−») — аватары сольются в капли")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        map.frame = view.bounds
        overlay.frame = view.bounds
        liquid.frame = overlay.bounds
        for index in 0..<2 {
            view.viewWithTag(100 + index)?.frame = CGRect(x: view.bounds.width - 66,
                                                        y: view.bounds.height - view.safeAreaInsets.bottom - 140 + CGFloat(index) * 60,
                                                        width: 50, height: 50)
        }
    }

    private func zoom(by factor: Double) {
        var region = map.region
        region.span.latitudeDelta = min(max(region.span.latitudeDelta * factor, 0.004), 1.2)
        region.span.longitudeDelta = min(max(region.span.longitudeDelta * factor, 0.004), 1.2)
        map.setRegion(region, animated: true)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        idle = 0
        liquid.isPaused = false
    }

    /// Friends whose avatars would overlap form a cluster: they slide together and their liquid rings merge.
    private func clusters(_ points: [CGPoint]) -> [[Int]] {
        var assigned = [Bool](repeating: false, count: points.count)
        var result: [[Int]] = []
        for i in points.indices where !assigned[i] {
            var group = [i]
            assigned[i] = true
            var k = 0
            while k < group.count {
                let p = points[group[k]]
                for j in points.indices where !assigned[j] && points[j].distance(to: p) < radius * 2.4 {
                    assigned[j] = true
                    group.append(j)
                }
                k += 1
            }
            result.append(group)
        }
        return result
    }

    private func step(_ dt: CFTimeInterval) {
        idle += dt
        let points = friends.map { map.convert($0.coordinate, toPointTo: overlay) }
        let groups = clusters(points)
        var shapes: [IslandFluidShape] = []
        var badgeIndex = 0
        var settled = true
        for group in groups {
            let centroid = CGPoint(x: group.map { points[$0].x }.reduce(0, +) / CGFloat(group.count),
                                   y: group.map { points[$0].y }.reduce(0, +) / CGFloat(group.count))
            for (rank, i) in group.enumerated() {
                let target = CGPoint(x: centroid.x - points[i].x, y: centroid.y - points[i].y)
                friends[i].offset.step(toward: group.count > 1 ? target : .zero, deltaTime: dt)
                friends[i].hidden.step(toward: group.count > 1 && rank > 0 ? 1 : 0, deltaTime: dt)
                let position = CGPoint(x: points[i].x + friends[i].offset.position.x, y: points[i].y + friends[i].offset.position.y)
                let grow = group.count > 1 && rank == 0 ? 1 + min(CGFloat(group.count) * 0.06, 0.3) : 1
                shapes.append(.circle(center: position, radius: radius * grow, blend: 20))
                let avatar = friends[i].avatar
                avatar.center = position
                avatar.alpha = 1 - friends[i].hidden.value
                avatar.transform = CGAffineTransform(scaleX: grow, y: grow)
                if friends[i].offset.speed > 1 || friends[i].offset.position.distance(to: group.count > 1 ? target : .zero) > 0.5 {
                    settled = false
                }
            }
            if group.count > 1 {
                overlay.bringSubviewToFront(friends[group[0]].avatar)
                let badge = badgeIndex < badges.count ? badges[badgeIndex] : makeBadge()
                badgeIndex += 1
                badge.text = "+\(group.count - 1)"
                badge.sizeToFit()
                badge.bounds.size = CGSize(width: max(badge.bounds.width + 12, 24), height: 24)
                badge.center = CGPoint(x: centroid.x + radius * 1.05, y: centroid.y - radius * 0.95)
                badge.alpha = 1
                overlay.bringSubviewToFront(badge)
            }
        }
        for index in badgeIndex..<badges.count {
            badges[index].alpha = 0
        }
        liquid.shapes = shapes
        if settled, idle > 0.5 {
            liquid.renderFrame()
            liquid.isPaused = true
        }
    }

    private func makeBadge() -> UILabel {
        let badge = UILabel()
        badge.font = .systemFont(ofSize: 13, weight: .bold)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = UIColor(red: 1, green: 0.25, blue: 0.4, alpha: 1)
        badge.layer.cornerRadius = 12
        badge.clipsToBounds = true
        overlay.addSubview(badge)
        badges.append(badge)
        return badge
    }
}

// MARK: - 10. Profile grid → post, peek

final class GridPeekDemoViewController: TrickPage, UIGestureRecognizerDelegate {
    private let scroll = UIScrollView()
    private var cells: [UIImageView] = []
    private let person = trickPeople[4]
    private var detail: UIView?
    private var openedCell: UIImageView?
    private var peek: (blur: UIVisualEffectView, card: UIView, actions: [UIView], start: CGPoint, cell: UIImageView)?
    private var peekChoice: Int?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.title = "olga_belova"
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        let header = makeHeader()
        scroll.addSubview(header)
        let scenes = DemoPhotos.Scene.allCases
        for index in 0..<18 {
            let cell = UIImageView(image: DemoPhotos.image(scenes[index % scenes.count], size: CGSize(width: 400, height: 400),
                                                          seed: UInt64(index + 20)))
            cell.contentMode = .scaleAspectFill
            cell.clipsToBounds = true
            cell.isUserInteractionEnabled = true
            cell.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open(_:))))
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(hold(_:)))
            hold.minimumPressDuration = 0.3
            cell.addGestureRecognizer(hold)
            scroll.addSubview(cell)
            cells.append(cell)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showHint("Тап — открыть пост. Удержание — превью, потяните вверх к действию", bottom: 60)
    }

    private func makeHeader() -> UIView {
        let header = UIView()
        header.tag = 1
        let avatar = RingAvatar(person: person)
        avatar.frame = CGRect(x: 16, y: 12, width: 90, height: 90)
        header.addSubview(avatar)
        for (index, (number, title)) in [("18", "публикаций"), ("12,4 тыс.", "подписчиков"), ("312", "подписки")].enumerated() {
            let n = UILabel()
            n.text = number
            n.font = .systemFont(ofSize: 17, weight: .bold)
            n.textColor = .white
            n.textAlignment = .center
            let t = UILabel()
            t.text = title
            t.font = .systemFont(ofSize: 13)
            t.textColor = .white
            t.textAlignment = .center
            let x = 120 + CGFloat(index) * 88
            n.frame = CGRect(x: x, y: 34, width: 88, height: 22)
            t.frame = CGRect(x: x, y: 56, width: 88, height: 18)
            header.addSubview(n)
            header.addSubview(t)
        }
        let name = UILabel(frame: CGRect(x: 16, y: 112, width: 300, height: 20))
        name.text = person.name
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.textColor = .white
        header.addSubview(name)
        let bio = UILabel(frame: CGRect(x: 16, y: 132, width: 340, height: 20))
        bio.text = "Фото · горы · море 🌊"
        bio.font = .systemFont(ofSize: 14)
        bio.textColor = .white
        header.addSubview(bio)
        return header
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        scroll.viewWithTag(1)?.frame = CGRect(x: 0, y: 0, width: width, height: 166)
        let side = (width - 4) / 3
        for (index, cell) in cells.enumerated() where cell.transform == .identity {
            cell.frame = CGRect(x: CGFloat(index % 3) * (side + 2), y: 170 + CGFloat(index / 3) * (side + 2), width: side, height: side)
        }
        scroll.contentSize = CGSize(width: width, height: 170 + CGFloat((cells.count + 2) / 3) * (side + 2))
    }

    // MARK: Open

    @objc private func open(_ gesture: UITapGestureRecognizer) {
        guard detail == nil, let cell = gesture.view as? UIImageView else { return }
        openedCell = cell
        let host = navigationController?.view ?? view!
        let detail = UIView(frame: host.bounds)
        detail.backgroundColor = .black
        detail.alpha = 0
        let top = host.safeAreaInsets.top
        let avatar = UIImageView(image: ChannelAvatar.image(for: person, size: 34))
        avatar.frame = CGRect(x: 14, y: top + 54, width: 34, height: 34)
        detail.addSubview(avatar)
        let name = UILabel(frame: CGRect(x: 58, y: top + 60, width: 200, height: 22))
        name.text = "olga_belova"
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.textColor = .white
        detail.addSubview(name)
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)),
                       for: .normal)
        close.tintColor = .white
        close.frame = CGRect(x: 6, y: top, width: 44, height: 44)
        close.addAction(UIAction { [weak self] _ in self?.closeDetail() }, for: .touchUpInside)
        detail.addSubview(close)
        let target = CGRect(x: 0, y: top + 98, width: host.bounds.width, height: host.bounds.width)
        let actions = UILabel(frame: CGRect(x: 14, y: target.maxY + 12, width: 300, height: 30))
        actions.text = "♡   💬   ➤"
        actions.font = .systemFont(ofSize: 24)
        actions.textColor = .white
        detail.addSubview(actions)
        let caption = UILabel(frame: CGRect(x: 14, y: target.maxY + 48, width: host.bounds.width - 28, height: 44))
        caption.text = "Нравится: 1 284\nolga_belova  Свет, который хочется сохранить ✨"
        caption.numberOfLines = 2
        caption.font = .systemFont(ofSize: 14)
        caption.textColor = .white
        detail.addSubview(caption)
        host.addSubview(detail)
        self.detail = detail
        // The cell's photo flies up into the post.
        let flyer = UIImageView(image: cell.image)
        flyer.contentMode = .scaleAspectFill
        flyer.clipsToBounds = true
        flyer.frame = cell.convert(cell.bounds, to: host)
        flyer.tag = 3
        host.addSubview(flyer)
        cell.alpha = 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.2) {
            flyer.frame = target
            detail.alpha = 1
        }
    }

    private func closeDetail() {
        guard let detail, let cell = openedCell, let host = detail.superview, let flyer = host.viewWithTag(3) else { return }
        let back = cell.convert(cell.bounds, to: host)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.2) {
            flyer.frame = back
            detail.alpha = 0
        } completion: { _ in
            cell.alpha = 1
            flyer.removeFromSuperview()
            detail.removeFromSuperview()
            self.detail = nil
        }
    }

    // MARK: Peek

    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        let host = navigationController?.view ?? view!
        switch gesture.state {
        case .began:
            guard let cell = gesture.view as? UIImageView else { return }
            beginPeek(cell, at: gesture.location(in: host), host: host)
        case .changed:
            movePeek(to: gesture.location(in: host))
        default:
            endPeek()
        }
    }

    private func beginPeek(_ cell: UIImageView, at point: CGPoint, host: UIView) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let blur = UIVisualEffectView(effect: nil)
        blur.frame = host.bounds
        host.addSubview(blur)
        let width = host.bounds.width - 40
        let card = UIView(frame: CGRect(x: 20, y: host.bounds.midY - width / 2 - 70, width: width, height: width + 52))
        card.backgroundColor = UIColor(white: 0.1, alpha: 1)
        card.layer.cornerRadius = 18
        card.clipsToBounds = true
        let avatar = UIImageView(image: ChannelAvatar.image(for: person, size: 30))
        avatar.frame = CGRect(x: 12, y: 11, width: 30, height: 30)
        card.addSubview(avatar)
        let name = UILabel(frame: CGRect(x: 50, y: 15, width: 200, height: 22))
        name.text = "olga_belova"
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.textColor = .white
        card.addSubview(name)
        let image = UIImageView(image: cell.image)
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.frame = CGRect(x: 0, y: 52, width: width, height: width)
        card.addSubview(image)
        host.addSubview(card)
        let actions = [("heart.fill", "Нравится"), ("bubble.right.fill", "Ответить"), ("paperplane.fill", "Поделиться")]
            .enumerated().map { index, item -> UIView in
                let pill = UIView(frame: CGRect(x: 20 + CGFloat(index) * (width / 3), y: card.frame.maxY + 16, width: width / 3 - 8, height: 64))
                pill.backgroundColor = UIColor(white: 0.15, alpha: 0.95)
                pill.layer.cornerRadius = 16
                let icon = UIImageView(image: UIImage(systemName: item.0))
                icon.tintColor = .white
                icon.contentMode = .center
                icon.frame = CGRect(x: 0, y: 8, width: pill.bounds.width, height: 26)
                pill.addSubview(icon)
                let label = UILabel(frame: CGRect(x: 0, y: 36, width: pill.bounds.width, height: 18))
                label.text = item.1
                label.font = .systemFont(ofSize: 12, weight: .medium)
                label.textColor = .white
                label.textAlignment = .center
                pill.addSubview(label)
                pill.alpha = 0
                pill.transform = CGAffineTransform(translationX: 0, y: 30)
                host.addSubview(pill)
                return pill
            }
        // The card grows out of the cell over a blurring background.
        let from = cell.convert(cell.bounds, to: host)
        card.transform = CGAffineTransform(translationX: from.midX - card.center.x, y: from.midY - card.center.y)
            .scaledBy(x: from.width / width, y: from.width / width)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.3) {
            blur.effect = UIBlurEffect(style: .systemThinMaterialDark)
            card.transform = .identity
        }
        peek = (blur, card, actions, point, cell)
        peekChoice = nil
    }

    private func movePeek(to point: CGPoint) {
        guard let peek else { return }
        let up = peek.start.y - point.y
        // Sliding up lifts the card and brings the actions in; the one under the finger lights up.
        peek.card.transform = CGAffineTransform(translationX: 0, y: -min(max(up, 0), 120) * 0.6)
        let shown = up > 30
        var choice: Int?
        for (index, pill) in peek.actions.enumerated() {
            UIView.animate(withDuration: 0.3, delay: shown ? 0.04 * Double(index) : 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.3) {
                pill.alpha = shown ? 1 : 0
                pill.transform = shown ? CGAffineTransform(translationX: 0, y: -min(max(up, 0), 120) * 0.6) : CGAffineTransform(translationX: 0, y: 30)
            }
            if shown, point.x >= pill.frame.minX - 4, point.x <= pill.frame.maxX + 4 {
                choice = index
            }
        }
        if choice != peekChoice {
            peekChoice = choice
            if choice != nil {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            for (index, pill) in peek.actions.enumerated() {
                pill.backgroundColor = index == choice ? UIColor(white: 0.32, alpha: 1) : UIColor(white: 0.15, alpha: 0.95)
            }
        }
    }

    private func endPeek() {
        guard let peek else { return }
        self.peek = nil
        let host = peek.blur.superview ?? view!
        if peekChoice == 0 {
            HeartPop.show(at: peek.card.center, in: host, target: nil, arrive: nil)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        let delay = peekChoice == 0 ? 0.7 : 0
        let from = peek.cell.convert(peek.cell.bounds, to: host)
        UIView.animate(withDuration: 0.4, delay: delay, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.2) {
            peek.blur.effect = nil
            let s = from.width / peek.card.bounds.width
            peek.card.transform = CGAffineTransform(translationX: from.midX - peek.card.center.x, y: from.midY - peek.card.center.y)
                .scaledBy(x: s, y: s)
            peek.card.alpha = 0
            peek.actions.forEach { $0.alpha = 0 }
        } completion: { _ in
            peek.blur.removeFromSuperview()
            peek.card.removeFromSuperview()
            peek.actions.forEach { $0.removeFromSuperview() }
        }
    }
}

// MARK: - 11. Notes

final class NotesDemoViewController: TrickPage {
    private struct Note {
        var text: String
        var music: Bool
        var size = IslandSpring(.zero, stiffness: 13, dampingRatio: 0.55)
        var lift = Spring1D(0, stiffness: 12, dampingRatio: 0.55)
        var view: UIView?
    }

    private let row = UIScrollView()
    private let liquid = LiquidCanvasView()
    private var avatars: [UIImageView] = []
    private var notes: [Note?] = []
    private let people = Array(trickPeople.prefix(7))
    private let bubbleColor = UIColor(white: 0.2, alpha: 1)
    private let slot: CGFloat = 92
    private let avatarTop: CGFloat = 72

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.title = "Сообщения"
        row.showsHorizontalScrollIndicator = false
        view.addSubview(row)
        liquid.liquidColor = bubbleColor
        liquid.gloss = 0.25
        liquid.rimWidth = 8
        liquid.onUpdate = { [weak self] dt in self?.step(dt) }
        row.addSubview(liquid)
        for (index, person) in people.enumerated() {
            let avatar = UIImageView(image: ChannelAvatar.image(for: index == 0 ? ChannelPerson(name: "Вы", hue: 0.55) : person, size: 70))
            avatar.isUserInteractionEnabled = true
            avatar.tag = index
            avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapAvatar(_:))))
            row.addSubview(avatar)
            avatars.append(avatar)
            let name = UILabel()
            name.text = index == 0 ? "Ваша заметка" : String(person.name.split(separator: " ").first ?? "")
            name.font = .systemFont(ofSize: 12)
            name.textColor = TrickPalette.secondary
            name.textAlignment = .center
            name.tag = 500 + index
            row.addSubview(name)
            notes.append(nil)
        }
        let plus = UIImageView(image: UIImage(systemName: "plus.circle.fill"))
        plus.tintColor = .white
        plus.backgroundColor = .black
        plus.layer.cornerRadius = 11
        plus.tag = 999
        row.addSubview(plus)
        let list = UIStackView()
        list.axis = .vertical
        list.tag = 9000
        for (i, person) in trickPeople.suffix(5).enumerated() {
            list.addArrangedSubview(TrickViews.chatRow(person, message: ["Ок 👍", "Смотри, что нашла", "Голосовое", "Ха-ха", "До завтра!"][i],
                                                       time: "\(9 + i):4\(i)", unread: i == 1 ? 2 : 0))
        }
        view.addSubview(list)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let seed: [(Int, String, Bool)] = [(1, "Кто в кино? 🍿", false), (2, "Daft Punk — Get Lucky", true), (4, "Работаю 😴", false),
                                           (5, "Море 🌊", false), (6, "Tame Impala — The Less I Know", true)]
        for (k, item) in seed.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + 0.18 * Double(k)) { [weak self] in
                self?.post(item.1, music: item.2, at: item.0)
            }
        }
        showHint("Нажмите на свой аватар, чтобы оставить заметку")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = view.safeAreaInsets.top
        row.frame = CGRect(x: 0, y: top, width: view.bounds.width, height: 190)
        row.contentSize = CGSize(width: CGFloat(people.count) * slot + 16, height: 190)
        liquid.frame = CGRect(origin: .zero, size: row.contentSize)
        for (index, avatar) in avatars.enumerated() {
            avatar.frame = CGRect(x: 8 + CGFloat(index) * slot + (slot - 70) / 2, y: avatarTop, width: 70, height: 70)
            row.viewWithTag(500 + index)?.frame = CGRect(x: 8 + CGFloat(index) * slot, y: avatarTop + 76, width: slot, height: 16)
        }
        row.viewWithTag(999)?.frame = CGRect(x: avatars[0].frame.maxX - 22, y: avatars[0].frame.maxY - 22, width: 22, height: 22)
        view.viewWithTag(9000)?.frame = CGRect(x: 0, y: row.frame.maxY + 6, width: view.bounds.width, height: 5 * 76)
    }

    @objc private func tapAvatar(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag else { return }
        if index == 0 {
            let alert = UIAlertController(title: "Новая заметка", message: "Её увидят друзья на 24 часа", preferredStyle: .alert)
            alert.addTextField { $0.placeholder = "Поделитесь мыслью…" }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Поделиться", style: .default) { [weak self, weak alert] _ in
                let text = alert?.textFields?.first?.text ?? ""
                self?.post(text.isEmpty ? "Привет! 👋" : text, music: false, at: 0)
            })
            present(alert, animated: true)
        } else if notes[index] != nil {
            // Poke a note and it jiggles.
            notes[index]?.lift.velocity += 120
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            liquid.isPaused = false
        }
    }

    /// Builds the note's content and blows the bubble out of the avatar's head.
    private func post(_ text: String, music: Bool, at index: Int) {
        notes[index]?.view?.removeFromSuperview()
        let content = UIView()
        content.isUserInteractionEnabled = false
        if music {
            let bars = UIStackView()
            bars.spacing = 2
            bars.alignment = .bottom
            for i in 0..<3 {
                let bar = UIView()
                bar.backgroundColor = UIColor(red: 0.5, green: 0.9, blue: 0.6, alpha: 1)
                bar.layer.cornerRadius = 1
                bar.translatesAutoresizingMaskIntoConstraints = false
                bar.widthAnchor.constraint(equalToConstant: 3).isActive = true
                bar.heightAnchor.constraint(equalToConstant: 12).isActive = true
                bar.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
                let pulse = CABasicAnimation(keyPath: "transform.scale.y")
                pulse.fromValue = 0.25
                pulse.toValue = 1
                pulse.duration = 0.3 + Double(i) * 0.12
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                bar.layer.add(pulse, forKey: "eq")
                bars.addArrangedSubview(bar)
            }
            bars.frame = CGRect(x: 10, y: 14, width: 13, height: 12)
            content.addSubview(bars)
            let clip = UIView(frame: CGRect(x: 27, y: 8, width: 52, height: 24))
            clip.clipsToBounds = true
            let label = UILabel()
            label.text = text + "     " + text
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .white
            label.sizeToFit()
            label.frame.origin = CGPoint(x: 0, y: 4)
            clip.addSubview(label)
            let marquee = CABasicAnimation(keyPath: "position.x")
            let shift = (text + "     ").size(withAttributes: [.font: label.font!]).width
            marquee.byValue = -shift
            marquee.duration = Double(shift) / 25
            marquee.repeatCount = .infinity
            label.layer.add(marquee, forKey: "marquee")
            content.addSubview(clip)
            content.bounds = CGRect(x: 0, y: 0, width: 86, height: 40)
        } else {
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: 12)
            label.textColor = .white
            label.numberOfLines = 2
            label.textAlignment = .center
            let size = label.sizeThatFits(CGSize(width: 66, height: 40))
            label.frame = CGRect(x: 10, y: 8, width: min(max(size.width, 30), 66), height: min(size.height, 32))
            content.addSubview(label)
            content.bounds = CGRect(x: 0, y: 0, width: label.frame.width + 20, height: label.frame.height + 16)
        }
        content.alpha = 0
        row.addSubview(content)
        var note = Note(text: text, music: music)
        note.view = content
        note.size = IslandSpring(CGPoint(x: 10, y: 10), stiffness: 13, dampingRatio: 0.5)
        note.lift = Spring1D(0, stiffness: 12, dampingRatio: 0.5)
        notes[index] = note
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        liquid.isPaused = false
    }

    private func step(_ dt: CFTimeInterval) {
        var shapes: [IslandFluidShape] = []
        var settled = true
        for index in notes.indices {
            guard var note = notes[index], let content = note.view else { continue }
            let avatar = avatars[index].frame
            let target = CGSize(width: content.bounds.width, height: content.bounds.height)
            note.size.step(toward: CGPoint(x: target.width, y: target.height), deltaTime: dt)
            note.lift.step(toward: 1, deltaTime: dt)
            let lift = note.lift.value
            let w = max(note.size.position.x, 6), h = max(note.size.position.y, 6)
            let center = CGPoint(x: avatar.midX, y: avatar.minY + 6 - (h / 2 + 4) * lift)
            shapes.append(IslandFluidShape(center: center, halfSize: CGSize(width: w / 2, height: h / 2),
                                           cornerRadius: min(16, h / 2), blend: 0))
            // The thought-bubble tail: two little drops between the note and the head.
            let tail = islandSmoothstep(0.6, 1, lift)
            if tail > 0 {
                shapes.append(.circle(center: CGPoint(x: avatar.midX - 12, y: center.y + h / 2 + 4), radius: 4.5 * tail, blend: 0))
                shapes.append(.circle(center: CGPoint(x: avatar.midX - 17, y: center.y + h / 2 + 11), radius: 2.6 * tail, blend: 0))
            }
            content.center = center
            content.alpha = islandSmoothstep(0.7, 0.95, w / max(target.width, 1))
            if note.size.speed > 0.5 || !note.lift.isSettled(at: 1, tolerance: 0.002) {
                settled = false
            }
            notes[index] = note
        }
        liquid.shapes = shapes
        if settled {
            liquid.renderFrame()
            liquid.isPaused = true
        }
    }
}

// MARK: - 12. Vanish mode

final class VanishModeDemoViewController: TrickChatPage, UIScrollViewDelegate {
    private let indicator = UIView()
    private let ring = CAShapeLayer()
    private let hintLabel = UILabel()
    private let banner = UILabel()
    private var armed = false
    private var vanish = false
    private let threshold: CGFloat = 100

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = trickPeople[2].name
        scroll.delegate = self
        sendButton.addAction(UIAction { [weak self] _ in self?.sendTapped() }, for: .touchUpInside)
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = 3
        ring.lineCap = .round
        ring.strokeEnd = 0
        indicator.layer.addSublayer(ring)
        let icon = UIImageView(image: UIImage(systemName: "moon.stars.fill"))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        icon.tag = 1
        indicator.addSubview(icon)
        hintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.textColor = TrickPalette.secondary
        hintLabel.textAlignment = .center
        indicator.addSubview(hintLabel)
        indicator.isUserInteractionEnabled = false
        view.insertSubview(indicator, belowSubview: inputBar)
        banner.font = .systemFont(ofSize: 13, weight: .semibold)
        banner.textColor = .white
        banner.textAlignment = .center
        banner.numberOfLines = 2
        banner.alpha = 0
        view.addSubview(banner)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToBottom(animated: false)
        showHint("Потяните чат вверх у последнего сообщения", bottom: 150)
    }

    override func sendTapped() {
        guard let text = input.text, !text.isEmpty else { return }
        input.text = ""
        let bubble = addBubble(text, outgoing: true)
        styleBubble(bubble, outgoing: true)
        scrollToBottom(animated: true)
    }

    private var overscroll: CGFloat {
        let bottom = max(scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height,
                         -scroll.adjustedContentInset.top)
        return scroll.contentOffset.y - bottom
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let pull = max(overscroll, 0)
        let bottom = inputBar.frame.minY
        indicator.frame = CGRect(x: 0, y: bottom - pull + 6, width: view.bounds.width, height: 80)
        let center = CGPoint(x: indicator.bounds.midX, y: 22)
        ring.path = UIBezierPath(arcCenter: center, radius: 20, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
        indicator.viewWithTag(1)?.center = center
        hintLabel.frame = CGRect(x: 0, y: 48, width: indicator.bounds.width, height: 18)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = min(pull / threshold, 1)
        CATransaction.commit()
        indicator.alpha = min(1, pull / 30)
        let now = pull >= threshold
        hintLabel.text = now ? "Отпустите" : (vanish ? "Проведите вверх, чтобы выключить" : "Проведите вверх для исчезающего режима")
        if now != armed {
            armed = now
            UIImpactFeedbackGenerator(style: now ? .medium : .light).impactOccurred()
        }
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard armed, let window = view.window else { return }
        armed = false
        let origin = inputBar.convert(CGPoint(x: inputBar.bounds.midX, y: 0), to: window)
        let turningOn = !vanish
        LiquidThemeReveal.transition(in: window, from: origin, duration: 0.9, apply: {
            self.vanish = turningOn
            self.applyStyle()
        })
        if turningOn {
            sparkle(from: origin, in: window)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func applyStyle() {
        let background = vanish ? UIColor(red: 0.03, green: 0.02, blue: 0.08, alpha: 1) : TrickPalette.telegramBackground
        view.backgroundColor = background
        inputBar.backgroundColor = background
        input.placeholder = vanish ? "Сообщение исчезнет…" : "Сообщение"
        navigationItem.title = vanish ? "Исчезающий режим" : trickPeople[2].name
        for row in stack.arrangedSubviews {
            guard let bubble = row.subviews.first else { continue }
            let outgoing = bubble.frame.maxX > row.bounds.midX + 20
            styleBubble(bubble, outgoing: outgoing)
        }
        banner.text = "Исчезающий режим включён\nСообщения исчезнут, когда вы закроете чат"
        banner.frame = CGRect(x: 30, y: view.safeAreaInsets.top + 6, width: view.bounds.width - 60, height: 40)
        banner.alpha = vanish ? 1 : 0
        scroll.contentInset.top = vanish ? 50 : 0
    }

    private func styleBubble(_ bubble: UIView, outgoing: Bool) {
        if vanish {
            bubble.backgroundColor = outgoing ? UIColor(red: 0.5, green: 0.25, blue: 0.95, alpha: 1) : UIColor(white: 0.14, alpha: 1)
            bubble.layer.borderWidth = outgoing ? 0 : 1
            bubble.layer.borderColor = UIColor(white: 1, alpha: 0.15).cgColor
        } else {
            bubble.backgroundColor = outgoing ? TrickPalette.outgoing : TrickPalette.incoming
            bubble.layer.borderWidth = 0
        }
    }

    /// Little stars rising from the bottom as the dark floods in.
    private func sparkle(from point: CGPoint, in window: UIWindow) {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: window.bounds.midX, y: point.y)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: window.bounds.width, height: 1)
        let cell = CAEmitterCell()
        cell.contents = TrickViews.emojiImage("✦", size: 24).cgImage
        cell.color = UIColor(red: 0.8, green: 0.7, blue: 1, alpha: 1).cgColor
        cell.birthRate = 60
        cell.lifetime = 2
        cell.velocity = 260
        cell.velocityRange = 160
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = 0.5
        cell.scale = 0.4
        cell.scaleRange = 0.3
        cell.alphaSpeed = -0.5
        emitter.emitterCells = [cell]
        window.layer.addSublayer(emitter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { emitter.removeFromSuperlayer() }
    }
}

// MARK: - 13. Reels

private final class ReelPage: UIView {
    let image = UIImageView()
    let progressTrack = UIView()
    let progressFill = UIView()
    let heart = UIImageView(image: UIImage(systemName: "heart"))
    var progress: CGFloat = 0
    let duration: CGFloat = 30

    init(scene: DemoPhotos.Scene, person: ChannelPerson, caption: String, seed: Int) {
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = .black
        image.image = DemoPhotos.image(scene, size: CGSize(width: 540, height: 960), seed: UInt64(seed))
        image.contentMode = .scaleAspectFill
        addSubview(image)
        let shade = CAGradientLayer()
        shade.colors = [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.6).cgColor]
        shade.locations = [0.6, 1]
        shade.name = "shade"
        layer.addSublayer(shade)
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 18
        column.alignment = .center
        column.tag = 1
        for (symbol, count) in [("heart", "48,2 тыс."), ("bubble.right", "1 204"), ("paperplane", "3 310")] {
            let icon = symbol == "heart" ? heart : UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = .white
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)
            let label = UILabel()
            label.text = count
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .white
            let item = UIStackView(arrangedSubviews: [icon, label])
            item.axis = .vertical
            item.alignment = .center
            item.spacing = 4
            column.addArrangedSubview(item)
        }
        addSubview(column)
        let author = UILabel()
        author.text = person.name.lowercased().replacingOccurrences(of: " ", with: "_") + "  ·  Подписаться"
        author.font = .systemFont(ofSize: 14, weight: .semibold)
        author.textColor = .white
        author.tag = 2
        addSubview(author)
        let text = UILabel()
        text.text = caption
        text.font = .systemFont(ofSize: 14)
        text.textColor = .white
        text.numberOfLines = 2
        text.tag = 3
        addSubview(text)
        progressTrack.backgroundColor = UIColor(white: 1, alpha: 0.3)
        progressFill.backgroundColor = .white
        progressTrack.addSubview(progressFill)
        addSubview(progressTrack)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var trackHeight: CGFloat = 2 {
        didSet { setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.first { $0.name == "shade" }?.frame = bounds
        let safe = window?.safeAreaInsets ?? .zero
        viewWithTag(1)?.frame = CGRect(x: bounds.width - 64, y: bounds.height - safe.bottom - 330, width: 54, height: 230)
        viewWithTag(2)?.frame = CGRect(x: 16, y: bounds.height - safe.bottom - 96, width: bounds.width - 90, height: 20)
        viewWithTag(3)?.frame = CGRect(x: 16, y: bounds.height - safe.bottom - 72, width: bounds.width - 90, height: 40)
        progressTrack.frame = CGRect(x: 0, y: bounds.height - safe.bottom - 20 - trackHeight / 2, width: bounds.width, height: trackHeight)
        progressTrack.layer.cornerRadius = trackHeight / 2
        updateFrame()
    }

    /// The "video": a slow push in and drift, driven by `progress`.
    func updateFrame() {
        let p = progress
        let s = 1.08 + 0.18 * sin(p * .pi)
        image.bounds = bounds
        image.center = CGPoint(x: bounds.midX + (p - 0.5) * 40, y: bounds.midY + sin(p * .pi * 2) * 12)
        image.transform = CGAffineTransform(scaleX: s, y: s)
        progressFill.frame = CGRect(x: 0, y: 0, width: progressTrack.bounds.width * p, height: progressTrack.bounds.height)
    }
}

final class ReelsDemoViewController: TrickPage, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let pager = UIScrollView()
    private var pages: [ReelPage] = []
    private var link: CADisplayLink?
    private var speed: CGFloat = 1
    private let speedPill = UILabel()
    private var jelly = Spring1D(0, stiffness: 14, dampingRatio: 0.45)
    private var lastOffset: CGFloat = 0
    private var lastTime: CFTimeInterval = 0
    private let preview = UIImageView()
    private let previewTime = UILabel()
    private var scrubbing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        pager.isPagingEnabled = true
        pager.showsVerticalScrollIndicator = false
        pager.contentInsetAdjustmentBehavior = .never
        pager.delegate = self
        view.addSubview(pager)
        let captions = ["Рассвет в горах за 30 секунд 🌄", "Океан дышит 🌊", "Город, который не спит ✨", "Лес после дождя 🌲",
                        "Северное сияние вживую 💚"]
        let scenes: [DemoPhotos.Scene] = [.sunset, .ocean, .city, .forest, .aurora]
        for (index, scene) in scenes.enumerated() {
            let page = ReelPage(scene: scene, person: trickPeople[index], caption: captions[index], seed: index + 40)
            pager.addSubview(page)
            pages.append(page)
        }
        speedPill.text = "  2×  ▶▶  "
        speedPill.font = .systemFont(ofSize: 15, weight: .bold)
        speedPill.textColor = .white
        speedPill.backgroundColor = UIColor(white: 0, alpha: 0.5)
        speedPill.layer.cornerRadius = 17
        speedPill.clipsToBounds = true
        speedPill.alpha = 0
        view.addSubview(speedPill)
        preview.contentMode = .scaleAspectFill
        preview.clipsToBounds = true
        preview.layer.cornerRadius = 10
        preview.layer.borderColor = UIColor.white.cgColor
        preview.layer.borderWidth = 2
        preview.alpha = 0
        view.addSubview(preview)
        previewTime.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        previewTime.textColor = .white
        previewTime.textAlignment = .center
        previewTime.alpha = 0
        view.addSubview(previewTime)

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(hold(_:)))
        hold.minimumPressDuration = 0.35
        hold.delegate = self
        pager.addGestureRecognizer(hold)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        pager.addGestureRecognizer(doubleTap)
        let scrub = UIPanGestureRecognizer(target: self, action: #selector(scrub(_:)))
        scrub.delegate = self
        view.addGestureRecognizer(scrub)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.alpha = 0.6
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showHint("Свайп вверх · удержание — 2× · двойной тап — ❤️ · тяните полоску внизу", bottom: 150)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.alpha = 1
        link?.invalidate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pager.frame = view.bounds
        for (index, page) in pages.enumerated() where page.transform == .identity {
            page.frame = CGRect(x: 0, y: CGFloat(index) * view.bounds.height, width: view.bounds.width, height: view.bounds.height)
        }
        pager.contentSize = CGSize(width: view.bounds.width, height: CGFloat(pages.count) * view.bounds.height)
        speedPill.sizeToFit()
        speedPill.bounds.size.height = 34
        speedPill.center = CGPoint(x: view.bounds.midX, y: view.safeAreaInsets.top + 60)
    }

    private var currentIndex: Int {
        min(max(Int((pager.contentOffset.y / max(view.bounds.height, 1)).rounded()), 0), pages.count - 1)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let y = touch.location(in: view).y
        let barZone = y > view.bounds.height - view.safeAreaInsets.bottom - 60
        // The bottom strip scrubs; everywhere else pages and holds.
        return gestureRecognizer is UIPanGestureRecognizer ? barZone : !barZone
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan.view === view else { return true }
        let v = pan.velocity(in: view)
        return abs(v.x) > abs(v.y)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = min(link.targetTimestamp - link.timestamp, 1.0 / 30)
        let page = pages[currentIndex]
        if !scrubbing {
            page.progress = (page.progress + CGFloat(dt) * speed / page.duration).truncatingRemainder(dividingBy: 1)
        }
        page.updateFrame()
        // Jelly: pages stretch along the swipe and wobble back when it stops.
        jelly.step(toward: 0, deltaTime: dt)
        let k = max(-0.08, min(0.08, jelly.value))
        for p in pages {
            p.transform = CGAffineTransform(scaleX: 1 - abs(k) * 0.5, y: 1 + abs(k))
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let now = CACurrentMediaTime()
        let dt = max(now - lastTime, 1.0 / 120)
        let v = (scrollView.contentOffset.y - lastOffset) / CGFloat(dt)
        lastOffset = scrollView.contentOffset.y
        lastTime = now
        if scrollView.isDragging || scrollView.isDecelerating {
            jelly.velocity += max(-6, min(6, v / 4000))
        }
    }

    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        let on = gesture.state == .began || gesture.state == .changed
        guard (speed == 2) != on else { return }
        speed = on ? 2 : 1
        UIImpactFeedbackGenerator(style: on ? .medium : .light).impactOccurred()
        speedPill.transform = on ? CGAffineTransform(scaleX: 0.6, y: 0.6) : .identity
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
            self.speedPill.alpha = on ? 1 : 0
            self.speedPill.transform = .identity
        }
    }

    @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
        HeartPop.show(at: gesture.location(in: view), in: view, target: nil, arrive: nil)
        let heart = pages[currentIndex].heart
        heart.image = UIImage(systemName: "heart.fill")
        heart.tintColor = PhotoFeedPalette.like
        heart.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.7) {
            heart.transform = .identity
        }
    }

    /// Dragging along the bottom bar scrubs; a bubble above the finger shows the frame there.
    @objc private func scrub(_ gesture: UIPanGestureRecognizer) {
        let page = pages[currentIndex]
        let x = gesture.location(in: view).x
        let p = min(max(x / view.bounds.width, 0), 0.999)
        switch gesture.state {
        case .began:
            scrubbing = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIView.animate(withDuration: 0.2) {
                page.trackHeight = 8
                page.layoutIfNeeded()
                self.preview.alpha = 1
                self.previewTime.alpha = 1
            }
            fallthrough
        case .changed:
            page.progress = p
            preview.image = page.image.image
            preview.bounds = CGRect(x: 0, y: 0, width: 90, height: 150)
            // The bubble shows the part of the shot the "video" is on at that moment.
            preview.layer.contentsRect = CGRect(x: 0.15 + (p - 0.5) * 0.2, y: 0.1, width: 0.7, height: 0.8)
            let barY = view.bounds.height - view.safeAreaInsets.bottom - 20
            preview.center = CGPoint(x: min(max(x, 55), view.bounds.width - 55), y: barY - 110)
            let seconds = Int(p * page.duration)
            previewTime.text = String(format: "0:%02d / 0:30", seconds)
            previewTime.frame = CGRect(x: preview.frame.minX - 20, y: preview.frame.maxY + 4, width: 130, height: 18)
        default:
            scrubbing = false
            UIView.animate(withDuration: 0.25) {
                page.trackHeight = 2
                page.layoutIfNeeded()
                self.preview.alpha = 0
                self.previewTime.alpha = 0
            }
        }
    }
}

// MARK: - 14. Lyrics sticker

final class LyricsStickerDemoViewController: TrickPage {
    private struct Line {
        let words: [String]
        let durations: [Double]
        var total: Double { durations.reduce(0, +) }
    }

    private let background = FluidMeshGradientView()
    private let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let linesContainer = UIView()
    private var dimLabels: [UILabel] = []
    private var brightLabels: [UILabel] = []
    private var masks: [CALayer] = []
    private var lines: [Line] = []
    private var current = 0
    private var lineTime: Double = 0
    private var link: CADisplayLink?
    private let font = UIFont.systemFont(ofSize: 18, weight: .heavy)

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Стикер с текстом песни"
        background.colors = [UIColor(red: 0.95, green: 0.4, blue: 0.3, alpha: 1), UIColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1),
                             UIColor(red: 0.98, green: 0.7, blue: 0.3, alpha: 1), UIColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1)]
        background.speed = 0.6
        view.addSubview(background)
        card.layer.cornerRadius = 26
        card.clipsToBounds = true
        view.addSubview(card)
        let art = UIImageView(image: DemoPhotos.image(.city, size: CGSize(width: 120, height: 120)))
        art.frame = CGRect(x: 16, y: 16, width: 48, height: 48)
        art.layer.cornerRadius = 8
        art.clipsToBounds = true
        card.contentView.addSubview(art)
        let title = UILabel(frame: CGRect(x: 76, y: 18, width: 200, height: 22))
        title.text = "Ночной город"
        title.font = .systemFont(ofSize: 16, weight: .bold)
        title.textColor = .white
        card.contentView.addSubview(title)
        let artist = UILabel(frame: CGRect(x: 76, y: 40, width: 200, height: 20))
        artist.text = "Neon Waves"
        artist.font = .systemFont(ofSize: 14)
        artist.textColor = UIColor(white: 1, alpha: 0.7)
        card.contentView.addSubview(artist)
        linesContainer.clipsToBounds = true
        card.contentView.addSubview(linesContainer)
        let text = [
            "Город горит огнями в ночи",
            "Мы бежим сквозь неоновый дождь",
            "Каждый свет — это чей-то звонок",
            "И ты рядом, и всё хорошо",
            "Пусть до утра не кончится ночь",
            "Город горит огнями в ночи",
        ]
        var random = SplitMix(seed: 3)
        lines = text.map { line in
            let words = line.split(separator: " ").map(String.init)
            return Line(words: words, durations: words.map { _ in 0.32 + Double(random.next()) * 0.3 })
        }
        for line in lines {
            let joined = line.words.joined(separator: " ")
            let dim = UILabel()
            dim.text = joined
            dim.font = font
            dim.textColor = UIColor(white: 1, alpha: 0.35)
            let bright = UILabel()
            bright.text = joined
            bright.font = font
            bright.textColor = .white
            let mask = CALayer()
            mask.backgroundColor = UIColor.black.cgColor
            bright.layer.mask = mask
            linesContainer.addSubview(dim)
            linesContainer.addSubview(bright)
            dimLabels.append(dim)
            brightLabels.append(bright)
            masks.append(mask)
        }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        link?.invalidate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        background.frame = view.bounds
        let width = view.bounds.width - 32
        card.frame = CGRect(x: 16, y: view.bounds.midY - 140, width: width, height: 260)
        linesContainer.frame = CGRect(x: 16, y: 80, width: width - 32, height: 170)
        layoutLines(animated: false)
    }

    /// Lines stack around the current one: it is big and centered, the others dim and smaller.
    private func layoutLines(animated: Bool) {
        let apply = {
            for index in self.lines.indices {
                let offset = CGFloat(index - self.current)
                let y = self.linesContainer.bounds.height * 0.35 + offset * 38
                let s: CGFloat = index == self.current ? 1 : 0.82
                for label in [self.dimLabels[index], self.brightLabels[index]] {
                    label.transform = .identity
                    label.sizeToFit()
                    label.frame.origin = CGPoint(x: 0, y: y - label.bounds.height / 2)
                    label.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
                    label.center = CGPoint(x: 0, y: y)
                    label.transform = CGAffineTransform(scaleX: s, y: s)
                    label.alpha = abs(offset) > 1.5 ? 0 : (index == self.current ? 1 : 0.6)
                }
            }
        }
        if animated {
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.2, animations: apply)
        } else {
            apply()
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = min(link.targetTimestamp - link.timestamp, 1.0 / 30)
        lineTime += dt
        let line = lines[current]
        // How far the fill has gone: whole words before the current one, then part of it.
        var elapsed = lineTime
        var text = ""
        var filled: CGFloat = 0
        for (index, word) in line.words.enumerated() {
            let before = (text + (index > 0 ? " " : "")) as NSString
            let after = (text + (index > 0 ? " " : "") + word) as NSString
            let x0 = before.size(withAttributes: [.font: font]).width
            let x1 = after.size(withAttributes: [.font: font]).width
            let d = line.durations[index]
            if elapsed >= d {
                filled = x1
                elapsed -= d
            } else {
                filled = x0 + (x1 - x0) * CGFloat(max(elapsed, 0) / d)
                elapsed = -1
                break
            }
            text = after as String
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in masks.indices {
            let label = brightLabels[index]
            let width = index < current ? label.bounds.width : (index == current ? filled : 0)
            masks[index].frame = CGRect(x: 0, y: 0, width: width, height: label.bounds.height)
        }
        CATransaction.commit()
        if lineTime > line.total + 0.5 {
            lineTime = 0
            current = (current + 1) % lines.count
            if current == 0 {
                masks.forEach { $0.frame.size.width = 0 }
            }
            UISelectionFeedbackGenerator().selectionChanged()
            layoutLines(animated: true)
        }
    }
}
