import UIKit
import MetalKit
import CoreMotion

enum MetalEffect: UInt32 {
    case fluid, frost, aurora, pulse, foil, dissolve, glow
}

// Four SIMD vectors keep Swift and Metal's uniform layout identical (64 bytes).
private struct EffectUniforms {
    var viewport: SIMD4<Float>  // width, height, time, intensity
    var input: SIMD4<Float>     // touch x/y, tilt x/y
    var state: SIMD4<Float>     // effect, event age, dissolve progress, corner radius
    var options: SIMD4<Float>   // reserved
}

private final class MetalContext {
    static let shared = MetalContext()
    let device: MTLDevice?
    let queue: MTLCommandQueue?
    let pipeline: MTLRenderPipelineState?
    let placeholder: MTLTexture?
    let failure: String?
    let framesInFlight = DispatchSemaphore(value: 3)

    private init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        queue = device?.makeCommandQueue()
        var pipeline: MTLRenderPipelineState?
        var placeholder: MTLTexture?
        var failure: String?
        do {
            guard let device, queue != nil else {
                throw NSError(domain: "MetalLab", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Metal недоступен на этом устройстве"])
            }
            let library = try device.makeDefaultLibrary(bundle: .main)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "effectVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "effectFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
            textureDescriptor.usage = .shaderRead
            placeholder = device.makeTexture(descriptor: textureDescriptor)
            var white: UInt32 = 0xFFFFFFFF
            placeholder?.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                                 withBytes: &white, bytesPerRow: 4)
        } catch {
            failure = error.localizedDescription
        }
        self.pipeline = pipeline
        self.placeholder = placeholder
        self.failure = failure
    }
}

/// A shared clock and motion sensor for the entire gallery. Offscreen surfaces do no GPU work.
private final class EffectClock: NSObject {
    static let shared = EffectClock()
    private let surfaces = NSHashTable<MetalEffectView>.weakObjects()
    private let motion = CMMotionManager()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var firstSurface = 0
    private(set) var time: Float = 0
    var paused = false { didSet { lastTimestamp = nil; updateMotion() } }
    private(set) var tilt = SIMD2<Float>.zero

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(activityChanged),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(activityChanged),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(activityChanged),
                                               name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    func add(_ surface: MetalEffectView) {
        surfaces.add(surface)
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            let maximum = Float(min(surface.window?.screen.maximumFramesPerSecond ?? 60, 120))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, maximum), maximum: maximum, preferred: maximum)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        activityChanged()
    }

    func remove(_ surface: MetalEffectView) {
        surfaces.remove(surface)
        if surfaces.allObjects.isEmpty {
            displayLink?.invalidate()
            displayLink = nil
            motion.stopDeviceMotionUpdates()
        }
    }

    @objc private func activityChanged() {
        displayLink?.isPaused = UIApplication.shared.applicationState != .active
        lastTimestamp = nil
        updateMotion()
        surfaces.allObjects.forEach { $0.needsFrame = true }
    }

    private func updateMotion() {
        let enabled = UIApplication.shared.applicationState == .active && !paused
            && !UIAccessibility.isReduceMotionEnabled && !surfaces.allObjects.isEmpty
        if enabled && motion.isDeviceMotionAvailable && !motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 1.0 / 30
            motion.startDeviceMotionUpdates()
        } else if !enabled {
            motion.stopDeviceMotionUpdates()
            tilt = .zero
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let delta = Float(min(link.timestamp - (lastTimestamp ?? link.timestamp), 0.05))
        lastTimestamp = link.timestamp
        if !paused && !UIAccessibility.isReduceMotionEnabled { time += delta }
        if let gravity = motion.deviceMotion?.gravity {
            tilt += (SIMD2(Float(gravity.x), Float(-gravity.y)) - tilt) * 0.12
        }
        let visible = surfaces.allObjects.filter { $0.isVisible }
        // Rotate priority so a busy shared GPU cannot starve the last visible card.
        for index in visible.indices {
            let surface = visible[(index + firstSurface) % visible.count]
            if (!paused && !UIAccessibility.isReduceMotionEnabled) || surface.needsFrame {
                surface.drawFrame(time: time, tilt: tilt)
            }
        }
        firstSurface = (firstSurface + 1) % max(visible.count, 1)
    }
}

/// Can be used as a background, texture processor, or transparent effect overlay.
class MetalEffectView: UIView, MetalSnapshotProviding {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    let effect: MetalEffect
    var intensity: Float = 0.75 { didSet { needsFrame = true } }
    var onActivate: (() -> Void)?
    var onDissolveComplete: (() -> Void)?
    fileprivate var needsFrame = true
    private var texture: MTLTexture?
    private var lastUniforms: EffectUniforms?
    private var point = SIMD2<Float>(0.5, 0.5)
    private var eventTime: Float = -100
    private var dissolveStart: Float?
    private var dissolveProgress: Float = 0
    private var isTrackingTouch = false
    private let feedback = UIImpactFeedbackGenerator(style: .light)
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    static var isPaused: Bool {
        get { EffectClock.shared.paused }
        set { EffectClock.shared.paused = newValue }
    }

    fileprivate var isVisible: Bool {
        guard let window, !isHidden, alpha > 0 else { return false }
        var visibleRect = convert(bounds, to: window)
        var ancestor = superview
        while let parent = ancestor {
            if parent.isHidden || parent.alpha <= 0 { return false }
            if parent.clipsToBounds {
                visibleRect = visibleRect.intersection(parent.convert(parent.bounds, to: window))
                if visibleRect.isNull || visibleRect.isEmpty { return false }
            }
            ancestor = parent.superview
        }
        return visibleRect.intersects(window.bounds)
    }

    init(effect: MetalEffect) {
        self.effect = effect
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        metalLayer.device = MetalContext.shared.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.cornerRadius = 24
        metalLayer.masksToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        isMultipleTouchEnabled = false
        if let failure = MetalContext.shared.failure {
            let message = UILabel()
            message.text = failure
            message.textColor = .white
            message.numberOfLines = 0
            message.font = .preferredFont(forTextStyle: .caption1)
            message.translatesAutoresizingMaskIntoConstraints = false
            addSubview(message)
            NSLayoutConstraint.activate([
                message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
                message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
                message.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
            backgroundColor = UIColor(white: 0.1, alpha: 1)
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(effect:)") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { EffectClock.shared.add(self) }
        else { EffectClock.shared.remove(self) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(window?.screen.scale ?? traitCollection.displayScale, 2)
        metalLayer.contentsScale = scale
        let size = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size; needsFrame = true }
    }

    /// Capture only when the source changes or resizes, never on every display frame.
    @discardableResult
    func capture(_ source: UIView) -> Bool {
        guard let device = MetalContext.shared.device, source.bounds.width > 0,
              source.bounds.height > 0 else { return false }
        source.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .standard
        format.scale = min(traitCollection.displayScale, 2)
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: source.bounds, format: format).image { context in
            source.layer.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage else { return false }
        do {
            texture = try MTKTextureLoader(device: device).newTexture(cgImage: cgImage,
                options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft])
            needsFrame = true
            return true
        } catch {
            accessibilityValue = "Не удалось загрузить текстуру"
            return false
        }
    }

    func activate(at location: CGPoint? = nil) {
        if effect == .dissolve && (dissolveProgress > 0 || dissolveStart != nil) { return }
        if let location {
            point = SIMD2(Float(location.x / max(bounds.width, 1)), Float(location.y / max(bounds.height, 1)))
        }
        eventTime = EffectClock.shared.time
        needsFrame = true
        feedback.impactOccurred(intensity: CGFloat(intensity))
        if effect == .dissolve {
            if UIAccessibility.isReduceMotionEnabled {
                dissolveProgress = 1
                onDissolveComplete?()
            } else { dissolveStart = eventTime }
        }
        onActivate?()
    }

    func restore() {
        dissolveStart = nil
        dissolveProgress = 0
        needsFrame = true
    }

    override func accessibilityActivate() -> Bool { activate(); return true }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        isTrackingTouch = true
        feedback.prepare()
        updateTouch(touch)
        if effect == .pulse || effect == .glow { activate(at: touch.location(in: self)) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { updateTouch(touch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isTrackingTouch, let touch = touches.first, bounds.contains(touch.location(in: self)),
           effect != .pulse && effect != .glow { activate(at: touch.location(in: self)) }
        isTrackingTouch = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTrackingTouch = false
    }

    private func updateTouch(_ touch: UITouch) {
        let location = touch.location(in: self)
        point = SIMD2(Float(location.x / max(bounds.width, 1)), Float(location.y / max(bounds.height, 1)))
        needsFrame = true
    }

    fileprivate func drawFrame(time: Float, tilt: SIMD2<Float>) {
        let context = MetalContext.shared
        guard let pipeline = context.pipeline, let queue = context.queue,
              bounds.width > 0, bounds.height > 0,
              context.framesInFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = metalLayer.nextDrawable(), let command = queue.makeCommandBuffer() else {
            context.framesInFlight.signal()
            return
        }
        if let start = dissolveStart {
            dissolveProgress = min((time - start) / 1.8, 1)
            if dissolveProgress >= 1 {
                dissolveStart = nil
                onDissolveComplete?()
            }
        }
        let screenTilt: SIMD2<Float>
        switch window?.windowScene?.effectiveGeometry.interfaceOrientation {
        case .landscapeLeft: screenTilt = SIMD2(-tilt.y, tilt.x)
        case .landscapeRight: screenTilt = SIMD2(tilt.y, -tilt.x)
        case .portraitUpsideDown: screenTilt = -tilt
        default: screenTilt = tilt
        }
        var uniforms = EffectUniforms(
            viewport: SIMD4(Float(bounds.width), Float(bounds.height), time, intensity),
            input: SIMD4(point.x, point.y, screenTilt.x, screenTilt.y),
            state: SIMD4(Float(effect.rawValue), time - eventTime, dissolveProgress, 24),
            options: .zero)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            context.framesInFlight.signal()
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EffectUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture ?? context.placeholder, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        let semaphore = context.framesInFlight
        command.addCompletedHandler { _ in semaphore.signal() }
        command.present(drawable)
        command.commit()
        lastUniforms = uniforms
        needsFrame = false
    }

    func metalSnapshot() -> UIImage? {
        let context = MetalContext.shared
        guard let device = context.device, let queue = context.queue,
              let pipeline = context.pipeline else { return nil }
        var uniforms = lastUniforms ?? EffectUniforms(
            viewport: SIMD4(Float(bounds.width), Float(bounds.height), EffectClock.shared.time, intensity),
            input: SIMD4(point.x, point.y, 0, 0),
            state: SIMD4(Float(effect.rawValue), 100, dissolveProgress, 24), options: .zero)
        return MetalSnapshot.render(device: device, queue: queue, size: metalLayer.drawableSize) { encoder in
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EffectUniforms>.stride, index: 0)
            encoder.setFragmentTexture(texture ?? context.placeholder, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }
}
