//
//  LiquidIslandView.swift
//  demoApp
//

import UIKit

/// Вью с каплей и жидкой перемычкой к Dynamic Island. Отрисовывает форму из `LiquidShape`, физику не считает.
/// Переносится в другое UIKit-приложение целиком: зависит только от файлов папки LiquidIsland
final class LiquidIslandView: UIView, UIGestureRecognizerDelegate {

    /// Параметры эффекта; меняются в реальном времени из debug-панели
    var configuration = LiquidIslandConfiguration() {
        didSet { controller.configuration = configuration }
    }

    private let controller = LiquidAnimationController()
    private var island = IslandGeometry(frame: .zero, isSystemIsland: true)
    private var hasStarted = false

    /// Острова нет на экране: его рисует сама вью. На устройстве с Dynamic Island слой скрыт
    private let islandLayer = CAShapeLayer()
    /// Перемычка между каплей и островом
    private let neckLayer = CAShapeLayer()
    private let dropLayer = CAShapeLayer()
    /// Отклик острова после поглощения: упругое кольцо вокруг острова
    private let rippleLayer = CAShapeLayer()

    private lazy var panGesture: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        return pan
    }()

    private lazy var impactFeedback = UIImpactFeedbackGenerator(style: .soft)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        controller.stop()
    }

    // MARK: - Настройка

    private func setup() {
        backgroundColor = .clear

        for shapeLayer in [islandLayer, neckLayer, dropLayer] {
            shapeLayer.fillColor = UIColor.black.cgColor
            layer.addSublayer(shapeLayer)
        }

        rippleLayer.fillColor = nil
        rippleLayer.strokeColor = UIColor.black.cgColor
        rippleLayer.lineWidth = 2
        rippleLayer.opacity = 0
        layer.addSublayer(rippleLayer)

        addGestureRecognizer(panGesture)

        controller.onFrame = { [weak self] shape in
            self?.render(shape)
        }
        controller.onAbsorbed = { [weak self] in
            self?.playAbsorptionResponse()
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        island = IslandGeometryProvider.geometry(in: self)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        islandLayer.isHidden = island.isSystemIsland
        islandLayer.path = UIBezierPath(roundedRect: island.frame, cornerRadius: island.frame.height / 2).cgPath
        let ringFrame = island.frame.insetBy(dx: -14, dy: -10)
        rippleLayer.frame = ringFrame
        rippleLayer.path = UIBezierPath(roundedRect: rippleLayer.bounds, cornerRadius: ringFrame.height / 2).cgPath
        CATransaction.commit()

        controller.updateLayout(island: island, bounds: bounds)

        if !hasStarted, !bounds.isEmpty {
            hasStarted = true
            controller.start()
        }
    }

    /// Касания внутри области системного острова не перехватываем: они принадлежат системе
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if island.isSystemIsland, island.frame.insetBy(dx: -12, dy: -8).contains(point) {
            return nil
        }
        return super.hitTest(point, with: event)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Вне окна кадровый цикл не нужен: остановим его, а при возврате продолжим
        if window == nil {
            controller.stop()
        } else {
            controller.resume()
        }
    }

    // MARK: - Жест

    /// Жест начинается только если палец попал в каплю, либо капли нет и палец создаёт новую
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        controller.canGrab(at: gestureRecognizer.location(in: self))
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            controller.beginGrab(at: point)
        case .changed:
            controller.moveGrab(to: point)
        case .ended, .cancelled, .failed:
            controller.endGrab()
        default:
            break
        }
    }

    // MARK: - Отрисовка

    /// Рисует каплю и перемычку по готовой форме. Пути пересоздаются на каждом кадре, слои — нет
    private func render(_ shape: LiquidShape) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard shape.isVisible else {
            dropLayer.isHidden = true
            neckLayer.isHidden = true
            return
        }

        dropLayer.isHidden = false
        dropLayer.path = LiquidPathBuilder.dropPath(shape).cgPath

        if let neck = LiquidPathBuilder.neckPath(shape) {
            neckLayer.isHidden = false
            neckLayer.path = neck.cgPath
        } else {
            neckLayer.isHidden = true
        }
    }

    /// Отклик острова: кольцо быстро расширяется с упругим перелётом и гаснет
    private func playAbsorptionResponse() {
        impactFeedback.impactOccurred(intensity: 0.8)

        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.9
        scale.toValue = 1.15
        scale.mass = 1
        scale.stiffness = 170
        scale.damping = 11
        scale.duration = scale.settlingDuration

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.7
        fade.toValue = 0
        fade.duration = 0.7
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

        rippleLayer.removeAllAnimations()
        rippleLayer.opacity = 0
        rippleLayer.add(scale, forKey: "ripple.scale")
        rippleLayer.add(fade, forKey: "ripple.fade")
    }
}
