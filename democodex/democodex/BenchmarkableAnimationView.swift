import UIKit

@MainActor
protocol BenchmarkableAnimationView: UIView {
    var progress: Float { get set }
    func startAnimation()
    func stopAnimation()
}

@MainActor
private final class AnimationDisplayLinkTarget: NSObject {
    weak var owner: AnimationView?
    @objc func tick(_ link: CADisplayLink) { owner?.render(time: link.targetTimestamp) }
}

/// Shared lifecycle and interaction for all ten components. A standalone view
/// owns its display link; the benchmark sets externallyDriven to use one clock.
class AnimationView: UIView, BenchmarkableAnimationView {
    var progress: Float = 0.68 {
        didSet {
            progress = progress.isFinite ? min(max(progress, 0), 1) : 0
            accessibilityValue = "\(Int(progress * 100)) процентов"
            setNeedsLayout()
            progressDidChange()
        }
    }
    var externallyDriven = false
    var onProgressChanged: ((Float) -> Void)?
    private(set) var isAnimating = false
    private(set) var animationTime = 0.0
    private(set) var interactionPoint = CGPoint(x: 0.5, y: 0.5)
    private(set) var interactionStrength: Float = 0
    private var isInteracting = false
    private var previousTime: Double?
    private var displayLink: CADisplayLink?
    private let displayTarget = AnimationDisplayLinkTarget()
    private(set) lazy var interactionPan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureInteraction()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureInteraction()
    }

    private func configureInteraction() {
        displayTarget.owner = self
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isAccessibilityElement = true
        addGestureRecognizer(interactionPan)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
        NotificationCenter.default.addObserver(self, selector: #selector(background),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func startAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        previousTime = nil
        animationDidStart()
        startDisplayLinkIfNeeded()
    }

    func stopAnimation() {
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        previousTime = nil
        resetInteraction()
        animationDidStop()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
            animationDidStop()
        } else if isAnimating {
            previousTime = nil
            animationDidStart()
            startDisplayLinkIfNeeded()
        }
    }

    private func startDisplayLinkIfNeeded() {
        guard isAnimating, !externallyDriven, window != nil, displayLink == nil,
              UIApplication.shared.applicationState == .active else { return }
        let link = CADisplayLink(target: displayTarget, selector: #selector(AnimationDisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Local time starts at zero for each new view, so A/B uses the same trajectory.
    final func render(time: CFTimeInterval) {
        guard isAnimating else { return }
        let dt = previousTime.map { max(0, time - $0) } ?? 0
        previousTime = time
        animationTime += dt
        if !isInteracting { interactionStrength *= Float(exp(-dt * 2.8)) }
        updateFrame(time: animationTime)
    }

    func updateFrame(time: CFTimeInterval) {}
    func progressDidChange() {}
    func animationDidStart() {}
    func animationDidStop() {}
    func interactionDidChange() {}

    /// Normalized coordinates, shared by UIKit and Metal. Also usable by a host
    /// supplying its own input. Strength decays after the drag is released.
    func updateInteraction(at point: CGPoint, active: Bool) {
        guard point.x.isFinite, point.y.isFinite else { return }
        interactionPoint = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        isInteracting = active
        interactionStrength = 1
        interactionDidChange()
    }

    func resetInteraction() {
        isInteracting = false
        interactionStrength = 0
        interactionPoint = CGPoint(x: 0.5, y: 0.5)
    }

    private func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / max(bounds.width, 1), y: point.y / max(bounds.height, 1))
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        updateInteraction(at: normalized(gesture.location(in: self)),
                          active: gesture.state == .began || gesture.state == .changed)
    }

    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        updateInteraction(at: normalized(gesture.location(in: self)), active: false)
    }

    @objc private func background() {
        displayLink?.invalidate()
        displayLink = nil
        previousTime = nil
        resetInteraction()
        animationDidStop()
    }

    @objc private func foreground() {
        if isAnimating, window != nil {
            animationDidStart()
            startDisplayLinkIfNeeded()
        }
    }
}

enum AnimationEffect: String, CaseIterable {
    case lava, wave, metaBall, plasma, fire

    var title: String {
        switch self {
        case .lava: "Лава"
        case .wave: "Вода"
        case .metaBall: "Капли"
        case .plasma: "Плазма"
        case .fire: "Огонь"
        }
    }

    var parameterTitle: String {
        switch self {
        case .lava, .wave: "Заполнение"
        case .metaBall: "Размер капель"
        case .plasma: "Энергия"
        case .fire: "Интенсивность"
        }
    }

    var interactionHint: String {
        switch self {
        case .lava: "Слайдер меняет заполнение лавы."
        case .wave: "Проведите по воде: уровень и волны следуют за пальцем."
        case .metaBall: "Коснитесь или тяните: капли притягиваются и слипаются."
        case .plasma: "Перетягивайте сгусток энергии внутри карточки."
        case .fire: "Проведите влево или вправо, чтобы изменить ветер."
        }
    }

    func details(engine: LavaEngine) -> String {
        switch (self, engine) {
        case (.lava, .uiKit): "CAGradientLayer · маска CAShapeLayer"
        case (.lava, .metal): "Процедурный fBm · горячий мениск"
        case (.wave, .uiKit): "CAShapeLayer · пересчёт волновых путей"
        case (.wave, .metal): "4 синусоидальные волны · процедурная пена"
        case (.metaBall, .uiKit): "Поле потенциалов · контур на Main Thread"
        case (.metaBall, .metal): "5 капель · поле R² / distance² · smoothstep"
        case (.plasma, .uiKit): "Радиальные CAGradientLayer · transform / opacity"
        case (.plasma, .metal): "Domain warping · fBm внутри fBm"
        case (.fire, .uiKit): "CAEmitterLayer · пламя, дым и искры"
        case (.fire, .metal): "Вертикальная turbulence · дым · тепловое искажение"
        }
    }

    @MainActor
    func makeView(engine: LavaEngine) -> AnimationView {
        switch (self, engine) {
        case (.lava, .uiKit): StandardLavaProgressBarView()
        case (.lava, .metal): MetalLavaProgressBarView()
        case (.wave, .uiKit): StandardWaveView()
        case (.wave, .metal): MetalWaveView()
        case (.metaBall, .uiKit): StandardMetaBallView()
        case (.metaBall, .metal): MetalMetaBallView()
        case (.plasma, .uiKit): StandardPlasmaView()
        case (.plasma, .metal): MetalPlasmaView()
        case (.fire, .uiKit): StandardFireView()
        case (.fire, .metal): MetalFireView()
        }
    }
}
