import Foundation
import Metal
import simd

// Runs the production MSL on the host GPU without relying on CoreSimulator/XCTest.
// This is a correctness check and offscreen benchmark, not an iPhone FPS claim.
struct CheckFailure: Error, CustomStringConvertible { let description: String }
func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(description: message) }
}

final class EngineChecks {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    init(path: String) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw CheckFailure(description: "A Metal GPU is required")
        }
        self.device = device; self.queue = queue
        library = try device.makeLibrary(URL: URL(fileURLWithPath: path))
    }
    func compute(_ name: String) throws -> MTLComputePipelineState {
        try device.makeComputePipelineState(function: library.makeFunction(name: name)!)
    }
    func pipeline(_ vertex: String, _ fragment: String, format: MTLPixelFormat = .bgra8Unorm) throws -> MTLRenderPipelineState {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: vertex)
        d.fragmentFunction = library.makeFunction(name: fragment)
        d.colorAttachments[0].pixelFormat = format
        return try device.makeRenderPipelineState(descriptor: d)
    }
    func texture(_ width: Int, _ height: Int, _ format: MTLPixelFormat, usage: MTLTextureUsage) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        d.storageMode = .shared; d.usage = usage
        return device.makeTexture(descriptor: d)!
    }
    func pass(_ texture: MTLTexture) -> MTLRenderPassDescriptor {
        let d = MTLRenderPassDescriptor()
        d.colorAttachments[0].texture = texture
        d.colorAttachments[0].loadAction = .clear
        d.colorAttachments[0].storeAction = .store
        return d
    }
    func submit(_ command: MTLCommandBuffer) throws {
        command.commit(); command.waitUntilCompleted()
        try check(command.status == .completed, command.error?.localizedDescription ?? "GPU command did not complete")
    }
    func bytes(_ texture: MTLTexture) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        data.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0) }
        return data
    }

    func testABI() throws {
        try check(MemoryLayout<SIMD2<Float>>.stride == 8, "XY sample stride")
        try check(MemoryLayout<ChartRangeNode>.stride == 8, "Min/max node stride")
        try check(MemoryLayout<ChartUniforms>.stride == 176, "Chart uniform stride")
        try check(MemoryLayout<ChartUniforms>.offset(of: \.domain) == 144, "Chart domain offset")
        try check(MemoryLayout<ChartUniforms>.offset(of: \.counts) == 160, "Chart counts offset")
        try check(MemoryLayout<TransitionUniforms>.stride == 32, "Transition uniform stride")
        try check(MemoryLayout<RainUniforms>.stride == 48, "Rain uniform stride")
        print("PASS shared C/Swift ABI")
    }

    func testLOD() throws {
        let count = 1_000_003, leaves = 1_048_576
        var input = (0..<count).map { SIMD2(Float($0), sin(Float($0) * 0.0003) * 0.3) }
        input[327_681].y = 50; input[327_682].y = -40
        let points = device.makeBuffer(length: leaves * 8, options: .storageModeShared)!
        input.withUnsafeBytes { points.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        let nodes = device.makeBuffer(length: leaves * 2 * MemoryLayout<ChartRangeNode>.stride, options: .storageModePrivate)!
        let write = try compute("chartWriteLeaves"), reduce = try compute("chartReduceLevel"), lodPipeline = try compute("chartPixelLOD")

        func rebuild(_ command: MTLCommandBuffer, dirty: Range<Int>) {
            let encoder = command.makeComputeCommandEncoder()!
            var r = ChartReductionUniforms()
            r.range = SIMD4(UInt32(dirty.lowerBound), UInt32(dirty.upperBound), UInt32(leaves), UInt32(input.count))
            encoder.setComputePipelineState(write)
            encoder.setBuffer(nodes, offset: 0, index: 0)
            encoder.setBytes(&r, length: MemoryLayout<ChartReductionUniforms>.stride, index: 1)
            encoder.dispatchThreads(MTLSize(width: dirty.count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 128, height: 1, depth: 1))
            encoder.memoryBarrier(scope: .buffers)
            var start = leaves + dirty.lowerBound, end = leaves + dirty.upperBound
            while start > 1 {
                start /= 2; end = (end + 1) / 2
                r.range.x = UInt32(start); r.range.y = UInt32(end)
                encoder.setComputePipelineState(reduce)
                encoder.setBuffer(points, offset: 0, index: 0)
                encoder.setBuffer(nodes, offset: 0, index: 1)
                encoder.setBytes(&r, length: MemoryLayout<ChartReductionUniforms>.stride, index: 2)
                encoder.dispatchThreads(MTLSize(width: end - start, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 128, height: 1, depth: 1))
                encoder.memoryBarrier(scope: .buffers)
            }
            encoder.endEncoding()
        }
        func query(_ domain: SIMD4<Float>, columns: Int, dirty: Range<Int>?) throws -> [SIMD2<Float>] {
            let command = queue.makeCommandBuffer()!
            if let dirty { rebuild(command, dirty: dirty) }
            let output = device.makeBuffer(length: columns * 2 * 8, options: .storageModeShared)!
            let encoder = command.makeComputeCommandEncoder()!
            var u = ChartUniforms()
            u.domain = domain; u.counts = SIMD4(UInt32(input.count), UInt32(leaves), UInt32(columns * 2), 0)
            encoder.setComputePipelineState(lodPipeline)
            encoder.setBuffer(points, offset: 0, index: 0)
            encoder.setBuffer(nodes, offset: 0, index: 1)
            encoder.setBuffer(output, offset: 0, index: 2)
            encoder.setBytes(&u, length: MemoryLayout<ChartUniforms>.stride, index: 3)
            encoder.dispatchThreads(MTLSize(width: columns, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 128, height: 1, depth: 1))
            encoder.endEncoding()
            try submit(command)
            return Array(UnsafeBufferPointer(start: output.contents().bindMemory(to: SIMD2<Float>.self, capacity: columns * 2), count: columns * 2))
        }
        func validate(_ output: [SIMD2<Float>], domain: SIMD4<Float>) throws {
            let columns = output.count / 2
            let step = (domain.y - domain.x) / Float(columns)
            for column in 0..<columns {
                let left = domain.x + Float(column) * step, right = domain.x + Float(column + 1) * step
                var lo = Int(ceil(left)), hi = Int(floor(right)) + 1
                lo = max(0, min(input.count, lo)); hi = max(0, min(input.count, hi))
                if column == 0 && lo > 0 { lo -= 1 }
                if column + 1 == columns && hi < input.count { hi += 1 }
                let pair = [output[column * 2], output[column * 2 + 1]]
                try check(pair[0].x <= pair[1].x, "LOD reordered extrema at column \(column)")
                if lo >= hi {
                    let point = input[min(lo, input.count - 1)]
                    try check(pair.allSatisfy { $0 == point }, "Empty bucket continuity")
                } else {
                    let ys = input[lo..<hi].map(\.y)
                    try check(abs(pair.map(\.y).min()! - ys.min()!) < 0.0001, "Minimum lost at column \(column)")
                    try check(abs(pair.map(\.y).max()! - ys.max()!) < 0.0001, "Maximum lost at column \(column)")
                }
            }
        }
        let domain = SIMD4<Float>(2, 1_000_002, -41, 51)
        let output = try query(domain, columns: 1000, dirty: 0..<leaves)
        try validate(output, domain: domain)
        try check(output.contains(where: { $0.y == 50 }) && output.contains(where: { $0.y == -40 }), "Narrow spike pair lost")
        try renderChart(output, domain: domain)
        let zoom = SIMD4<Float>(327_680, 327_690, -41, 51)
        try validate(query(zoom, columns: 100, dirty: nil), domain: zoom)
        let oldCount = input.count
        let tail = (0..<64).map { SIMD2(Float(oldCount + $0), $0 == 31 ? Float(80) : Float(-0.2)) }
        tail.withUnsafeBytes { points.contents().advanced(by: oldCount * 8).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        input.append(contentsOf: tail)
        let appendedDomain = SIMD4<Float>(Float(oldCount - 36), Float(oldCount + 64), -41, 81)
        try validate(query(appendedDomain, columns: 100, dirty: oldCount..<input.count), domain: appendedDomain)
        print("PASS 1,000,003-point min/max LOD, ordered spikes, empty buckets, dirty-tail streaming")
    }

    func renderChart(_ lod: [SIMD2<Float>], domain: SIMD4<Float>) throws {
        let buffer = lod.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)! }
        let scene = texture(256, 128, .rgba16Float, usage: [.renderTarget, .shaderRead])
        let ping = texture(128, 64, .rgba16Float, usage: [.shaderWrite, .shaderRead])
        let pong = texture(128, 64, .rgba16Float, usage: [.shaderWrite, .shaderRead])
        let target = texture(256, 128, .bgra8Unorm, usage: .renderTarget)
        var u = ChartUniforms()
        u.domain = domain; u.viewport = SIMD4(256, 128, 0, 0.8)
        u.counts = SIMD4(1_000_003, 1_048_576, UInt32(lod.count), 0)
        u.projection = simd_float4x4(columns: (SIMD4(2, 0, 0, 0), SIMD4(0, 2, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(-1, -1, 0, 1)))
        u.view = simd_float4x4(columns: (SIMD4(1 / (domain.y - domain.x), 0, 0, 0),
            SIMD4(0, 1 / (domain.w - domain.z), 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
        let command = queue.makeCommandBuffer()!
        let encoder = command.makeRenderCommandEncoder(descriptor: pass(scene))!
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&u, length: MemoryLayout<ChartUniforms>.stride, index: 1)
        encoder.setRenderPipelineState(try pipeline("chartFillVertex", "chartFillFragment", format: .rgba16Float))
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: lod.count * 2)
        encoder.setRenderPipelineState(try pipeline("chartLineVertex", "chartLineFragment", format: .rgba16Float))
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: lod.count)
        encoder.endEncoding()
        for (name, input, output) in [("bloomHorizontal", scene, ping), ("bloomVertical", ping, pong)] {
            let e = command.makeComputeCommandEncoder()!
            e.setComputePipelineState(try compute(name))
            e.setTexture(input, index: 0); e.setTexture(output, index: 1)
            e.dispatchThreads(MTLSize(width: 128, height: 64, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            e.endEncoding()
        }
        let composite = command.makeRenderCommandEncoder(descriptor: pass(target))!
        composite.setRenderPipelineState(try pipeline("engineFullscreenVertex", "chartComposite"))
        composite.setFragmentTexture(scene, index: 0); composite.setFragmentTexture(pong, index: 1)
        composite.setFragmentBytes(&u, length: MemoryLayout<ChartUniforms>.stride, index: 0)
        composite.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        composite.endEncoding(); try submit(command)
        let pixels = bytes(target)
        var foundSignal = false
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let green = Int(pixels[i + 1]), red = Int(pixels[i + 2])
            if green > 120 && green > red + 20 { foundSignal = true; break }
        }
        try check(foundSignal, "Chart line/fill/bloom composite produced no neon signal")
        print("PASS lineStrip + triangleStrip + HDR bloom composite")
    }

    func testTransitionsAndRain() throws {
        let a = texture(2, 2, .bgra8Unorm, usage: .shaderRead)
        let b = texture(2, 2, .bgra8Unorm, usage: .shaderRead)
        let red: [UInt8] = Array(repeating: [0, 0, 255, 255], count: 4).flatMap { $0 }
        let blue: [UInt8] = Array(repeating: [255, 0, 0, 255], count: 4).flatMap { $0 }
        red.withUnsafeBytes { a.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 8) }
        blue.withUnsafeBytes { b.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 8) }
        let target = texture(64, 32, .bgra8Unorm, usage: .renderTarget)
        let transition = try pipeline("engineFullscreenVertex", "screenTransition")
        for style in 0..<4 {
            for reversed in 0...1 {
                for progress: Float in [0, 0.5, 1] {
                    let command = queue.makeCommandBuffer()!, encoder = command.makeRenderCommandEncoder(descriptor: pass(target))!
                    var u = TransitionUniforms()
                    u.state = SIMD4(progress, Float(style), 0.5, 0.5)
                    u.viewport = SIMD4(64, 32, 0.25, Float(reversed))
                    encoder.setRenderPipelineState(transition)
                    encoder.setFragmentTexture(a, index: 0); encoder.setFragmentTexture(b, index: 1)
                    encoder.setFragmentBytes(&u, length: MemoryLayout<TransitionUniforms>.stride, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    encoder.endEncoding(); try submit(command)
                    let pixels = bytes(target)
                    if progress == 0 || progress == 1 {
                        let expected: [UInt8] = progress == 0 ? [0, 0, 255, 255] : [255, 0, 0, 255]
                        for i in stride(from: 0, to: pixels.count, by: 4) {
                            try check(Array(pixels[i..<i + 4]) == expected, "Transition endpoint style \(style), reverse \(reversed), progress \(progress)")
                        }
                    }
                }
            }
        }
        let rain = try pipeline("matrixRainVertex", "matrixRainFragment")
        let atlas = texture(16, 6, .rgba8Unorm, usage: .shaderRead)
        let white = [UInt8](repeating: 255, count: 16 * 6 * 4)
        white.withUnsafeBytes { atlas.replace(region: MTLRegionMake2D(0, 0, 16, 6), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 64) }
        let command = queue.makeCommandBuffer()!, encoder = command.makeRenderCommandEncoder(descriptor: pass(target))!
        var u = RainUniforms()
        u.viewport = SIMD4(64, 32, 3, 12); u.atlas = SIMD4(16, 6, 96, 8); u.appearance = SIMD4(8, 8, 13, 1)
        encoder.setRenderPipelineState(rain)
        encoder.setVertexBytes(&u, length: MemoryLayout<RainUniforms>.stride, index: 0)
        encoder.setFragmentTexture(atlas, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 32)
        encoder.endEncoding(); try submit(command)
        let pixels = bytes(target)
        try check(stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0 + 1] > pixels[$0 + 2] && pixels[$0 + 1] > 10 }, "Instanced rain produced no green glyphs")
        print("PASS transition endpoints/midpoints (all styles, both directions), instanced rain")
    }

    func testGaussian() throws {
        let source = texture(64, 32, .rgba16Float, usage: .shaderRead)
        let ping = texture(32, 16, .rgba16Float, usage: [.shaderRead, .shaderWrite])
        let pong = texture(32, 16, .rgba16Float, usage: [.shaderRead, .shaderWrite])
        let values = Array(repeating: [Float16(1), Float16(0.5), Float16(0.25), Float16(1)], count: 64 * 32).flatMap { $0 }
        values.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 64, 32), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 64 * 8) }
        let command = queue.makeCommandBuffer()!
        for (name, input, output) in [("bloomHorizontal", source, ping), ("bloomVertical", ping, pong)] {
            let encoder = command.makeComputeCommandEncoder()!
            encoder.setComputePipelineState(try compute(name))
            encoder.setTexture(input, index: 0); encoder.setTexture(output, index: 1)
            encoder.dispatchThreads(MTLSize(width: 32, height: 16, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            encoder.endEncoding()
        }
        try submit(command)
        var result = [Float16](repeating: 0, count: 32 * 16 * 4)
        result.withUnsafeMutableBytes { pong.getBytes($0.baseAddress!, bytesPerRow: 32 * 8,
            from: MTLRegionMake2D(0, 0, 32, 16), mipmapLevel: 0) }
        for i in result.indices { try check(abs(Float(result[i]) - Float(values[i % 4])) < 0.003, "Gaussian failed to preserve constant field/edge") }
        var impulse = [Float16](repeating: 0, count: 64 * 32 * 4)
        for y in 14...17 { for x in 30...33 { for c in 0..<4 { impulse[(y * 64 + x) * 4 + c] = 1 } } }
        impulse.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 64, 32), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 64 * 8) }
        let impulseCommand = queue.makeCommandBuffer()!
        for (name, input, output) in [("bloomHorizontal", source, ping), ("bloomVertical", ping, pong)] {
            let e = impulseCommand.makeComputeCommandEncoder()!
            e.setComputePipelineState(try compute(name))
            e.setTexture(input, index: 0); e.setTexture(output, index: 1)
            e.dispatchThreads(MTLSize(width: 32, height: 16, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            e.endEncoding()
        }
        try submit(impulseCommand)
        result.withUnsafeMutableBytes { pong.getBytes($0.baseAddress!, bytesPerRow: 32 * 8,
            from: MTLRegionMake2D(0, 0, 32, 16), mipmapLevel: 0) }
        try check(Float(result[(8 * 32 + 18) * 4]) > 0.005, "Bloom did not spread horizontally")
        try check(Float(result[(10 * 32 + 16) * 4]) > 0.005, "Bloom did not spread vertically")
        try check(Float(result[0]) < 0.00001, "Bloom leaked outside its kernel support")
        print("PASS normalized two-pass Gaussian, edge behavior, horizontal/vertical impulse spread")
    }
}

do {
    guard CommandLine.arguments.count == 2 else { throw CheckFailure(description: "Usage: MetalEngineChecks /path/to/default.metallib") }
    let checks = try EngineChecks(path: CommandLine.arguments[1])
    print("GPU: \(checks.device.name)")
    try checks.testABI()
    try checks.testLOD()
    try checks.testTransitionsAndRain()
    try checks.testGaussian()
    print("All Metal engine checks passed. 120 FPS still requires a physical ProMotion device benchmark.")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
