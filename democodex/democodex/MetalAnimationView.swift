import UIKit
import MetalKit

struct EffectUniforms {
    var resolution: SIMD2<Float>
    var progress: Float
    var time: Float
    var touch: SIMD2<Float>
    var interaction: Float
    var padding: Float = 0
}

class MetalAnimationView: AnimationView, MTKViewDelegate {
    static var presentationMetricsAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }
    var fragmentFunctionName: String { "lavaFragment" }
    var vertexFunctionName: String { "lavaVertex" }
    var renderClearColor: MTLClearColor { MTLClearColorMake(0, 0, 0, 1) }
    private(set) var unavailabilityReason: String?
    var isAvailable: Bool { pipeline != nil }
    let measurements = RenderMeasurements()

    private var metalView: MTKView?
    private(set) var commandQueue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private let inFlight = DispatchSemaphore(value: 3)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isAccessibilityElement = true
        accessibilityLabel = "Прогресс, Metal"
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        clipsToBounds = true
        backgroundColor = UIColor(red: 0.075, green: 0.045, blue: 0.04, alpha: 1)
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            unavailabilityReason = "На этом устройстве Metal недоступен."
            return
        }
        do {
            guard let library = device.makeDefaultLibrary(),
                  let vertex = library.makeFunction(name: vertexFunctionName),
                  let fragment = library.makeFunction(name: fragmentFunctionName) else {
                unavailabilityReason = "Шейдер \(fragmentFunctionName) не найден в библиотеке приложения."
                return
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = fragmentFunctionName
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            configurePipeline(descriptor)
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            commandQueue = queue
            try prepareResources(device: device, library: library, queue: queue)
            let metalView = MTKView(frame: bounds, device: device)
            metalView.colorPixelFormat = .bgra8Unorm
            metalView.depthStencilPixelFormat = descriptor.depthAttachmentPixelFormat
            metalView.clearColor = renderClearColor
            metalView.framebufferOnly = true
            metalView.autoResizeDrawable = true
            metalView.isPaused = true
            metalView.enableSetNeedsDisplay = false
            metalView.isOpaque = true
            metalView.isUserInteractionEnabled = false
            metalView.delegate = self
            metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(metalView)
            self.metalView = metalView
            assert(MemoryLayout<EffectUniforms>.stride == 32)
        } catch {
            pipeline = nil
            unavailabilityReason = "Ошибка Metal pipeline: \(error.localizedDescription)"
        }
    }

    override func updateFrame(time: CFTimeInterval) {
        guard !isHidden, window != nil, isAvailable else { return }
        metalView?.draw()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard isAnimating else { return }
        // Skip instead of waiting on the in-flight semaphore. Drawable acquisition
        // below is still subject to the platform's presentation scheduling.
        guard inFlight.wait(timeout: .now()) == .success else { return }
        let start = CACurrentMediaTime()
        guard let pipeline, let queue = commandQueue,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        let generation = measurements.generation
        var uniforms = EffectUniforms(resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                                    progress: progress, time: Float(animationTime),
                                    touch: SIMD2(Float(interactionPoint.x), Float(interactionPoint.y)),
                                    interaction: interactionStrength)
        guard encodeSimulation(commandBuffer: buffer, uniforms: uniforms),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encodeRender(encoder: encoder, uniforms: &uniforms)
        encoder.endEncoding()
        encodePostRender(commandBuffer: buffer, uniforms: uniforms)
        let measurements = measurements
        #if !targetEnvironment(simulator)
        drawable.addPresentedHandler { drawable in
            if drawable.presentedTime > 0 { measurements.recordPresentation(generation: generation) }
        }
        #endif
        buffer.present(drawable)
        let semaphore = inFlight
        buffer.addCompletedHandler { command in
            defer { semaphore.signal() }
            guard command.status == .completed else {
                measurements.recordFailure(generation: generation)
                return
            }
            let gpuMS = command.gpuEndTime > command.gpuStartTime && command.gpuStartTime > 0
                ? (command.gpuEndTime - command.gpuStartTime) * 1_000 : nil
            measurements.recordCompletion(gpuMS: gpuMS,
                                          latencyMS: (CACurrentMediaTime() - start) * 1_000,
                                          generation: generation)
        }
        buffer.commit()
        measurements.recordCPU((CACurrentMediaTime() - start) * 1_000, generation: generation)
    }

    func configurePipeline(_ descriptor: MTLRenderPipelineDescriptor) {}
    func prepareResources(device: MTLDevice, library: MTLLibrary, queue: MTLCommandQueue) throws {}
    func encodeSimulation(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) -> Bool { true }
    func encodePostRender(commandBuffer: MTLCommandBuffer, uniforms: EffectUniforms) {}
    func encodeRender(encoder: MTLRenderCommandEncoder, uniforms: inout EffectUniforms) {
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EffectUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
