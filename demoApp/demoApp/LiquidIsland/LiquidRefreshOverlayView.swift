//
//  LiquidRefreshOverlayView.swift
//  demoApp
//

import UIKit
import QuartzCore

/// Оверлей pull-to-refresh: капля висит под Dynamic Island, падает на карточку, делится на две половины,
/// обтекает карточку слева и справа, сливается внизу и стекает тонкой линией.
/// Вью пассивна: касания проходят к списку. Состояние получает от контроллера экрана: сдвиг списка и прямоугольник карточки
final class LiquidRefreshOverlayView: UIView {

    /// Сдвиг списка вниз, после которого отпускание запускает обновление, points.
    /// Это смещение списка, а не пальца: UIScrollView сжимает оттягивание примерно вдвое
    static let triggerDistance: CGFloat = 60
    /// Радиус скругления карточки, к которой прижимается капля. Должен совпадать с радиусом карточки на экране
    static let cardCornerRadius: CGFloat = 24

    /// Сдвиг списка вниз, points. Контроллер передаёт его при каждом скролле
    var pullDistance: CGFloat = 0 {
        didSet {
            guard phase == .hidden || phase == .hanging else { return }
            if phase == .hidden, pullDistance > 0 {
                phase = .hanging
            }
            startDisplayLinkIfNeeded()
        }
    }

    /// Прямоугольник карточки в координатах этой вью
    var cardRect: CGRect = .zero

    /// Обновление завершено: линия стекла, список можно вернуть наверх
    var onFinished: (() -> Void)?

    private let dropRadius: CGFloat = 24
    private let dockRadius: CGFloat = 16
    private let gravity: CGFloat = 2600
    /// Длительность обтекания карточки: за это время выполняется «обновление»
    private let flowDuration: CGFloat = 1.3
    /// Стекание линией: сначала капля сужается в нить, затем нить тянется вниз и гаснет
    private let streakDuration: CGFloat = 0.6
    private let streakNarrowDuration: CGFloat = 0.35
    /// Время, за которое перемычка рвётся после отпускания, секунды
    private let tearDuration: CGFloat = 0.12
    /// Половины во время обтекания: тонкая линия ширины lineWidth с хвостом lineTail
    private let lineWidth: CGFloat = 12
    private let lineTail: CGFloat = 70

    private enum Phase {
        case hidden
        /// Капля висит под Dynamic Island и растёт вместе с оттягиванием
        case hanging
        /// Капля отрывается и падает
        case falling
        /// Капля делится на две половины и обтекает карточку слева и справа
        case flowing
        /// Половины сливаются внизу и стекают линией
        case dripping
    }

    private var phase: Phase = .hidden

    /// Сглаженный сдвиг: пружина даёт капле лёгкое колебание при оттягивании и возврате
    private var pullValue: CGFloat = 0
    private var pullVelocity: CGFloat = 0

    /// Центр капли в фазах висения, падения и стекания
    private var dropCenter: CGPoint = .zero
    private var radius: CGFloat = 0
    private var direction = CGPoint(x: 0, y: 1)
    private var elongation: CGFloat = 0
    private var neck: CGFloat = 0
    private var fallVelocity: CGFloat = 0
    private var phaseTime: CGFloat = 0

    /// Две половины во время обтекания: правая идёт по контуру вправо, левая — зеркально влево
    private var rightCenter: CGPoint = .zero
    private var leftCenter: CGPoint = .zero
    private var rightDirection = CGPoint(x: 1, y: 0)
    private var leftDirection = CGPoint(x: -1, y: 0)

    /// Нижний край Dynamic Island: отсюда капля вытекает, а не с самого верха экрана
    private var anchorY: CGFloat = 0

    private let dropLayer = CAShapeLayer()
    private let leftDropLayer = CAShapeLayer()
    private let neckLayer = CAShapeLayer()

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private lazy var linkTarget = OverlayLinkTarget(owner: self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for shapeLayer in [neckLayer, leftDropLayer, dropLayer] {
            shapeLayer.fillColor = UIColor.black.cgColor
            shapeLayer.isHidden = true
            layer.addSublayer(shapeLayer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopDisplayLink()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        anchorY = IslandGeometryProvider.geometry(in: self).frame.maxY
    }

    // MARK: - Публичный интерфейс

    /// Оттянутый список отпущен после порога: капля отрывается от края и падает
    func beginRelease() {
        guard phase == .hanging else { return }
        phase = .falling
        fallVelocity = 0
        phaseTime = 0
        startDisplayLinkIfNeeded()
    }

    // MARK: - Кадры

    private var needsFrames: Bool {
        switch phase {
        case .hidden:
            return false
        case .hanging:
            return abs(pullValue - pullDistance) > 0.05 || abs(pullVelocity) > 0.05
        default:
            return true
        }
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil, needsFrames else { return }
        let link = CADisplayLink(target: linkTarget, selector: #selector(OverlayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = 0
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func handleFrame(_ link: CADisplayLink) {
        let dt: CGFloat
        if lastTimestamp == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = CGFloat(min(max(link.timestamp - lastTimestamp, 1.0 / 240.0), 1.0 / 30.0))
        }
        lastTimestamp = link.timestamp

        advance(by: dt)
        render()
        if !needsFrames {
            stopDisplayLink()
        }
    }

    private func advance(by dt: CGFloat) {
        switch phase {
        case .hidden:
            break

        case .hanging:
            LiquidPhysicsEngine.stepSpring(
                value: &pullValue,
                velocity: &pullVelocity,
                target: pullDistance,
                stiffness: 240,
                damping: 20,
                dt: dt
            )
            radius = dropRadius * min(1, 0.3 + pullValue / 60)
            dropCenter = CGPoint(x: bounds.midX, y: anchorY + radius + pullValue)
            direction = CGPoint(x: 0, y: 1)
            elongation = min(0.6, pullValue / 200)
            neck = 1
            if pullDistance == 0, pullValue < 0.5 {
                pullValue = 0
                pullVelocity = 0
                phase = .hidden
            }

        case .falling:
            phaseTime += dt
            radius = dropRadius
            direction = CGPoint(x: 0, y: 1)
            elongation = min(0.5, 0.3 + fallVelocity / 4000)
            neck = max(0, 1 - phaseTime / tearDuration)
            fallVelocity += gravity * dt
            dropCenter.y += fallVelocity * dt
            // Капля садится на верхний край карточки, когда касается её контура
            if cardRect.height > 0, dropCenter.y + dropRadius >= cardRect.minY {
                startFlow()
            }

        case .flowing:
            phaseTime += dt
            let progress = min(1, phaseTime / flowDuration)
            let eased = progress * progress * (3 - 2 * progress)
            let contour = contourRect
            let s = contourHalfLength(contour) * eased

            // Правая половина идёт по контуру, левая — её зеркальная копия
            rightCenter = contourPoint(s, in: contour)
            leftCenter = CGPoint(x: 2 * contour.midX - rightCenter.x, y: rightCenter.y)

            let ahead = contourPoint(s + 2, in: contour)
            let behind = contourPoint(max(0, s - 2), in: contour)
            rightDirection = normalized(
                CGPoint(x: ahead.x - behind.x, y: ahead.y - behind.y),
                fallback: CGPoint(x: 1, y: 0)
            )
            leftDirection = CGPoint(x: -rightDirection.x, y: rightDirection.y)
            radius = dropRadius
            elongation = 0.6

            if progress >= 1 {
                // Половины сошлись внизу: дальше одна линия
                phase = .dripping
                phaseTime = 0
                fallVelocity = 0
                dropCenter = CGPoint(x: contour.midX, y: contour.maxY)
            }

        case .dripping:
            phaseTime += dt
            fallVelocity += gravity * dt
            dropCenter.y += fallVelocity * dt
            if phaseTime >= streakDuration {
                phase = .hidden
                onFinished?()
            }
        }
    }

    private func startFlow() {
        dropCenter.y = cardRect.minY - dropRadius
        rightCenter = dropCenter
        leftCenter = dropCenter
        rightDirection = CGPoint(x: 1, y: 0)
        leftDirection = CGPoint(x: -1, y: 0)
        phase = .flowing
        phaseTime = 0
        neck = 0
    }

    // MARK: - Контур карточки

    /// Контур, по которому течёт капля: карточка, увеличенная на радиус капли
    private var contourRect: CGRect {
        cardRect.insetBy(dx: -dropRadius, dy: -dropRadius)
    }

    /// Половина контура от верхней середины по правому краю до нижней середины
    private func contourHalfLength(_ rect: CGRect) -> CGFloat {
        let corner = LiquidRefreshOverlayView.cardCornerRadius + dropRadius
        let edge = rect.maxX - corner - rect.midX
        let arc = CGFloat.pi / 2 * corner
        let side = (rect.maxY - corner) - (rect.minY + corner)
        return edge + arc + side + arc + edge
    }

    /// Точка на половине контура на расстоянии s от верхней середины, по часовой стрелке
    private func contourPoint(_ s: CGFloat, in rect: CGRect) -> CGPoint {
        let corner = LiquidRefreshOverlayView.cardCornerRadius + dropRadius
        let edge = rect.maxX - corner - rect.midX
        let arc = CGFloat.pi / 2 * corner
        let side = (rect.maxY - corner) - (rect.minY + corner)
        var distance = max(0, s)

        // Верхний край вправо
        if distance <= edge {
            return CGPoint(x: rect.midX + distance, y: rect.minY)
        }
        distance -= edge

        // Верхний правый угол
        if distance <= arc {
            let angle = -CGFloat.pi / 2 + distance / corner
            return CGPoint(x: rect.maxX - corner + corner * cos(angle), y: rect.minY + corner + corner * sin(angle))
        }
        distance -= arc

        // Правый край вниз
        if distance <= side {
            return CGPoint(x: rect.maxX, y: rect.minY + corner + distance)
        }
        distance -= side

        // Нижний правый угол
        if distance <= arc {
            let angle = distance / corner
            return CGPoint(x: rect.maxX - corner + corner * cos(angle), y: rect.maxY - corner + corner * sin(angle))
        }
        distance -= arc

        // Нижний край влево к середине
        return CGPoint(x: max(rect.midX, rect.maxX - corner - distance), y: rect.maxY)
    }

    private func normalized(_ v: CGPoint, fallback: CGPoint) -> CGPoint {
        let length = hypot(v.x, v.y)
        guard length > 0 else { return fallback }
        return CGPoint(x: v.x / length, y: v.y / length)
    }

    /// Сила перемычки между половинами: 1 — капли перекрываются, 0 — далеко друг от друга
    private func bridgeAmount() -> CGFloat {
        let distance = hypot(rightCenter.x - leftCenter.x, rightCenter.y - leftCenter.y)
        let r = lineWidth / 2
        return min(1, max(0, 1 - (distance - r) / r))
    }

    // MARK: - Отрисовка

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        switch phase {
        case .hidden:
            dropLayer.isHidden = true
            leftDropLayer.isHidden = true
            neckLayer.isHidden = true

        case .hanging, .falling:
            leftDropLayer.isHidden = true
            let body = makeShape(
                center: dropCenter,
                radius: radius,
                direction: direction,
                elongation: elongation,
                dock: CGPoint(x: bounds.midX, y: anchorY),
                neck: neck
            )
            setDrop(dropLayer, body)
            setNeck(LiquidPathBuilder.neckPath(body))
            dropLayer.opacity = 1

        case .flowing:
            // Половины текут тонкими линиями по контуру, хвост тянется за движением
            let bridge = bridgeAmount()
            dropLayer.isHidden = false
            leftDropLayer.isHidden = false
            dropLayer.path = LiquidPathBuilder.streakPath(head: rightCenter, direction: rightDirection, width: lineWidth, tail: lineTail).cgPath
            leftDropLayer.path = LiquidPathBuilder.streakPath(head: leftCenter, direction: leftDirection, width: lineWidth, tail: lineTail).cgPath
            dropLayer.opacity = 1
            leftDropLayer.opacity = 1

            // Перемычка между линиями растёт при сближении и тонкеет при разделении
            let bridgeShape = LiquidShape(
                center: leftCenter,
                direction: rightDirection,
                radius: lineWidth / 2,
                elongation: 0,
                dock: rightCenter,
                dockRadius: lineWidth / 2,
                neck: bridge,
                isVisible: true
            )
            setNeck(LiquidPathBuilder.neckPath(bridgeShape))

        case .dripping:
            // Стекание линией: сначала капля сужается в нить, затем нить вытягивается хвостом и гаснет
            leftDropLayer.isHidden = true
            neckLayer.isHidden = true
            dropLayer.isHidden = false
            let narrow = min(1, phaseTime / streakNarrowDuration)
            let width = dropRadius * 2 * (1 - 0.85 * narrow)
            let tail = min(150, fallVelocity * 0.15)
            dropLayer.path = LiquidPathBuilder.streakPath(head: dropCenter, direction: CGPoint(x: 0, y: 1), width: width, tail: tail).cgPath
            dropLayer.opacity = Float(max(0, 1 - phaseTime / streakDuration))
        }
    }

    private func makeShape(
        center: CGPoint,
        radius: CGFloat,
        direction: CGPoint,
        elongation: CGFloat,
        dock: CGPoint,
        neck: CGFloat
    ) -> LiquidShape {
        LiquidShape(
            center: center,
            direction: direction,
            radius: radius,
            elongation: elongation,
            dock: dock,
            dockRadius: dockRadius,
            neck: neck,
            isVisible: radius > 0.5
        )
    }

    private func setDrop(_ target: CAShapeLayer, _ shape: LiquidShape) {
        target.isHidden = !shape.isVisible
        target.path = LiquidPathBuilder.dropPath(shape).cgPath
    }

    private func setNeck(_ path: UIBezierPath?) {
        if let path {
            neckLayer.isHidden = false
            neckLayer.path = path.cgPath
        } else {
            neckLayer.isHidden = true
        }
    }
}

/// Слабая цель для CADisplayLink: link удерживает цель, поэтому вью напрямую в цели не подходит
private final class OverlayLinkTarget: NSObject {

    private weak var owner: LiquidRefreshOverlayView?

    init(owner: LiquidRefreshOverlayView) {
        self.owner = owner
    }

    @objc func tick(_ link: CADisplayLink) {
        owner?.handleFrame(link)
    }
}
