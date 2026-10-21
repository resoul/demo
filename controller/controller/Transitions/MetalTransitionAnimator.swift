//
//  MetalTransitionAnimator.swift
//  controller
//
//  UIKit view-controller transitions rendered with Metal:
//  both screens are snapshotted into MTLTextures and composited by a fragment
//  shader (see Shaders.metal) in an MTKView driven by a 120 Hz CADisplayLink.
//

import UIKit
import MetalKit

// MARK: - Effects

enum MetalTransitionEffect: String, CaseIterable {
    case rippleDissolve
    case vortex
    case pageCurl
    case noiseDissolve
    case pixelate
    case glitch
    case zoomBlur
    case chromaticPortal

    enum Category: String, CaseIterable {
        case distortion = "Distortion & Geometry"
        case digital = "Digital & Glitch"
        case optics = "Optics & Blurs"
    }

    var category: Category {
        switch self {
        case .rippleDissolve, .vortex, .pageCurl: .distortion
        case .noiseDissolve, .pixelate, .glitch: .digital
        case .zoomBlur, .chromaticPortal: .optics
        }
    }

    var title: String {
        switch self {
        case .rippleDissolve: "Ripple Dissolve"
        case .vortex: "Vortex / Swirl"
        case .pageCurl: "3D Page Curl & Wave"
        case .noiseDissolve: "Perlin Noise Dissolve"
        case .pixelate: "Pixelate / Mosaic"
        case .glitch: "Digital Glitch & RGB Split"
        case .zoomBlur: "Zoom Lens & Radial Blur"
        case .chromaticPortal: "Chromatic Tunnel / Portal"
        }
    }

    var fragmentFunctionName: String {
        switch self {
        case .rippleDissolve: "ripple_dissolve_fragment"
        case .vortex: "vortex_fragment"
        case .pageCurl: "page_curl_fragment"
        case .noiseDissolve: "noise_dissolve_fragment"
        case .pixelate: "pixelate_fragment"
        case .glitch: "glitch_fragment"
        case .zoomBlur: "zoom_blur_fragment"
        case .chromaticPortal: "chromatic_portal_fragment"
        }
    }

    var defaultDuration: TimeInterval {
        switch self {
        case .rippleDissolve, .noiseDissolve: 0.8
        case .vortex, .pageCurl, .chromaticPortal: 0.7
        case .pixelate: 0.6
        case .zoomBlur: 0.55
        case .glitch: 0.5
        }
    }
}

/// Mirrors `TransitionUniforms` in Shaders.metal — keep field order and types in sync.
struct TransitionUniforms {
    var progress: Float = 0
    var time: Float = 0
    var resolution: SIMD2<Float> = .zero
    var touch: SIMD2<Float> = SIMD2(0.5, 0.5)
    var aspect: Float = 1
}

// MARK: - Renderer

/// Shared GPU objects: device, queue, compiled pipelines and the snapshot → texture path.
final class MetalTransitionRenderer {
    static let shared = MetalTransitionRenderer()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pixelFormat: MTLPixelFormat = .bgra8Unorm
    private let library: MTLLibrary
    private var pipelines: [MetalTransitionEffect: MTLRenderPipelineState] = [:]

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        self.library = library
    }

    func pipeline(for effect: MetalTransitionEffect) -> MTLRenderPipelineState? {
        if let cached = pipelines[effect] { return cached }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Transition.\(effect.rawValue)"
        descriptor.vertexFunction = library.makeFunction(name: "transition_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: effect.fragmentFunctionName)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        do {
            let state = try device.makeRenderPipelineState(descriptor: descriptor)
            pipelines[effect] = state
            return state
        } catch {
            assertionFailure("Failed to build pipeline for \(effect): \(error)")
            return nil
        }
    }

    /// Compiles pipelines ahead of time so the first frame of a transition doesn't hitch.
    func prewarm(_ effects: [MetalTransitionEffect] = MetalTransitionEffect.allCases) {
        effects.forEach { _ = pipeline(for: $0) }
    }

    /// Draws `view` at `frame` into a canvas the size of `canvas`, straight into a BGRA bitmap
    /// that is uploaded as a texture (no intermediate UIImage / PNG round trip).
    /// `onScreen` views are captured as last rendered (includes blurs and other render-server effects);
    /// views that haven't been on screen yet are rendered from their layer tree, because
    /// `drawHierarchy(afterScreenUpdates: true)` is not allowed inside the transition's CA commit.
    func makeTexture(snapshotting view: UIView, frame: CGRect, canvas: CGSize, scale: CGFloat,
                     onScreen: Bool) -> MTLTexture? {
        let width = Int((canvas.width * scale).rounded())
        let height = Int((canvas.height * scale).rounded())
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        // Flip into UIKit coordinates so row 0 of the bitmap is the top of the screen.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.setFillColor(UIColor.systemBackground.resolvedColor(with: view.traitCollection).cgColor)
        context.fill(CGRect(origin: .zero, size: canvas))

        UIGraphicsPushContext(context)
        if !onScreen || !view.drawHierarchy(in: frame, afterScreenUpdates: false) {
            context.translateBy(x: frame.minX, y: frame.minY)
            view.layer.render(in: context)
        }
        UIGraphicsPopContext()

        guard let bytes = context.data else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: context.bytesPerRow)
        return texture
    }
}

// MARK: - Animator

final class MetalTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    enum Operation {
        case present, dismiss, push, pop

        var isForward: Bool { self == .present || self == .push }
    }

    static let durationRange: ClosedRange<TimeInterval> = 0.4...0.8

    let effect: MetalTransitionEffect
    let operation: Operation
    let duration: TimeInterval
    /// Origin of the effect (ripple, burn, zoom, portal) in window coordinates. Defaults to the center.
    var touchPoint: CGPoint?
    /// Back transitions (pop / dismiss) play the forward effect in reverse, e.g. the page uncurls.
    var reversesOnBack = true

    private var session: MetalTransitionSession?

    init(effect: MetalTransitionEffect, operation: Operation, duration: TimeInterval? = nil,
         touchPoint: CGPoint? = nil) {
        self.effect = effect
        self.operation = operation
        let requested = duration ?? effect.defaultDuration
        self.duration = min(max(requested, Self.durationRange.lowerBound), Self.durationRange.upperBound)
        self.touchPoint = touchPoint
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        duration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView
        guard let fromVC = transitionContext.viewController(forKey: .from),
              let toVC = transitionContext.viewController(forKey: .to),
              let fromView = transitionContext.view(forKey: .from) ?? fromVC.view,
              let toView = transitionContext.view(forKey: .to) ?? toVC.view else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }

        toView.frame = transitionContext.finalFrame(for: toVC)
        if fromView.superview === container {
            container.insertSubview(toView, belowSubview: fromView)
        } else {
            container.addSubview(toView)
        }
        toView.layoutIfNeeded()

        let bounds = container.bounds
        let scale = container.traitCollection.displayScale
        let fromFrame = frame(transitionContext.initialFrame(for: fromVC), or: bounds)

        guard let renderer = MetalTransitionRenderer.shared,
              let pipeline = renderer.pipeline(for: effect),
              let fromTexture = renderer.makeTexture(snapshotting: fromView, frame: fromFrame, canvas: bounds.size,
                                                     scale: scale, onScreen: true),
              let toTexture = renderer.makeTexture(snapshotting: toView, frame: toView.frame, canvas: bounds.size,
                                                   scale: scale, onScreen: false) else {
            crossfade(from: fromView, to: toView, context: transitionContext)
            return
        }

        // Playing backwards = swap the screens and run progress 1 → 0.
        let reversed = reversesOnBack && !operation.isForward
        let probe = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        probe.isUserInteractionEnabled = false
        probe.alpha = 0
        container.addSubview(probe)

        let session = MetalTransitionSession(
            renderer: renderer,
            pipeline: pipeline,
            fromTexture: reversed ? toTexture : fromTexture,
            toTexture: reversed ? fromTexture : toTexture,
            frame: bounds,
            scale: scale,
            touch: normalizedTouch(in: container),
            probe: probe,
            reversed: reversed)
        container.addSubview(session.metalView)
        session.renderFirstFrame()
        fromView.isHidden = true
        toView.isHidden = true
        session.start()
        self.session = session

        // The probe's opacity is the timeline: Core Animation runs it in real time, and
        // UIPercentDrivenInteractiveTransition scrubs it by pausing the container layer.
        // It stays linear — each shader shapes its own easing.
        UIView.animate(withDuration: duration, delay: 0, options: [.curveLinear]) {
            probe.alpha = 1
        } completion: { _ in
            let cancelled = transitionContext.transitionWasCancelled
            session.stop()
            fromView.isHidden = false
            toView.isHidden = false
            if cancelled {
                toView.removeFromSuperview()
            }
            self.session = nil
            transitionContext.completeTransition(!cancelled)
        }
    }

    private func frame(_ frame: CGRect, or fallback: CGRect) -> CGRect {
        frame.isEmpty ? fallback : frame
    }

    private func normalizedTouch(in container: UIView) -> SIMD2<Float> {
        guard let touchPoint, container.bounds.width > 0, container.bounds.height > 0 else { return SIMD2(0.5, 0.5) }
        let point = container.convert(touchPoint, from: nil)
        let x = min(max(point.x / container.bounds.width, 0), 1)
        let y = min(max(point.y / container.bounds.height, 0), 1)
        return SIMD2(Float(x), Float(y))
    }

    /// Fallback when Metal is unavailable (or snapshotting fails).
    private func crossfade(from fromView: UIView, to toView: UIView,
                           context transitionContext: UIViewControllerContextTransitioning) {
        toView.alpha = 0
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut]) {
            toView.alpha = 1
        } completion: { _ in
            let cancelled = transitionContext.transitionWasCancelled
            if cancelled {
                toView.removeFromSuperview()
            }
            transitionContext.completeTransition(!cancelled)
        }
    }
}

// MARK: - Per-transition render state

private final class MetalTransitionSession: NSObject, MTKViewDelegate {
    let metalView: MTKView

    private let renderer: MetalTransitionRenderer
    private let pipeline: MTLRenderPipelineState
    private let fromTexture: MTLTexture
    private let toTexture: MTLTexture
    private let probe: UIView
    private let reversed: Bool
    private let startTime = CACurrentMediaTime()
    private var uniforms = TransitionUniforms()
    private var displayLink: CADisplayLink?

    init(renderer: MetalTransitionRenderer, pipeline: MTLRenderPipelineState, fromTexture: MTLTexture,
         toTexture: MTLTexture, frame: CGRect, scale: CGFloat, touch: SIMD2<Float>, probe: UIView,
         reversed: Bool) {
        self.renderer = renderer
        self.pipeline = pipeline
        self.fromTexture = fromTexture
        self.toTexture = toTexture
        self.probe = probe
        self.reversed = reversed

        metalView = MTKView(frame: frame, device: renderer.device)
        metalView.colorPixelFormat = renderer.pixelFormat
        metalView.framebufferOnly = true
        metalView.isOpaque = true
        metalView.isUserInteractionEnabled = false
        metalView.contentScaleFactor = scale
        metalView.autoResizeDrawable = false
        metalView.drawableSize = CGSize(width: fromTexture.width, height: fromTexture.height)
        // Frames are pushed by our own display link, not MTKView's internal timer.
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = false

        uniforms.resolution = SIMD2(Float(fromTexture.width), Float(fromTexture.height))
        uniforms.aspect = Float(fromTexture.width) / Float(max(fromTexture.height, 1))
        uniforms.touch = touch
        super.init()
        metalView.delegate = self
    }

    /// Presents frame 0 inside the current CATransaction, so the MTKView appears atomically
    /// with the real views being hidden — no blank or flashing frame.
    func renderFirstFrame() {
        metalView.presentsWithTransaction = true
        metalView.draw()
        metalView.presentsWithTransaction = false
    }

    func start() {
        let link = CADisplayLink(target: DisplayLinkTarget(session: self), selector: #selector(DisplayLinkTarget.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        metalView.delegate = nil
        metalView.removeFromSuperview()
        probe.removeFromSuperview()
    }

    private var progress: Float {
        let raw = min(max(probe.layer.presentation()?.opacity ?? 0, 0), 1)
        return reversed ? 1 - raw : raw
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        uniforms.progress = progress
        uniforms.time = Float(CACurrentMediaTime() - startTime)

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(fromTexture, index: 0)
        encoder.setFragmentTexture(toTexture, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TransitionUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        if view.presentsWithTransaction {
            commandBuffer.commit()
            commandBuffer.waitUntilScheduled()
            drawable.present()
        } else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

/// Weak trampoline: CADisplayLink retains its target, the session owns the link.
private final class DisplayLinkTarget: NSObject {
    weak var session: MetalTransitionSession?

    init(session: MetalTransitionSession) {
        self.session = session
    }

    @objc func tick(_ link: CADisplayLink) {
        session?.metalView.draw()
    }
}
