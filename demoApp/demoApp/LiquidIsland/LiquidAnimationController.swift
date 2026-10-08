//
//  LiquidAnimationController.swift
//  demoApp
//

import UIKit
import QuartzCore

/// Управляет состоянием капли и переходами между сценариями: захват, притяжение, возврат, поглощение и появление новой капли.
/// Физику считает `LiquidPhysicsEngine`, форму рисует `LiquidIslandView`. Контроллер только связывает их через CADisplayLink
final class LiquidAnimationController {

    private enum Phase {
        /// Капли нет: она появится по касанию или через паузу после поглощения
        case hidden
        /// Капля появляется в доме с упругим ростом
        case appearing
        /// Капля лежит в доме
        case resting
        /// Палец держит каплю
        case dragging
        /// Палец отпустил далеко от острова: пружина возвращает каплю домой
        case returning
        /// Капля поглощается островом
        case absorbing
    }

    /// Параметры эффекта. Читаются каждый кадр, поэтому правки из debug-панели действуют сразу
    var configuration = LiquidIslandConfiguration()

    /// Форма на кадр; вызывается, пока анимация активна, и при каждом изменении layout
    var onFrame: ((LiquidShape) -> Void)?
    /// Капля поглощена: вью показывает отклик острова
    var onAbsorbed: (() -> Void)?

    /// Длительность пути капли к острову при поглощении, секунды
    private let absorbDuration: CGFloat = 0.5
    /// Пауза между поглощением и появлением новой капли, секунды
    private let respawnDelay: CGFloat = 0.9
    /// Минимальный радиус, в котором палец захватывает каплю, points
    private let minimumGrabRadius: CGFloat = 56

    private var island = IslandGeometry(frame: .zero, isSystemIsland: true)
    private var bounds: CGRect = .zero

    private var phase: Phase = .hidden
    /// Центр капли. Во время удержания он идёт за пальцем, в остальных фазах двигается пружиной
    private var center = SpringState(position: .zero)
    /// Смещение капли к острову при удержании: пружина догоняет точку притяжения
    private var pull = SpringState(position: .zero)
    private var scale: CGFloat = 0
    private var scaleVelocity: CGFloat = 0

    /// Точка пальца и смещение капли относительно неё в момент захвата, чтобы капля не прыгала
    private var pointer: CGPoint = .zero
    private var grabOffset: CGPoint = .zero

    private var absorbStart: CGPoint = .zero
    private var absorbProgress: CGFloat = 0
    /// Время до появления новой капли; 0 — отсчёта нет
    private var respawnTimer: CGFloat = 0

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private lazy var linkTarget = DisplayLinkTarget(owner: self)

    deinit {
        stopDisplayLink()
    }

    // MARK: - Публичный интерфейс

    /// Создаёт первую каплю в доме. Вызывать после того, как известна геометрия
    func start() {
        guard phase == .hidden, respawnTimer == 0 else { return }
        spawn(at: home)
    }

    /// Обновляет геометрию острова и границы. Капля, которая лежит в доме, переедет к новому месту пружиной
    func updateLayout(island: IslandGeometry, bounds: CGRect) {
        self.island = island
        self.bounds = bounds
        startDisplayLinkIfNeeded()
        emitFrame()
    }

    /// Можно ли захватить каплю в точке касания. Если капли нет, касание создаёт новую
    func canGrab(at point: CGPoint) -> Bool {
        if phase == .hidden { return true }
        let grabRadius = max(minimumGrabRadius, configuration.dropRadius * 2)
        return hypot(point.x - center.position.x, point.y - center.position.y) <= grabRadius
    }

    /// Палец захватил каплю или создал новую. Работает и во время возврата, и во время поглощения
    func beginGrab(at point: CGPoint) {
        if phase == .hidden {
            spawn(at: point)
            grabOffset = .zero
        } else {
            grabOffset = CGPoint(x: center.position.x - point.x, y: center.position.y - point.y)
        }
        pointer = point
        pull = SpringState(position: .zero)
        absorbProgress = 0
        respawnTimer = 0
        phase = .dragging
        startDisplayLinkIfNeeded()
    }

    /// Палец двигается
    func moveGrab(to point: CGPoint) {
        guard phase == .dragging else { return }
        pointer = point
    }

    /// Палец отпустил, либо жест отменён. Близко к острову — поглощение, далеко — возврат домой
    func endGrab() {
        guard phase == .dragging else { return }
        let distance = LiquidPhysicsEngine.surfaceDistance(
            from: center.position,
            radius: configuration.dropRadius,
            to: island.frame
        )
        if distance <= configuration.absorptionThreshold {
            absorbStart = center.position
            absorbProgress = 0
            phase = .absorbing
        } else {
            phase = .returning
        }
        startDisplayLinkIfNeeded()
    }

    /// Останавливает CADisplayLink, когда вью уходит с экрана
    func stop() {
        stopDisplayLink()
    }

    /// Запускает CADisplayLink снова, если анимация ещё не закончилась
    func resume() {
        startDisplayLinkIfNeeded()
    }

    // MARK: - Состояние

    /// Точка дома: под островом, ближе к низу экрана
    private var home: CGPoint {
        CGPoint(x: bounds.midX, y: min(island.frame.maxY + 170, bounds.maxY - 160))
    }

    /// Капля в доме и не двигается: кадровый цикл для неё не нужен
    private var isSettled: Bool {
        let dx = center.position.x - home.x
        let dy = center.position.y - home.y
        let speed = hypot(center.velocity.x, center.velocity.y)
        return hypot(dx, dy) < 0.3 && speed < 0.5 && abs(scale - 1) < 0.004 && abs(scaleVelocity) < 0.02
    }

    private var needsFrames: Bool {
        switch phase {
        case .hidden: return respawnTimer > 0
        case .resting: return !isSettled
        default: return true
        }
    }

    private func spawn(at point: CGPoint) {
        center = SpringState(position: point)
        pull = SpringState(position: .zero)
        scale = 0
        scaleVelocity = 0
        respawnTimer = 0
        phase = .appearing
        startDisplayLinkIfNeeded()
    }

    // MARK: - Кадры

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil, needsFrames else { return }
        let link = CADisplayLink(target: linkTarget, selector: #selector(DisplayLinkTarget.tick(_:)))
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
            // Ограничиваем шаг: после паузы в приложении большой dt дал бы рывок пружин
            dt = CGFloat(min(max(link.timestamp - lastTimestamp, 1.0 / 240.0), 1.0 / 30.0))
        }
        lastTimestamp = link.timestamp

        advance(by: dt)
        emitFrame()
        if !needsFrames {
            stopDisplayLink()
        }
    }

    private func advance(by dt: CGFloat) {
        let config = configuration

        switch phase {
        case .hidden:
            guard respawnTimer > 0 else { return }
            respawnTimer = max(0, respawnTimer - dt)
            if respawnTimer == 0 {
                spawn(at: home)
            }

        case .appearing:
            stepScale(dt, target: 1)
            stepCenter(toward: home, dt: dt, config: config)
            if abs(scale - 1) < 0.004 && abs(scaleVelocity) < 0.02 {
                scale = 1
                scaleVelocity = 0
                phase = .resting
            }

        case .resting:
            stepCenter(toward: home, dt: dt, config: config)

        case .dragging:
            let finger = CGPoint(x: pointer.x + grabOffset.x, y: pointer.y + grabOffset.y)
            let distance = LiquidPhysicsEngine.surfaceDistance(from: finger, radius: config.dropRadius, to: island.frame)
            let attraction = LiquidPhysicsEngine.attraction(distance: distance, radius: config.attractionRadius)
            let magnetic = LiquidPhysicsEngine.magneticTarget(
                pointer: finger,
                island: island.frame,
                radius: config.dropRadius,
                attraction: attraction
            )

            // Капля идёт за пальцем без задержки; пружина добавляет только смещение к острову, поэтому тянущий эффект плавный
            let previous = center.position
            LiquidPhysicsEngine.stepSpring(
                &pull,
                target: CGPoint(x: magnetic.x - finger.x, y: magnetic.y - finger.y),
                stiffness: config.springStiffness,
                damping: config.damping,
                dt: dt
            )
            center.position = CGPoint(x: finger.x + pull.position.x, y: finger.y + pull.position.y)

            // Скорость по смещению между кадрами сглаживаем; по ней капля вытягивается при быстром движении
            let measuredX = (center.position.x - previous.x) / dt
            let measuredY = (center.position.y - previous.y) / dt
            center.velocity = CGPoint(
                x: center.velocity.x + (measuredX - center.velocity.x) * 0.35,
                y: center.velocity.y + (measuredY - center.velocity.y) * 0.35
            )
            stepScale(dt, target: 1)

        case .returning:
            stepCenter(toward: home, dt: dt, config: config)
            stepScale(dt, target: 1)
            let dx = center.position.x - home.x
            let dy = center.position.y - home.y
            if hypot(dx, dy) < 0.5, hypot(center.velocity.x, center.velocity.y) < 1 {
                center = SpringState(position: home)
                phase = .resting
            }

        case .absorbing:
            absorbProgress = min(1, absorbProgress + dt / absorbDuration)
            let p = absorbProgress
            // Квадратичный путь: капля сначала медленно отходит, потом быстро падает в остров
            let t = p * p
            let end = CGPoint(x: island.frame.midX, y: island.frame.midY)
            center = SpringState(position: CGPoint(
                x: absorbStart.x + (end.x - absorbStart.x) * t,
                y: absorbStart.y + (end.y - absorbStart.y) * t
            ))
            scale = 1 - p
            scaleVelocity = 0
            if p >= 1 {
                finishAbsorption()
            }
        }
    }

    private func finishAbsorption() {
        phase = .hidden
        scale = 0
        scaleVelocity = 0
        absorbProgress = 0
        respawnTimer = respawnDelay
        onAbsorbed?()
    }

    private func stepCenter(toward target: CGPoint, dt: CGFloat, config: LiquidIslandConfiguration) {
        LiquidPhysicsEngine.stepSpring(
            &center,
            target: target,
            stiffness: config.springStiffness,
            damping: config.damping,
            dt: dt
        )
    }

    private func stepScale(_ dt: CGFloat, target: CGFloat) {
        LiquidPhysicsEngine.stepSpring(
            value: &scale,
            velocity: &scaleVelocity,
            target: target,
            stiffness: LiquidPhysicsEngine.scaleStiffness,
            damping: LiquidPhysicsEngine.scaleDamping,
            dt: dt
        )
    }

    private func emitFrame() {
        let shape = LiquidPhysicsEngine.shape(
            center: center.position,
            velocity: center.velocity,
            scale: scale,
            absorption: phase == .absorbing ? absorbProgress : 0,
            island: island.frame,
            configuration: configuration
        )
        onFrame?(shape)
    }
}

/// Слабая цель для CADisplayLink. Link сохраняет свою цель, поэтому напрямую контроллер в цели не подходит: получился бы цикл
private final class DisplayLinkTarget: NSObject {

    private weak var owner: LiquidAnimationController?

    init(owner: LiquidAnimationController) {
        self.owner = owner
    }

    @objc func tick(_ link: CADisplayLink) {
        owner?.handleFrame(link)
    }
}
