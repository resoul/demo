import XCTest
import MetalKit
import simd
@testable import democodex

final class MetalLabTests: XCTestCase {
    @MainActor
    func testTabsAndLabReplacementLifecycle() async throws {
        let tabs = MainTabBarController()
        tabs.loadViewIfNeeded()
        XCTAssertEqual(tabs.viewControllers?.count, 5)
        XCTAssertTrue(tabs.viewControllers?[0] is LavaProgressViewController)
        let lab = try XCTUnwrap(tabs.viewControllers?[1] as? MetalLabViewController)
        XCTAssertEqual(lab.tabBarItem.title, "Metal Lab")
        lab.loadViewIfNeeded()
        lab.beginAppearanceTransition(true, animated: false)
        lab.endAppearanceTransition()
        func descendants<T: UIView>(_ type: T.Type, _ view: UIView) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, $0) }
        }
        let control = try XCTUnwrap(descendants(UISegmentedControl.self, lab.view).first { $0.numberOfSegments == 3 })
        let slider = try XCTUnwrap(descendants(UISlider.self, lab.view).first)
        let particles = try XCTUnwrap(lab.activeEffectView as? MetalParticlesView)
        slider.value = 1_000_000
        slider.sendActions(for: .valueChanged)
        XCTAssertEqual(particles.particleCount, 1_000_000)
        XCTAssertEqual(particles.particleBuffer?.length, 16_000_000)
        slider.value = 10_000
        slider.sendActions(for: .valueChanged)
        XCTAssertEqual(particles.particleCount, 10_000)
        for index in 0..<3 {
            let old = try XCTUnwrap(lab.activeEffectView)
            control.selectedSegmentIndex = index
            control.sendActions(for: .valueChanged)
            let current = try XCTUnwrap(lab.activeEffectView)
            XCTAssertFalse(old === current)
            XCTAssertFalse(old.isAnimating)
            XCTAssertNil(old.superview)
            XCTAssertTrue(current.isAnimating)
            XCTAssertTrue(current.isAvailable, current.unavailabilityReason ?? "Missing pipeline")
            if let water = current as? MetalLiquidView { XCTAssertFalse(water.motionEnabled) }
        }
        lab.beginAppearanceTransition(false, animated: false)
        lab.endAppearanceTransition()
        XCTAssertFalse(lab.activeEffectView!.isAnimating)
    }

    @MainActor
    func testMainThreadCPUSamplerIsMonotonic() async throws {
        let profiler = PerformanceProfiler(cpuScope: .mainThread)
        let before = try XCTUnwrap(profiler.cpuSeconds())
        var work = 0.0
        for value in 1...10_000 { work += sqrt(Double(value)) }
        XCTAssertGreaterThan(work, 0)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(profiler.cpuSeconds()), before)
    }

    func testPresentationCounterRejectsPreviousGeneration() {
        let measurements = RenderMeasurements()
        let old = measurements.generation
        measurements.reset()
        measurements.recordPresentation(generation: old)
        measurements.recordPresentation(generation: measurements.generation)
        XCTAssertEqual(measurements.drain().presentedFrames, 1)
        XCTAssertEqual(measurements.drain().presentedFrames, 0)
    }

    @MainActor
    func testComputeUpdatesOnlyActiveParticlesAndForceDirection() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let seed = try await device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: "initializeParticles")))
        let simulate = try await device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: "simulateParticles")))
        let buffer = try XCTUnwrap(device.makeBuffer(length: 257 * 16, options: .storageModeShared))
        var capacity: UInt32 = 257
        let initialize = try XCTUnwrap(queue.makeCommandBuffer())
        let seedEncoder = try XCTUnwrap(initialize.makeComputeCommandEncoder())
        seedEncoder.setComputePipelineState(seed)
        seedEncoder.setBuffer(buffer, offset: 0, index: 0)
        seedEncoder.setBytes(&capacity, length: 4, index: 1)
        seedEncoder.dispatchThreads(MTLSize(width: 512, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
        seedEncoder.endEncoding()
        await complete(initialize)
        let initial = Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: SIMD4<Float>.self), count: 257))
        XCTAssertTrue(initial.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) })
        var outputs: [[SIMD4<Float>]] = []
        for force: Float in [1, -1] {
            _ = initial.withUnsafeBytes { memcpy(buffer.contents(), $0.baseAddress!, $0.count) }
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
            var u = ParticleSimulationUniforms(touch: SIMD2(0.8, 0.2), deltaTime: 1 / 60, aspect: 1,
                                               count: 129, time: 2, force: force, interaction: 1)
            XCTAssertEqual(MemoryLayout<ParticleSimulationUniforms>.stride, 32)
            encoder.setComputePipelineState(simulate)
            encoder.setBuffer(buffer, offset: 0, index: 0)
            encoder.setBytes(&u, length: MemoryLayout<ParticleSimulationUniforms>.stride, index: 1)
            encoder.dispatchThreads(MTLSize(width: 512, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
            encoder.endEncoding()
            await complete(command)
            XCTAssertEqual(command.status, .completed)
            let output = Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: SIMD4<Float>.self), count: 257))
            XCTAssertEqual(Array(output[129...]), Array(initial[129...]))
            XCTAssertNotEqual(output[128], initial[128])
            XCTAssertTrue(output.allSatisfy { $0.x.isFinite && $0.w.isFinite })
            outputs.append(output)
        }
        let deltaVelocity = SIMD2(outputs[0][10].z - outputs[1][10].z, outputs[0][10].w - outputs[1][10].w)
        let towards = SIMD2<Float>(0.8, 0.2) - SIMD2(initial[10].x, initial[10].y)
        XCTAssertGreaterThan(simd_dot(deltaVelocity, towards), 0)
    }

    @MainActor
    func testOneMillionParticlesActuallyComputeAndRender() async throws {
        let renderer = MetalParticlesView()
        XCTAssertTrue(renderer.isAvailable, renderer.unavailabilityReason ?? "Particles unavailable")
        renderer.particleCount = 1_000_000
        let queue = try XCTUnwrap(renderer.commandQueue)
        let device = queue.device
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "particlesVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "particlesFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        renderer.configurePipeline(descriptor)
        let pipeline = try await device.makeRenderPipelineState(descriptor: descriptor)
        let texture = try makeTexture(device)
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        var u = EffectUniforms(resolution: SIMD2(96, 96), progress: 1, time: 1,
                               touch: SIMD2(0.5, 0.5), interaction: 1)
        XCTAssertTrue(renderer.encodeSimulation(commandBuffer: command, uniforms: u))
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass(texture)))
        encoder.setRenderPipelineState(pipeline)
        renderer.encodeRender(encoder: encoder, uniforms: &u)
        encoder.endEncoding()
        await complete(command)
        XCTAssertEqual(command.status, .completed)
        let output = pixels(texture)
        let visiblePixels = stride(from: 0, to: output.count, by: 4).filter { output[$0] > 0 || output[$0 + 1] > 0 || output[$0 + 2] > 0 }.count
        XCTAssertGreaterThan(visiblePixels, 96 * 96 / 2, "A million initialized particles must populate the viewport")
        XCTAssertEqual(renderer.particleCount, 1_000_000)
    }

    @MainActor
    func testWaterAndVolumetricGlassRenderAndReact() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        for name in ["liquidWavesFragment", "glassRefractionFragment"] {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "lavaVertex")
            descriptor.fragmentFunction = library.makeFunction(name: name)
            descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
            let pipeline = try await device.makeRenderPipelineState(descriptor: descriptor)
            func render(time: Float = 2, touch: SIMD2<Float> = SIMD2(0.5, 0.5), tilt: Float = 0) async throws -> [UInt8] {
                let texture = try makeTexture(device)
                let command = try XCTUnwrap(queue.makeCommandBuffer())
                let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass(texture)))
                var u = EffectUniforms(resolution: SIMD2(96, 96), progress: 0.65, time: time,
                                       touch: touch, interaction: 1)
                var physics = LiquidPhysicsUniforms(tilt: SIMD2(tilt, 0), impulseTime: 1.7)
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentBytes(&u, length: 32, index: 0)
                if name == "liquidWavesFragment" { encoder.setFragmentBytes(&physics, length: 16, index: 1) }
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
                await complete(command)
                XCTAssertEqual(command.status, .completed)
                return pixels(texture)
            }
            let initial = try await render()
            let later = try await render(time: 3)
            let touched = try await render(touch: SIMD2(0.75, 0.4))
            XCTAssertNotEqual(initial, later, name)
            XCTAssertNotEqual(initial, touched, name)
            if name == "liquidWavesFragment" {
                let tilted = try await render(tilt: 0.6)
                XCTAssertNotEqual(initial, tilted)
            } else {
                let background = try await render(touch: SIMD2(5, 5))
                XCTAssertNotEqual(initial, background, "Refraction must change the scene")
                XCTAssertEqual(Array(initial.prefix(4)), Array(background.prefix(4)), "Pixels outside the lens stay unchanged")
            }
        }
    }

    private func makeTexture(_ device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 96, height: 96, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    private func pass(_ texture: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        return pass
    }

    private func pixels(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 96 * 96 * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: 96 * 4, from: MTLRegionMake2D(0, 0, 96, 96), mipmapLevel: 0)
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
