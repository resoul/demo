import XCTest
import MetalKit
@testable import democodex

final class LavaLabTests: XCTestCase {
    private func sample(duration: Double = 0.5, cpu: Double? = 10,
                        intervals: [Double] = Array(repeating: 1_000 / 60, count: 30)) -> PerformanceSnapshot {
        PerformanceSnapshot(duration: duration, frameIntervalsMS: intervals, cpuPercent: cpu,
                            render: RenderBatch(), thermalState: ProcessInfo.processInfo.thermalState.rawValue,
                            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    func testFrameStatisticsIncludeStalls() {
        let intervals = Array(repeating: 10.0, count: 18) + [30, 100]
        let snapshot = sample(intervals: intervals)
        XCTAssertEqual(snapshot.fps, 1_000 / 15.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.p95MS, 30)
        XCTAssertEqual([Double]().percentile95, 0)
    }

    func testAggregateUsesAllFramesAndTimeWeightedCPU() {
        let result = BenchmarkResult(engine: .uiKit, samples: [
            sample(duration: 1, cpu: 10, intervals: [10, 10]),
            sample(duration: 3, cpu: 30, intervals: [40])
        ])
        XCTAssertEqual(result.fps, 50, accuracy: 0.001)
        XCTAssertEqual(result.cpuPercent!, 25, accuracy: 0.001)
        XCTAssertNil(BenchmarkResult(engine: .uiKit, samples: [sample(cpu: nil)]).cpuPercent)
    }

    func testOldMetalCompletionsCannotContaminateNextMode() {
        let mailbox = RenderMeasurements()
        let old = mailbox.generation
        mailbox.recordCompletion(gpuMS: 99, latencyMS: 100, generation: old)
        mailbox.reset()
        mailbox.recordCPU(50, generation: old)
        mailbox.recordCompletion(gpuMS: 99, latencyMS: 100, generation: old)
        mailbox.recordFailure(generation: old)
        let current = mailbox.generation
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            mailbox.recordCompletion(gpuMS: 0.25, latencyMS: 2, generation: current)
        }
        let batch = mailbox.drain()
        XCTAssertEqual(batch.completedFrames, 200)
        XCTAssertEqual(batch.gpuMS.mean, 0.25)
        XCTAssertTrue(batch.cpuMS.isEmpty)
        XCTAssertEqual(batch.failedFrames, 0)
        XCTAssertEqual(mailbox.drain().completedFrames, 0)
    }

    func testRunExcludesWarmupAndMeasuresBothEngines() {
        let run = BenchmarkRun(firstEngine: .uiKit, requestedFPS: 60, progress: 0.68,
                               drawableSize: CGSize(width: 900, height: 264))
        for engine in [LavaEngine.uiKit, .metal] {
            XCTAssertEqual(run.engine, engine)
            for _ in 0..<3 { _ = run.consume(sample(cpu: 999)) }
            XCTAssertTrue(run.isWarmingUp)
            guard case .measurementStarted = run.consume(sample(cpu: 999)) else {
                return XCTFail("Warm-up must finish after two seconds")
            }
            for _ in 0..<19 { _ = run.consume(sample(cpu: 12)) }
            let event = run.consume(sample(cpu: 12))
            if engine == .uiKit {
                guard case .switchEngine(.metal) = event else { return XCTFail("Must switch engines") }
            } else {
                guard case .finished = event else { return XCTFail("Must finish") }
            }
        }
        XCTAssertEqual(run.results.count, 2)
        for result in run.results {
            XCTAssertEqual(result.duration, 10)
            XCTAssertEqual(result.samples.count, 20)
            XCTAssertEqual(result.cpuPercent!, 12, accuracy: 0.001)
        }
    }

    @MainActor
    func testCSVLeavesUnsupportedGPUEmpty() async {
        let run = BenchmarkRun(firstEngine: .uiKit, requestedFPS: 60, progress: 0.68, drawableSize: .zero)
        for _ in 0..<24 { _ = run.consume(sample()) }
        let csv = run.csv()
        let row = try! XCTUnwrap(csv.split(separator: "\n").first { $0.hasPrefix("UIKit,") })
        let fields = row.split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(fields[7], "")
        XCTAssertEqual(fields[8], "")
        XCTAssertEqual(fields[9], "")
        XCTAssertTrue(csv.contains("# requested_fps,60"))
        XCTAssertFalse(csv.contains("nan"))
    }

    @MainActor
    func testProgressHandlesEndpointsAndNonfiniteInput() async {
        let view = StandardLavaProgressBarView(frame: CGRect(x: 0, y: 0, width: 300, height: 88))
        for (input, expected) in [(Float(-1), Float(0)), (2, 1), (.nan, 0), (.infinity, 0), (0.68, 0.68)] {
            view.progress = input
            view.layoutIfNeeded()
            view.render(time: 1)
            XCTAssertEqual(view.progress, expected)
        }
    }

    @MainActor
    func testShaderCompilesAndProgressEndpointsRenderCorrectly() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "lavaVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "lavaFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        let pipeline = try await device.makeRenderPipelineState(descriptor: descriptor)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                        width: 64, height: 16, mipmapped: false)
        textureDescriptor.usage = [.renderTarget]
        textureDescriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: textureDescriptor))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        struct Uniforms { var resolution: SIMD2<Float>; var progress: Float; var time: Float }
        for progress: Float in [0, 0.5, 1] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            let buffer = try XCTUnwrap(queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(buffer.makeRenderCommandEncoder(descriptor: pass))
            var uniforms = Uniforms(resolution: SIMD2(64, 16), progress: progress, time: 1)
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            await buffer.commitAndComplete()
            XCTAssertEqual(buffer.status, .completed)
            var pixels = [UInt8](repeating: 0, count: 64 * 16 * 4)
            pixels.withUnsafeMutableBytes { bytes in
                texture.getBytes(bytes.baseAddress!, bytesPerRow: 64 * 4,
                                 from: MTLRegionMake2D(0, 0, 64, 16), mipmapLevel: 0)
            }
            // The rightmost pixel stays in the dark track until progress == 1.
            let right = (8 * 64 + 63) * 4
            if progress < 1 {
                XCTAssertLessThanOrEqual(abs(Int(pixels[right]) - 19), 1)
                XCTAssertLessThanOrEqual(abs(Int(pixels[right + 1]) - 11), 1)
            } else {
                XCTAssertGreaterThan(pixels[right], 30)
            }
            if progress == 0 {
                XCTAssertTrue(stride(from: 0, to: pixels.count, by: 4).allSatisfy { pixels[$0] == pixels[0] })
            }
        }
    }
}

private extension MTLCommandBuffer {
    func commitAndComplete() async {
        await withCheckedContinuation { continuation in
            addCompletedHandler { _ in continuation.resume() }
            commit()
        }
    }
}
