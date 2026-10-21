import UIKit
import MetalKit

@MainActor protocol MetalTransitionBackendReporting: AnyObject {
    func didSelectMetalTransitionBackend(_ metal: Bool)
}

enum MetalTransitionStyle: UInt32, CaseIterable {
    case perlinNoiseDissolve, rippleDistortion, glitchRGB
    var title: String {
        switch self {
        case .perlinNoiseDissolve: return "Perlin dissolve"
        case .rippleDistortion: return "Ripple distortion"
        case .glitchRGB: return "Glitch RGB"
        }
    }
}

/// UINavigationController-compatible screen animator, including actual Metal surfaces
/// in its snapshots. Snapshot readback is a one-time preparation cost, not per frame.
final class MetalTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let style: MetalTransitionStyle
    let touchOrigin: CGPoint
    let reversed: Bool
    var duration: TimeInterval = 0.5
    private var session: MetalTransitionSession?

    init(style: MetalTransitionStyle, touchOrigin: CGPoint = CGPoint(x: 0.5, y: 0.5), reversed: Bool = false) {
        self.style = style
        self.touchOrigin = touchOrigin
        self.reversed = reversed
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.18 : duration
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let from = context.view(forKey: .from), let to = context.view(forKey: .to),
              let target = context.viewController(forKey: .to) else { context.completeTransition(false); return }
        to.frame = context.finalFrame(for: target)
        if from.superview === context.containerView { context.containerView.insertSubview(to, belowSubview: from) }
        else { context.containerView.addSubview(to) }
        to.setNeedsLayout()
        to.layoutIfNeeded()
        do {
            let session = try MetalTransitionSession(context: context, style: style, origin: touchOrigin,
                reversed: reversed, duration: transitionDuration(using: context)) { [weak self] in self?.session = nil }
            self.session = session
            (target as? MetalTransitionBackendReporting)?.didSelectMetalTransitionBackend(true)
            session.start()
        } catch {
            (target as? MetalTransitionBackendReporting)?.didSelectMetalTransitionBackend(false)
            // Metal unavailable or texture allocation failed: finish a standard UIKit fade.
            let oldAlpha = to.alpha
            context.containerView.bringSubviewToFront(to)
            to.alpha = 0
            UIView.animate(withDuration: transitionDuration(using: context), animations: { to.alpha = oldAlpha }) { _ in
                to.alpha = oldAlpha
                let completed = !context.transitionWasCancelled
                if !completed { to.removeFromSuperview() }
                context.completeTransition(completed)
            }
        }
    }
}

private final class MetalTransitionSession: NSObject {
    private let context: UIViewControllerContextTransitioning
    private let from: UIView
    private let to: UIView
    private let fromWasHidden: Bool
    private let toWasHidden: Bool
    private let surface: TransitionMetalSurface
    private let duration: TimeInterval
    private let completion: () -> Void
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var finished = false

    init(context: UIViewControllerContextTransitioning, style: MetalTransitionStyle, origin: CGPoint,
         reversed: Bool, duration: TimeInterval, completion: @escaping () -> Void) throws {
        self.context = context
        from = context.view(forKey: .from)!
        to = context.view(forKey: .to)!
        fromWasHidden = from.isHidden
        toWasHidden = to.isHidden
        self.duration = max(duration, 0.01)
        self.completion = completion
        let engine = try MetalEngine.shared.get()
        let loader = MTKTextureLoader(device: engine.device)
        let fromImage = MetalSnapshot.capture(from)
        let toImage = MetalSnapshot.capture(to)
        guard let fromCG = fromImage.cgImage, let toCG = toImage.cgImage else { throw MetalEngineError.allocation }
        let options: [MTKTextureLoader.Option: Any] = [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft]
        let a = try loader.newTexture(cgImage: fromCG, options: options)
        let b = try loader.newTexture(cgImage: toCG, options: options)
        surface = try TransitionMetalSurface(engine: engine, from: a, to: b,
            style: UIAccessibility.isReduceMotionEnabled ? 3 : style.rawValue,
            origin: origin, reversed: reversed)
        super.init()
        surface.frame = context.containerView.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        surface.onFinalFrame = { [weak self] in self?.finish() }
        NotificationCenter.default.addObserver(self, selector: #selector(finish), name: UIApplication.willResignActiveNotification, object: nil)
    }

    func start() {
        context.containerView.addSubview(surface)
        surface.layoutIfNeeded()
        from.isHidden = true
        to.isHidden = true
        startTime = CACurrentMediaTime()
        _ = surface.render(progress: 0, time: 0)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        let maximum = Float(min(120, surface.window?.screen.maximumFramesPerSecond ?? 60))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, maximum), maximum: maximum, preferred: maximum)
        self.link = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard !finished else { return }
        let elapsed = max(0, link.targetTimestamp - startTime)
        let progress = Float(min(1, elapsed / duration))
        if surface.render(progress: progress, time: Float(elapsed)) && progress >= 1 { link.isPaused = true }
    }

    @objc private func finish() {
        guard !finished else { return }
        finished = true
        link?.invalidate()
        link = nil
        from.isHidden = fromWasHidden
        to.isHidden = toWasHidden
        let success = !context.transitionWasCancelled
        if !success { to.removeFromSuperview() }
        context.completeTransition(success)
        surface.removeFromSuperview()
        completion()
    }
}

private final class TransitionMetalSurface: MTKView, MTKViewDelegate {
    var onFinalFrame: (() -> Void)?
    private let engine: MetalEngine
    private let pipeline: MTLRenderPipelineState
    private let fromTexture: MTLTexture
    private let toTexture: MTLTexture
    private let ring: MTLBuffer
    private let inFlight = DispatchSemaphore(value: 3)
    private var slot = 0
    private var u = TransitionUniforms()
    private var submitted = false

    init(engine: MetalEngine, from: MTLTexture, to: MTLTexture, style: UInt32, origin: CGPoint, reversed: Bool) throws {
        self.engine = engine
        pipeline = try engine.render(vertex: "engineFullscreenVertex", fragment: "screenTransition")
        fromTexture = from
        toTexture = to
        guard let ring = engine.device.makeBuffer(length: 256 * 3, options: .storageModeShared) else { throw MetalEngineError.allocation }
        self.ring = ring
        super.init(frame: .zero, device: engine.device)
        colorPixelFormat = .bgra8Unorm
        isPaused = true
        enableSetNeedsDisplay = false
        isUserInteractionEnabled = false
        delegate = self
        u.state = SIMD4(0, Float(style), Float(min(1, max(0, origin.x))), Float(min(1, max(0, origin.y))))
        u.viewport.w = reversed ? 1 : 0
    }

    required init(coder: NSCoder) { fatalError("Use init(engine:from:to:style:origin:reversed:)") }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func render(progress: Float, time: Float) -> Bool {
        u.state.x = progress
        u.viewport.x = Float(drawableSize.width)
        u.viewport.y = Float(drawableSize.height)
        u.viewport.z = time
        submitted = false
        draw() // MTKView owns drawable acquisition/release for this manual frame.
        return submitted
    }

    func draw(in view: MTKView) {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = currentDrawable, let command = engine.queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: MetalEngine.pass(drawable.texture)) else {
            inFlight.signal()
            if u.state.x >= 1 { onFinalFrame?() }
            return
        }
        let offset = slot % 3 * 256
        withUnsafeBytes(of: &u) { ring.contents().advanced(by: offset).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBuffer(ring, offset: offset, index: 0)
        encoder.setFragmentTexture(fromTexture, index: 0)
        encoder.setFragmentTexture(toTexture, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        let final = u.state.x >= 1 ? onFinalFrame : nil, semaphore = inFlight
        command.addCompletedHandler { _ in
            semaphore.signal()
            if let final { DispatchQueue.main.async { final() } }
        }
        command.present(drawable)
        command.commit()
        slot += 1
        submitted = true
    }
}

final class MetalNavigationController: UINavigationController, UINavigationControllerDelegate {
    override var childForStatusBarStyle: UIViewController? { topViewController }
    var transitionStyle: MetalTransitionStyle = .perlinNoiseDissolve
    var transitionOrigin = CGPoint(x: 0.5, y: 0.5)

    override func viewDidLoad() {
        super.viewDidLoad()
        setNavigationBarHidden(true, animated: false)
        delegate = self
    }

    func navigationController(_ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        MetalTransitionAnimator(style: transitionStyle, touchOrigin: transitionOrigin, reversed: operation == .pop)
    }
}
