import XCTest
import MetalKit
@testable import democodex

final class EmojiParticlesTests: XCTestCase {
    @MainActor
    func testAtlasCachesNativeGlyphsAndTransparentPadding() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let first = try EmojiTextureProvider.atlas(for: device)
        let second = try EmojiTextureProvider.atlas(for: device)
        XCTAssertTrue(first.texture === second.texture)
        XCTAssertEqual(first.symbols, ["🔥", "❤️", "🚀", "💥", "🦊"])
        XCTAssertEqual(first.texture.width, 640)
        XCTAssertEqual(first.texture.height, 128)
        let image = try await readTexture(first.texture, device: device)
        for tile in 0..<5 {
            var opaque = 0
            var transparent = 0
            for y in 0..<128 {
                for x in (tile * 128)..<((tile + 1) * 128) {
                    let alpha = image[(y * 640 + x) * 4 + 3]
                    if alpha > 20 { opaque += 1 }
                    if alpha == 0 { transparent += 1 }
                }
            }
            XCTAssertGreaterThan(opaque, 100, "Missing native emoji glyph")
            XCTAssertGreaterThan(transparent, 100, "Glyphs need transparent padding")
        }
        let singleA = try EmojiTextureProvider.texture(for: "🚀", device: device)
        let singleB = try EmojiTextureProvider.texture(for: "🚀", device: device)
        XCTAssertTrue(singleA === singleB)
        XCTAssertEqual(singleA.width, 128)
    }

    @MainActor
    func testGPUPhysicsModesVisibilityAndPartialThreadgroup() async throws {
        XCTAssertEqual(MemoryLayout<EmojiParticleState>.stride, 48)
        XCTAssertEqual(MemoryLayout<EmojiPhysicsUniforms>.stride, 80)
        XCTAssertEqual(MemoryLayout<EmojiRenderUniforms>.stride, 32)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let pipeline = try await device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: "simulateEmojiParticles")))
        let states = try XCTUnwrap(device.makeBuffer(length: 1024 * 48, options: .storageModeShared))
        let counter = try XCTUnwrap(device.makeBuffer(length: 4, options: .storageModeShared))
        var initial = [EmojiParticleState](repeating: EmojiParticleState(position: SIMD2(0.5, 0.5), velocity: .zero,
                           angle: 0, angularVelocity: 4, age: 0.5, lifetime: 2, emojiIndex: 0, burstID: 0, size: 1), count: 1024)
        for id in 500..<750 { initial[id].position.y = -0.3 }
        for id in 750..<1000 { initial[id].age = 3 }
        var uniform = EmojiPhysicsUniforms(emitter: SIMD2(0.5, 0.85), touch: SIMD2(0.4, 0.5), deltaTime: 0,
                  time: 1, aspect: 1, interaction: 0, count: 1000, mode: 0, burstID: 0, atlasCount: 5,
                  viewportSize: SIMD2(512, 512), gravity: 1, repulsion: 0.06, spriteSize: 32)
        func run() async throws -> [EmojiParticleState] {
            _ = initial.withUnsafeBytes { memcpy(states.contents(), $0.baseAddress!, $0.count) }
            counter.contents().storeBytes(of: UInt32(0), as: UInt32.self)
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(states, offset: 0, index: 0)
            encoder.setBytes(&uniform, length: 80, index: 1)
            encoder.setBuffer(counter, offset: 0, index: 2)
            encoder.dispatchThreadgroups(MTLSize(width: 4, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
            encoder.endEncoding()
            await complete(command)
            XCTAssertEqual(command.status, .completed)
            return Array(UnsafeBufferPointer(start: states.contents().assumingMemoryBound(to: EmojiParticleState.self), count: 1024))
        }
        for (mode, index) in [(UInt32(0), UInt32(0)), (1, 2), (2, 1)] {
            uniform.mode = mode
            let output = try await run()
            XCTAssertEqual(counter.contents().load(as: UInt32.self), 500)
            XCTAssertTrue(output.prefix(1000).allSatisfy { $0.emojiIndex == index })
            XCTAssertEqual(output[1000].position, initial[1000].position)
            XCTAssertEqual(output[1000].age, initial[1000].age)
            XCTAssertLessThan(output[800].age, 0.01, "Expired particles must respawn")
        }
        uniform.mode = 3
        let mixed = try await run()
        XCTAssertEqual(Set(mixed.prefix(500).map(\.emojiIndex)), Set(UInt32(0)...UInt32(4)))
        uniform.deltaTime = 1 / 60
        uniform.interaction = 1
        let moved = try await run()
        XCTAssertGreaterThan(moved[10].velocity.y, 0, "Gravity must accelerate downward")
        XCTAssertGreaterThan(moved[10].velocity.x, 0, "A touch to the left must repel right")
        XCTAssertGreaterThan(moved[10].angle, 0, "Quads must rotate")
    }

    @MainActor
    func testOneHundredThousandInstancedEmojiActuallyRenderAndReportCount() async throws {
        let renderer = MetalEmojiParticlesView()
        XCTAssertTrue(renderer.isAvailable, renderer.unavailabilityReason ?? "No emoji renderer")
        renderer.particleCount = 100_000
        renderer.spriteSizePixels = 16
        let queue = try XCTUnwrap(renderer.commandQueue)
        let device = queue.device
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "emojiVertex")
        desc.fragmentFunction = library.makeFunction(name: "emojiFragment")
        desc.colorAttachments[0].pixelFormat = .rgba8Unorm
        renderer.configurePipeline(desc)
        let pipeline = try await device.makeRenderPipelineState(descriptor: desc)
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 128, height: 128, mipmapped: false)
        textureDesc.usage = [.renderTarget]
        textureDesc.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: textureDesc))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        var u = EffectUniforms(resolution: SIMD2(128, 128), progress: 1, time: 1, touch: SIMD2(0.5, 0.85), interaction: 0)
        XCTAssertTrue(renderer.encodeSimulation(commandBuffer: command, uniforms: u))
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        renderer.encodeRender(encoder: encoder, uniforms: &u)
        encoder.endEncoding()
        renderer.encodePostRender(commandBuffer: command, uniforms: u)
        await complete(command)
        XCTAssertEqual(command.status, .completed)
        let active = try XCTUnwrap(renderer.measurements.drain().activeEntities)
        XCTAssertGreaterThan(active, 0)
        XCTAssertLessThanOrEqual(active, 100_000)
        var bytes = [UInt8](repeating: 0, count: 128 * 128 * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: 128 * 4, from: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0)
        }
        XCTAssertGreaterThan(stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 0 || bytes[$0 + 1] > 0 || bytes[$0 + 2] > 0 }.count, 500)
        XCTAssertEqual(renderer.particleBuffer?.length, 9_600_000)
    }

    @MainActor
    func testThirdTabControlsBurstPauseAndLifecycle() async throws {
        let tabs = MainTabBarController()
        tabs.loadViewIfNeeded()
        let controller = try XCTUnwrap(tabs.viewControllers?[2] as? EmojiParticlesViewController)
        controller.loadViewIfNeeded()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        let renderer = try XCTUnwrap(controller.particleView)
        XCTAssertTrue(renderer.isAnimating)
        func descendants<T: UIView>(_ type: T.Type, _ view: UIView) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, $0) }
        }
        let slider = try XCTUnwrap(descendants(UISlider.self, controller.view).first)
        slider.value = 200_000
        slider.sendActions(for: .valueChanged)
        XCTAssertEqual(renderer.particleCount, 200_000)
        slider.value = 1000
        slider.sendActions(for: .valueChanged)
        XCTAssertEqual(renderer.particleCount, 1000)
        let modes = try XCTUnwrap(descendants(UISegmentedControl.self, controller.view).first { $0.numberOfSegments == 4 })
        for mode in EmojiParticleMode.allCases {
            modes.selectedSegmentIndex = Int(mode.rawValue)
            modes.sendActions(for: .valueChanged)
            XCTAssertEqual(renderer.mode, mode)
        }
        let oldBurst = renderer.burstID
        renderer.updateInteraction(at: CGPoint(x: 0.2, y: 0.7), active: true)
        XCTAssertNotEqual(renderer.burstID, oldBurst)
        let pause = try XCTUnwrap(descendants(UIButton.self, controller.view).first { $0.configuration?.title == "Пауза" })
        pause.sendActions(for: .touchUpInside)
        XCTAssertFalse(renderer.isAnimating)
        pause.sendActions(for: .touchUpInside)
        XCTAssertTrue(renderer.isAnimating)
        controller.beginAppearanceTransition(false, animated: false)
        controller.endAppearanceTransition()
        XCTAssertFalse(renderer.isAnimating)
    }

    func testActiveCounterRejectsOldCompletionsAndPreservesZero() {
        let measurements = RenderMeasurements()
        let old = measurements.generation
        measurements.reset()
        measurements.recordActiveEntities(99_000, generation: old)
        XCTAssertNil(measurements.drain().activeEntities)
        measurements.recordActiveEntities(0, generation: measurements.generation)
        XCTAssertEqual(measurements.drain().activeEntities, 0)
    }

    private func readTexture(_ texture: MTLTexture, device: MTLDevice) async throws -> [UInt8] {
        let width = texture.width, height = texture.height
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: width, height: height, mipmapped: false)
        desc.storageMode = .shared
        let copy = try XCTUnwrap(device.makeTexture(descriptor: desc))
        let command = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeBlitCommandEncoder())
        encoder.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                     sourceSize: MTLSize(width: width, height: height, depth: 1), to: copy, destinationSlice: 0,
                     destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        encoder.endEncoding()
        await complete(command)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes {
            copy.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return bytes
    }

    private func complete(_ command: MTLCommandBuffer) async {
        await withCheckedContinuation { continuation in
            command.addCompletedHandler { _ in continuation.resume() }
            command.commit()
        }
    }
}
