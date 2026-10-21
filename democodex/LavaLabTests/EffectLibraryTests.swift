import XCTest
import MetalKit
@testable import democodex

final class EffectLibraryTests: XCTestCase {
    @MainActor
    func testAllTenViewsConformAndStopUpdating() async {
        for effect in AnimationEffect.allCases {
            for engine in LavaEngine.allCases {
                let view = effect.makeView(engine: engine)
                let component: any BenchmarkableAnimationView = view
                component.progress = 0.5
                view.externallyDriven = true
                view.frame = CGRect(x: 0, y: 0, width: 320, height: 220)
                view.layoutIfNeeded()
                component.startAnimation()
                view.render(time: 100)
                view.render(time: 100.016)
                XCTAssertTrue(view.isAnimating)
                XCTAssertEqual(view.animationTime, 0.016, accuracy: 0.0001)
                component.stopAnimation()
                view.render(time: 101)
                XCTAssertFalse(view.isAnimating)
                XCTAssertEqual(view.animationTime, 0.016, accuracy: 0.0001)
                if let metal = view as? MetalAnimationView {
                    XCTAssertTrue(metal.isAvailable, metal.unavailabilityReason ?? "Missing pipeline")
                }
            }
        }
    }

    @MainActor
    func testDragChangesWaterLevelAndReleaseDecays() async {
        for view: AnimationView in [StandardWaveView(), MetalWaveView()] {
            view.externallyDriven = true
            view.startAnimation()
            var reported: Float?
            view.onProgressChanged = { reported = $0 }
            view.updateInteraction(at: CGPoint(x: 0.8, y: 0.2), active: true)
            XCTAssertEqual(view.progress, 0.8, accuracy: 0.0001)
            XCTAssertEqual(reported!, 0.8, accuracy: 0.0001)
            view.render(time: 0)
            view.render(time: 0.05)
            XCTAssertEqual(view.interactionStrength, 1)
            view.updateInteraction(at: CGPoint(x: 0.8, y: 0.2), active: false)
            view.render(time: 0.1)
            XCTAssertLessThan(view.interactionStrength, 1)
            view.stopAnimation()
            XCTAssertEqual(view.interactionStrength, 0)
        }
    }

    func testAttractionMergesBlobCentersAndWavesHaveExactEndpoints() {
        let touch = CGPoint(x: 0.5, y: 0.5)
        let before = EffectDynamics.blobs(time: 1, progress: 0.5, touch: touch, strength: 0)
        let after = EffectDynamics.blobs(time: 1, progress: 0.5, touch: touch, strength: 1)
        for (a, b) in zip(before, after) {
            XCTAssertLessThan(hypot(b.center.x - touch.x, b.center.y - touch.y),
                              hypot(a.center.x - touch.x, a.center.y - touch.y))
        }
        XCTAssertGreaterThan(EffectDynamics.potential(at: touch, blobs: after, aspect: 1.5), 1)
        for x in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertEqual(EffectDynamics.waveHeight(x: x, time: 3, progress: 0, touch: touch, strength: 1), 1, accuracy: 0.0001)
            XCTAssertEqual(EffectDynamics.waveHeight(x: x, time: 3, progress: 1, touch: touch, strength: 1), 0, accuracy: 0.0001)
        }
    }

    @MainActor
    func testScreenReplacesViewsForEveryEffectAndEngine() async throws {
        let controller = BenchmarkViewController()
        controller.loadViewIfNeeded()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        defer {
            controller.beginAppearanceTransition(false, animated: false)
            controller.endAppearanceTransition()
        }
        func controls(in view: UIView) -> [UISegmentedControl] {
            (view as? UISegmentedControl).map { [$0] } ?? view.subviews.flatMap { controls(in: $0) }
        }
        let all = controls(in: controller.view)
        let effects = try XCTUnwrap(all.first { $0.numberOfSegments == 5 })
        let engines = try XCTUnwrap(all.first { $0.accessibilityLabel == "Режим отрисовки" })
        for index in AnimationEffect.allCases.indices {
            effects.selectedSegmentIndex = index
            effects.sendActions(for: .valueChanged)
            for engineIndex in 0...1 {
                let old = try XCTUnwrap(controller.activeAnimation)
                engines.selectedSegmentIndex = engineIndex
                engines.sendActions(for: .valueChanged)
                let new = try XCTUnwrap(controller.activeAnimation)
                XCTAssertFalse(old === new)
                XCTAssertNil(old.superview)
                XCTAssertFalse(old.isAnimating)
                XCTAssertTrue(new.isAnimating)
                XCTAssertEqual(new is MetalAnimationView, engineIndex == 1)
                XCTAssertEqual(new.progress, 0.68, accuracy: 0.0001)
            }
        }
        func buttons(in view: UIView) -> [UIButton] {
            (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let start = try XCTUnwrap(buttons(in: controller.view).first { $0.configuration?.title == "Запустить A/B-тест" })
        start.sendActions(for: .touchUpInside)
        XCTAssertFalse(effects.isEnabled)
        XCTAssertFalse(engines.isEnabled)
        XCTAssertFalse(controller.activeAnimation!.isUserInteractionEnabled)
        start.sendActions(for: .touchUpInside)
        XCTAssertTrue(effects.isEnabled)
        XCTAssertTrue(controller.activeAnimation!.isUserInteractionEnabled)
        start.sendActions(for: .touchUpInside)
        controller.scrollViewWillBeginDragging(UIScrollView())
        XCTAssertTrue(effects.isEnabled)
        XCTAssertTrue(controller.activeAnimation!.isUserInteractionEnabled)
    }

    @MainActor
    func testFirePausesParticleSimulationAndZeroIntensityHidesParticles() async {
        let view = StandardFireView()
        view.externallyDriven = true
        let emitters = view.layer.sublayers!.compactMap { $0 as? CAEmitterLayer }
        XCTAssertEqual(emitters.count, 3)
        view.startAnimation()
        XCTAssertTrue(emitters.allSatisfy { $0.speed == 1 && $0.birthRate > 0 })
        view.progress = 0
        XCTAssertTrue(emitters.allSatisfy { $0.isHidden && $0.birthRate == 0 })
        view.stopAnimation()
        XCTAssertTrue(emitters.allSatisfy { $0.speed == 0 && $0.birthRate == 0 })
    }

    @MainActor
    func testCSVIdentifiesSelectedEffect() async {
        let run = BenchmarkRun(firstEngine: .metal, requestedFPS: 60, progress: 0.4,
                               drawableSize: CGSize(width: 600, height: 400), effect: .fire)
        XCTAssertTrue(run.csv().contains("# effect,fire"))
    }

    @MainActor
    func testAllNewShadersRenderAnimateAndReactToTouch() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        XCTAssertEqual(MemoryLayout<EffectUniforms>.stride, 32)
        for name in ["waveFragment", "metaBallFragment", "plasmaFragment", "fireFragment"] {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "lavaVertex")
            descriptor.fragmentFunction = library.makeFunction(name: name)
            descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
            let pipeline = try await device.makeRenderPipelineState(descriptor: descriptor)
            let queue = try XCTUnwrap(device.makeCommandQueue())
            func render(progress: Float = 0.6, time: Float = 2, interaction: Float = 0) async throws -> [UInt8] {
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 96, height: 64, mipmapped: false)
                desc.storageMode = .shared
                desc.usage = [.renderTarget]
                let texture = try XCTUnwrap(device.makeTexture(descriptor: desc))
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = texture
                pass.colorAttachments[0].loadAction = .dontCare
                pass.colorAttachments[0].storeAction = .store
                let buffer = try XCTUnwrap(queue.makeCommandBuffer())
                let encoder = try XCTUnwrap(buffer.makeRenderCommandEncoder(descriptor: pass))
                var u = EffectUniforms(resolution: SIMD2(96, 64), progress: progress, time: time,
                                       touch: SIMD2(0.75, 0.4), interaction: interaction)
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentBytes(&u, length: MemoryLayout<EffectUniforms>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
                await withCheckedContinuation { continuation in
                    buffer.addCompletedHandler { _ in continuation.resume() }
                    buffer.commit()
                }
                XCTAssertEqual(buffer.status, .completed)
                var bytes = [UInt8](repeating: 0, count: 96 * 64 * 4)
                bytes.withUnsafeMutableBytes {
                    texture.getBytes($0.baseAddress!, bytesPerRow: 96 * 4,
                                     from: MTLRegionMake2D(0, 0, 96, 64), mipmapLevel: 0)
                }
                return bytes
            }
            let image = try await render()
            let later = try await render(time: 3)
            let touched = try await render(interaction: 1)
            XCTAssertNotEqual(image, later, "\(name) must animate")
            XCTAssertNotEqual(image, touched, "\(name) must react to touch")
            let zero = try await render(progress: 0)
            let full = try await render(progress: 1)
            XCTAssertNotEqual(zero, full, "\(name) must respond to progress/intensity")
            XCTAssertTrue(stride(from: 3, to: image.count, by: 4).allSatisfy { image[$0] == 255 })
            if name == "waveFragment" || name == "fireFragment" {
                XCTAssertTrue(stride(from: 0, to: zero.count, by: 4).allSatisfy { zero[$0] == zero[0] }, "Zero must be empty")
            }
        }
    }
}
