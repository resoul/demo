import XCTest
import MetalKit
import simd
@testable import democodex

final class GPUExperimentsTests: XCTestCase {
    @MainActor
    func testFiveTabsCatalogsReplacementAndPause() async throws {
        let tabs = MainTabBarController(); tabs.loadViewIfNeeded()
        XCTAssertEqual(tabs.viewControllers?.count, 5)
        XCTAssertTrue(tabs.viewControllers?[3] is GPUShowcaseViewController)
        XCTAssertTrue(tabs.viewControllers?[4] is ComputeBenchmarkViewController)
        for index in 3...4 {
            let controller = try XCTUnwrap(tabs.viewControllers?[index] as? GPUExperimentsViewController)
            controller.loadViewIfNeeded()
            controller.beginAppearanceTransition(true, animated: false); controller.endAppearanceTransition()
            XCTAssertEqual(controller.experiments.count, index == 3 ? 6 : 4)
            for effect in controller.experiments {
                let old = controller.activeExperimentView
                controller.selectExperiment(effect)
                XCTAssertEqual(controller.selectedExperiment, effect)
                XCTAssertFalse(old?.isAnimating ?? false)
                XCTAssertNil(old?.superview)
                let renderer = try XCTUnwrap(controller.activeExperimentView)
                XCTAssertTrue(renderer.isAvailable, renderer.unavailabilityReason ?? effect.title)
            }
            controller.beginAppearanceTransition(false, animated: false); controller.endAppearanceTransition()
            XCTAssertFalse(controller.activeExperimentView?.isAnimating ?? true)
        }
    }

    @MainActor
    func testEveryExperimentActuallyComputesAndRenders() async throws {
        XCTAssertEqual(MemoryLayout<ExperimentUniforms>.stride, 64)
        XCTAssertEqual(MemoryLayout<NBodyState>.stride, 32)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        for effect in GPUExperiment.allCases {
            let renderer = effect.makeView(); renderer.load = effect == .sph ? 1 : 0
            XCTAssertTrue(renderer.isAvailable, renderer.unavailabilityReason ?? effect.title)
            let queue = try XCTUnwrap(renderer.commandQueue)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: renderer.vertexFunctionName)
            descriptor.fragmentFunction = library.makeFunction(name: renderer.fragmentFunctionName)
            descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
            renderer.configurePipeline(descriptor)
            let pipeline = try await device.makeRenderPipelineState(descriptor: descriptor)
            var outputs: [[UInt8]] = []
            for frame in 0..<4 {
                let texture = try outputTexture(device)
                let command = try XCTUnwrap(queue.makeCommandBuffer())
                var u = EffectUniforms(resolution: SIMD2(96,96), progress: 0.5, time: Float(frame)/60,
                                       touch: SIMD2(0.45,0.55),interaction: frame < 2 ? 0 : 1)
                XCTAssertTrue(renderer.encodeSimulation(commandBuffer: command, uniforms: u), effect.title)
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = texture
                pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
                if descriptor.depthAttachmentPixelFormat != .invalid {
                    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,width: 96,height: 96,mipmapped: false)
                    d.usage = .renderTarget; d.storageMode = .private
                    pass.depthAttachment.texture = try XCTUnwrap(device.makeTexture(descriptor: d))
                    pass.depthAttachment.loadAction = .clear; pass.depthAttachment.clearDepth = 1
                }
                let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
                encoder.setRenderPipelineState(pipeline); renderer.encodeRender(encoder: encoder, uniforms: &u); encoder.endEncoding()
                await complete(command)
                XCTAssertEqual(command.status, .completed, "\(effect.title): \(String(describing: command.error))")
                outputs.append(pixels(texture))
            }
            let nonblack = stride(from: 0, to: outputs[3].count, by: 4).filter { outputs[3][$0] > 0 || outputs[3][$0+1] > 0 || outputs[3][$0+2] > 0 }.count
            XCTAssertGreaterThan(nonblack, 20, effect.title)
            XCTAssertNotEqual(outputs[0], outputs[3], "\(effect.title) must evolve or react")
            renderer.stopAnimation()
        }
    }

    @MainActor
    func testSpatialCountingSortPreservesEveryParticleIncludingPartialGroups() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice()), library = try XCTUnwrap(device.makeDefaultLibrary())
        let renderer = MetalAquariumView(); let queue = try XCTUnwrap(renderer.commandQueue)
        let count = 1_031, cells = 16*16
        var states = (0..<count).map { NBodyState.initial($0, count: count) }
        for i in states.indices { states[i].position = SIMD4(Float(i%31)/31,Float(i/31)/34,0,1) }
        let input = try XCTUnwrap(states.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!,length: $0.count,options: .storageModeShared) })
        func buffer(_ count: Int) throws -> MTLBuffer { try XCTUnwrap(device.makeBuffer(length: count*4, options: .storageModeShared)) }
        let histogram = try buffer(cells), cursors = try buffer(cells), a = try buffer(cells), b = try buffer(cells), sorted = try buffer(count)
        var u = ExperimentUniforms(); u.count = UInt32(count); u.side = 16; renderer.u = u
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let grid = MTLSize(width: cells,height: 1,depth: 1), particles = MTLSize(width: count,height: 1,depth: 1)
        XCTAssertTrue(renderer.dispatch("gridClear",command: command,size: grid,buffers: [histogram,cursors]))
        XCTAssertTrue(renderer.dispatch("gridHistogram",command: command,size: particles,buffers: [input,histogram]))
        XCTAssertTrue(renderer.dispatch("gridScan",command: command,size: grid,buffers: [histogram,a],scalar: 0))
        var source = a, target = b
        for stride: UInt32 in [1,2,4,8,16,32,64,128] {
            XCTAssertTrue(renderer.dispatch("gridScan",command: command,size: grid,buffers: [source,target],scalar: stride)); swap(&source,&target)
        }
        XCTAssertTrue(renderer.dispatch("gridScatter",command: command,size: particles,buffers: [input,histogram,source,cursors,sorted]))
        await complete(command); XCTAssertEqual(command.status,.completed)
        let offsets = source.contents().assumingMemoryBound(to: UInt32.self)
        let ids = Array(UnsafeBufferPointer(start: sorted.contents().assumingMemoryBound(to: UInt32.self),count: count))
        XCTAssertEqual(offsets[cells-1],UInt32(count)); XCTAssertEqual(Set(ids),Set((0..<count).map(UInt32.init)))
        var previous = 0
        for id in ids {
            let p = states[Int(id)].position
            let key = min(15,Int(p.y*16))*16+min(15,Int(p.x*16))
            XCTAssertGreaterThanOrEqual(key,previous); previous = key
        }
        XCTAssertNotNil(library.makeFunction(name: "sphDensity"))
        renderer.stressRange = true; renderer.load = 1; XCTAssertEqual(renderer.entityCount,100_000)
    }

    @MainActor
    func testNBodyGPUAgreesWithCPUSIMDForOneStep() async throws {
        let count = 512
        let worker = NBodyCPUWorker(); worker.reset(count: count); worker.requestStep()
        var result: NBodyCPUWorker.Result?
        for _ in 0..<300 {
            if let value = worker.takeResult() { result = value; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let cpu = try XCTUnwrap(result)
        let renderer = MetalNBodyView(); renderer.load = 0
        let device = try XCTUnwrap(renderer.commandQueue?.device), queue = try XCTUnwrap(renderer.commandQueue)
        let initial = (0..<count).map { NBodyState.initial($0,count: count) }
        let source = try XCTUnwrap(initial.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!,length: $0.count,options: .storageModeShared) })
        let target = try XCTUnwrap(device.makeBuffer(length: count*32,options: .storageModeShared))
        var u = ExperimentUniforms(); u.count = UInt32(count); u.dt = 1/120; renderer.u = u
        let command = try XCTUnwrap(queue.makeCommandBuffer()), size = MTLSize(width: count,height: 1,depth: 1)
        XCTAssertTrue(renderer.dispatch("nbodyStep",command: command,size: size,buffers: [source,target]))
        await complete(command); XCTAssertEqual(command.status,.completed)
        let gpu = target.contents().assumingMemoryBound(to: NBodyState.self)
        for i in 0..<count {
            XCTAssertLessThan(simd_length(gpu[i].position-cpu.states[i].position),0.0001)
            XCTAssertLessThan(simd_length(gpu[i].velocity-cpu.states[i].velocity),0.0001)
        }
    }

    func testThroughputUsesCompletedWorkAndHasNoInventedNumbers() {
        let meter = ExperimentThroughput()
        XCTAssertNil(meter.drain().gflops)
        meter.record(operations: 2e9,bytes: 4e9,seconds: 2)
        let sample = meter.drain(); XCTAssertEqual(sample.gflops,1); XCTAssertEqual(sample.gbps,2)
        XCTAssertNil(meter.drain().gbps)
    }

    private func outputTexture(_ device: MTLDevice) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,width: 96,height: 96,mipmapped: false)
        d.usage = [.renderTarget,.shaderRead]; d.storageMode = .shared
        return try XCTUnwrap(device.makeTexture(descriptor: d))
    }
    private func pixels(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0,count: texture.width*texture.height*4)
        texture.getBytes(&bytes,bytesPerRow: texture.width*4,from: MTLRegionMake2D(0,0,texture.width,texture.height),mipmapLevel: 0)
        return bytes
    }
    private func complete(_ command: MTLCommandBuffer) async {
        await withCheckedContinuation { continuation in command.addCompletedHandler { _ in continuation.resume() }; command.commit() }
    }
}
