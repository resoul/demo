//
//  ProgressBarView.swift
//  demoApp
//

import UIKit

/// Анимация внутри заливки
enum ProgressEffect: CaseIterable {
    case plain
    case shimmer
    case stripes
    case liquidWave
    case stretch
    case pulseDot
    case flowGradient
    case particles

    var title: String {
        switch self {
        case .plain: return "Шарик"
        case .shimmer: return "Блик"
        case .stripes: return "Бегущие полоски"
        case .liquidWave: return "Жидкая волна"
        case .stretch: return "Растяжение кончика"
        case .pulseDot: return "Пульсирующая точка"
        case .flowGradient: return "Течущий градиент"
        case .particles: return "Искры"
        }
    }
}

final class ProgressBarView: UIView {

    var effect: ProgressEffect = .plain {
        didSet { applyEffect() }
    }
    /// Скорость догоняния цели: чем больше, тем быстрее заливка
    var progressSpeed: Double = 5
    /// Текущая цель прогресса, от 0 до 1
    private(set) var progress: CGFloat = 0

    private let trackView = UIView()
    private let fillView = UIView()
    private let shimmerLayer = CAGradientLayer()
    private let flowLayer = CAGradientLayer()
    private let stripesLayer = CALayer()
    private let waveMask = CAShapeLayer()
    private let emitter = CAEmitterLayer()
    private let dotLayer = CALayer()
    private let rippleLayer = CALayer()
    private let bubbleView = UIView()
    private let bubbleShape = CAShapeLayer()
    private let bubbleLabel = UILabel()

    private let trackHeight: CGFloat = 10
    private let trackTop: CGFloat = 40
    private let bubbleBodyHeight: CGFloat = 28
    private let bubbleTailHeight: CGFloat = 6
    private let bubblePaddingX: CGFloat = 12
    private let waveAmplitude: CGFloat = 3
    private let stripePeriod: CGFloat = 16
    /// Отступ по бокам, чтобы шарик на 100% не обрезался у края
    private let horizontalInset: CGFloat = 36
    private var trackWidth: CGFloat { bounds.width - horizontalInset * 2 }
    private var bubbleTotalHeight: CGFloat { bubbleBodyHeight + bubbleTailHeight }
    /// Кончик хвостика шарика чуть выше дорожки
    private var bubbleTipY: CGFloat { trackTop - 4 }
    private var tipCenterY: CGFloat { trackTop + trackHeight / 2 }

    // Пружина шарика и его наклон
    private let springStiffness: CGFloat = 150
    private let springDamping: CGFloat = 16
    private let maxTilt: CGFloat = 0.3

    private var displayedProgress: CGFloat = 0
    private var targetProgress: CGFloat = 0
    private var bubbleX: CGFloat = 0
    private var bubbleVelocity: CGFloat = 0
    private var fillVelocity: CGFloat = 0
    private var tilt: CGFloat = 0
    private var wavePhase: CGFloat = 0
    private var lastLayoutWidth: CGFloat = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var displayLink: CADisplayLink?

    private static let stripeImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { _ in
        UIColor.white.withAlphaComponent(0.25).setFill()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: 16))
        path.addLine(to: CGPoint(x: 8, y: 0))
        path.addLine(to: CGPoint(x: 12, y: 0))
        path.addLine(to: CGPoint(x: 4, y: 16))
        path.close()
        path.fill()
    }

    private static let dotImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { _ in
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 16, height: 16)).fill()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: trackTop + trackHeight)
    }

    private func setup() {
        trackView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
        trackView.layer.cornerRadius = trackHeight / 2
        trackView.clipsToBounds = true
        addSubview(trackView)

        fillView.backgroundColor = .systemBlue
        fillView.layer.cornerRadius = trackHeight / 2
        fillView.clipsToBounds = true
        trackView.addSubview(fillView)

        // Слои эффектов живут внутри заливки и обрезаются её формой
        shimmerLayer.colors = [
            UIColor.white.withAlphaComponent(0).cgColor,
            UIColor.white.withAlphaComponent(0.5).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor,
        ]
        shimmerLayer.locations = [NSNumber(value: 0.35), NSNumber(value: 0.5), NSNumber(value: 0.65)]
        flowLayer.colors = [UIColor.systemBlue.cgColor, UIColor.systemTeal.cgColor, UIColor.systemBlue.cgColor]
        for gradient in [shimmerLayer, flowLayer] {
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            gradient.isHidden = true
            fillView.layer.addSublayer(gradient)
        }

        stripesLayer.backgroundColor = UIColor(patternImage: ProgressBarView.stripeImage).cgColor
        stripesLayer.isHidden = true
        fillView.layer.addSublayer(stripesLayer)

        // Точка на кончике заливки и её пульс
        dotLayer.backgroundColor = UIColor.systemBlue.cgColor
        dotLayer.borderColor = UIColor.white.cgColor
        dotLayer.borderWidth = 2
        dotLayer.isHidden = true
        layer.addSublayer(dotLayer)

        rippleLayer.borderColor = UIColor.systemBlue.cgColor
        rippleLayer.borderWidth = 2
        rippleLayer.isHidden = true
        layer.addSublayer(rippleLayer)

        // Искры вылетают из кончика заливки, пока она движется
        emitter.emitterShape = .point
        emitter.emitterSize = CGSize(width: 1, height: 1)
        emitter.emitterCells = [makeEmitterCell()]
        emitter.birthRate = 0
        layer.addSublayer(emitter)

        bubbleView.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        bubbleShape.fillColor = UIColor.systemBlue.cgColor
        bubbleView.layer.addSublayer(bubbleShape)

        bubbleLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        bubbleLabel.textColor = .white
        bubbleLabel.textAlignment = .center
        bubbleView.addSubview(bubbleLabel)
        addSubview(bubbleView)
    }

    /// С анимацией заливка и шарик плавно догоняют новое значение
    func setProgress(_ value: CGFloat, animated: Bool = true) {
        progress = min(max(value, 0), 1)
        targetProgress = progress

        guard animated else {
            displayedProgress = targetProgress
            bubbleX = fillEndX(for: displayedProgress)
            bubbleVelocity = 0
            fillVelocity = 0
            tilt = 0
            render()
            return
        }
        startDisplayLink()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        trackView.frame = CGRect(x: horizontalInset, y: trackTop, width: trackWidth, height: trackHeight)

        // При смене ширины шарик ставим на место сразу, без пружины
        if bounds.width != lastLayoutWidth {
            lastLayoutWidth = bounds.width
            bubbleX = fillEndX(for: displayedProgress)
            bubbleVelocity = 0
        }
        render()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDisplayLink()
        } else if effect == .liquidWave {
            startDisplayLink()
        }
    }

    // MARK: - Эффекты

    private func applyEffect() {
        // Выключаем всё, что было включено для прошлого эффекта
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        [shimmerLayer, flowLayer, stripesLayer, dotLayer, rippleLayer].forEach { layer in
            layer.isHidden = true
            layer.removeAllAnimations()
        }
        fillView.layer.mask = nil
        emitter.birthRate = 0
        CATransaction.commit()

        switch effect {
        case .plain, .stretch, .particles:
            break
        case .shimmer:
            shimmerLayer.isHidden = false
            shimmerLayer.add(loop("startPoint", from: point(-1), to: point(1), duration: 1.4), forKey: "start")
            shimmerLayer.add(loop("endPoint", from: point(0), to: point(2), duration: 1.4), forKey: "end")
        case .flowGradient:
            flowLayer.isHidden = false
            flowLayer.add(loop("startPoint", from: point(-1), to: point(0), duration: 2), forKey: "start")
            flowLayer.add(loop("endPoint", from: point(0), to: point(1), duration: 2), forKey: "end")
        case .stripes:
            stripesLayer.isHidden = false
            stripesLayer.add(loop("transform.translation.x", from: 0.0, to: stripePeriod, duration: 0.5), forKey: "move")
        case .liquidWave:
            // Волна считается по кадрам, поэтому нужен display link (см. startDisplayLink)
            fillView.layer.mask = waveMask
        case .pulseDot:
            dotLayer.isHidden = false
            rippleLayer.isHidden = false
            rippleLayer.add(loop("transform.scale", from: 1.0, to: 3.0, duration: 1), forKey: "scale")
            rippleLayer.add(loop("opacity", from: 0.8, to: 0.0, duration: 1), forKey: "fade")
        }

        if effect == .liquidWave {
            startDisplayLink()
        }
        render()
    }

    private func loop(_ keyPath: String, from: Any, to: Any, duration: CFTimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        return animation
    }

    private func point(_ x: CGFloat) -> NSValue {
        NSValue(cgPoint: CGPoint(x: x, y: 0.5))
    }

    private func makeEmitterCell() -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = ProgressBarView.dotImage.cgImage
        cell.birthRate = 40
        cell.lifetime = 0.6
        cell.lifetimeRange = 0.2
        cell.velocity = 50
        cell.velocityRange = 30
        cell.emissionRange = .pi * 2
        cell.scale = 0.12
        cell.scaleRange = 0.06
        cell.alphaSpeed = -1.6
        cell.color = UIColor.systemBlue.cgColor
        return cell
    }

    // MARK: - Анимация по кадрам

    private var isMoving: Bool {
        displayLink != nil && abs(fillVelocity) > 5
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        lastFrameTime = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTime = 0
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastFrameTime == 0 ? 1.0 / 60.0 : min(now - lastFrameTime, 1.0 / 30.0)
        lastFrameTime = now

        // Заливка догоняет цель: чем дальше цель, тем быстрее движение
        let previous = displayedProgress
        let ease = CGFloat(1 - exp(-progressSpeed * dt))
        displayedProgress += (targetProgress - displayedProgress) * ease
        fillVelocity = (displayedProgress - previous) * trackWidth / CGFloat(dt)

        // Шарик висит на пружине и тянется за концом заливки, поэтому отстаёт и покачивается
        let fillX = fillEndX(for: displayedProgress)
        let force = springStiffness * (fillX - bubbleX) - springDamping * bubbleVelocity
        bubbleVelocity += force * CGFloat(dt)
        bubbleX += bubbleVelocity * CGFloat(dt)

        // Наклон зависит от скорости: шарик летит вправо — клонится вправо
        tilt = max(-maxTilt, min(maxTilt, bubbleVelocity / 1500))

        if effect == .liquidWave {
            wavePhase += CGFloat(dt) * 5
        }

        let isSettled = abs(targetProgress - displayedProgress) < 0.0005
            && abs(fillX - bubbleX) < 0.5
            && abs(bubbleVelocity) < 1
        if isSettled {
            displayedProgress = targetProgress
            bubbleX = fillEndX(for: displayedProgress)
            bubbleVelocity = 0
            fillVelocity = 0
            tilt = 0
            // Волна движется и в покое, поэтому её кадры не останавливаем
            if effect != .liquidWave {
                stopDisplayLink()
            }
        }
        render()
    }

    // MARK: - Отрисовка

    private func fillEndX(for value: CGFloat) -> CGFloat {
        horizontalInset + value * trackWidth
    }

    private func render() {
        // Без этого CoreAnimation добавляет свои анимации поверх пружины
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let fillWidth = displayedProgress * trackWidth

        // Заливка может растягиваться при скорости или иметь запас под волну
        let extraWidth: CGFloat
        switch effect {
        case .liquidWave: extraWidth = fillWidth > 0 ? waveAmplitude : 0
        case .stretch: extraWidth = min(abs(fillVelocity) * 0.02, 10)
        default: extraWidth = 0
        }
        fillView.frame = CGRect(x: 0, y: 0, width: fillWidth + extraWidth, height: trackHeight)
        let fillBounds = fillView.bounds
        shimmerLayer.frame = fillBounds
        flowLayer.frame = fillBounds
        stripesLayer.frame = CGRect(x: 0, y: 0, width: fillBounds.width + stripePeriod, height: trackHeight)

        if effect == .liquidWave {
            waveMask.frame = fillBounds
            waveMask.path = wavePath(fillWidth: fillWidth)
        }

        let tip = CGPoint(x: horizontalInset + fillWidth, y: tipCenterY)
        dotLayer.frame = CGRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 10)
        dotLayer.cornerRadius = 5
        rippleLayer.frame = dotLayer.frame
        rippleLayer.cornerRadius = 5
        emitter.emitterPosition = tip
        emitter.birthRate = effect == .particles && isMoving ? 1 : 0

        bubbleLabel.text = "\(Int((displayedProgress * 100).rounded()))%"
        bubbleLabel.sizeToFit()
        let bodyWidth = bubbleLabel.intrinsicContentSize.width + bubblePaddingX * 2

        // Шарик не выходит за края, даже если пружина тянет дальше
        let x = min(max(bubbleX, bodyWidth / 2), bounds.width - bodyWidth / 2)

        bubbleView.layer.bounds = CGRect(x: 0, y: 0, width: bodyWidth, height: bubbleTotalHeight)
        bubbleView.layer.position = CGPoint(x: x, y: bubbleTipY)
        bubbleView.layer.transform = CATransform3DMakeRotation(tilt, 0, 0, 1)
        bubbleShape.frame = CGRect(x: 0, y: 0, width: bodyWidth, height: bubbleTotalHeight)
        bubbleShape.path = bubblePath(width: bodyWidth).cgPath
        bubbleLabel.frame = CGRect(x: 0, y: 0, width: bodyWidth, height: bubbleBodyHeight)

        CATransaction.commit()
    }

    /// Правый край заливки волнистый: синусоида по высоте дорожки, фаза идёт со временем
    private func wavePath(fillWidth: CGFloat) -> CGPath {
        let path = UIBezierPath()
        let steps = 20
        path.move(to: .zero)
        for i in 0...steps {
            let y = trackHeight * CGFloat(i) / CGFloat(steps)
            let x = fillWidth + waveAmplitude * sin(y / trackHeight * 4 * .pi + wavePhase)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: 0, y: trackHeight))
        path.close()
        return path.cgPath
    }

    /// Скруглённый прямоугольник с хвостиком вниз по центру
    private func bubblePath(width: CGFloat) -> UIBezierPath {
        let path = UIBezierPath(
            roundedRect: CGRect(x: 0, y: 0, width: width, height: bubbleBodyHeight),
            cornerRadius: 8
        )
        let mid = width / 2
        path.move(to: CGPoint(x: mid - 5, y: bubbleBodyHeight))
        path.addLine(to: CGPoint(x: mid, y: bubbleTotalHeight))
        path.addLine(to: CGPoint(x: mid + 5, y: bubbleBodyHeight))
        path.close()
        return path
    }
}
