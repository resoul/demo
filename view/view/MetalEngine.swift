import UIKit
import MetalKit

enum MetalEngineError: LocalizedError {
    case unavailable, allocation, invalidPoints, capacity, busy, command(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Metal недоступен на этом устройстве."
        case .allocation: return "Недостаточно GPU-памяти."
        case .invalidPoints: return "Нужны минимум две конечные точки с возрастающей координатой X."
        case .capacity: return "Достигнута ёмкость буфера. Загрузите новый набор данных."
        case .busy: return "GPU занят. Повторите операцию."
        case .command(let message): return message
        }
    }
}

/// Shared device, queue, library and compiled pipeline cache for the engine page.
final class MetalEngine {
    static let shared: Result<MetalEngine, Error> = Result { try MetalEngine() }
    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    private var renders: [String: MTLRenderPipelineState] = [:]
    private var computes: [String: MTLComputePipelineState] = [:]

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw MetalEngineError.unavailable
        }
        self.device = device
        self.queue = queue
        library = try device.makeDefaultLibrary(bundle: Bundle(for: MetalChartView.self))
    }

    func render(vertex: String, fragment: String, format: MTLPixelFormat = .bgra8Unorm) throws -> MTLRenderPipelineState {
        let key = "\(vertex)/\(fragment)/\(format.rawValue)"
        if let pipeline = renders[key] { return pipeline }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = key
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = format
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        renders[key] = pipeline
        return pipeline
    }

    func compute(_ name: String) throws -> MTLComputePipelineState {
        if let pipeline = computes[name] { return pipeline }
        guard let function = library.makeFunction(name: name) else { throw MetalEngineError.unavailable }
        let pipeline = try device.makeComputePipelineState(function: function)
        computes[name] = pipeline
        return pipeline
    }

    func texture(width: Int, height: Int, format: MTLPixelFormat,
                 usage: MTLTextureUsage, storage: MTLStorageMode = .private) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
            width: max(width, 1), height: max(height, 1), mipmapped: false)
        descriptor.usage = usage
        descriptor.storageMode = storage
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw MetalEngineError.allocation }
        return texture
    }

    static func dispatch(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, count: Int) {
        encoder.setComputePipelineState(pipeline)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(128, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
    }

    static func pass(_ texture: MTLTexture, clear: MTLClearColor = MTLClearColorMake(0, 0, 0, 0)) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = clear
        return pass
    }
}

/// Explicit GPU readback is used only for screen transitions/diagnostics, never per frame.
@MainActor protocol MetalSnapshotProviding: AnyObject {
    func metalSnapshot() -> UIImage?
}

enum MetalSnapshot {
    static func render(device: MTLDevice, queue: MTLCommandQueue, size: CGSize,
                       encode: (MTLRenderCommandEncoder) -> Void) -> UIImage? {
        let width = max(1, Int(size.width)), height = max(1, Int(size.height))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .renderTarget
        guard let texture = device.makeTexture(descriptor: descriptor),
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: MetalEngine.pass(texture)) else { return nil }
        encode(encoder)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            texture.getBytes(bytes.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                    .union(.byteOrder32Little), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// UIKit cannot reliably capture CAMetalLayer contents. Replace those surfaces
    /// explicitly, then repaint later UIKit siblings so labels remain above their effects.
    static func capture(_ root: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .standard
        format.scale = min(root.window?.screen.scale ?? 2, 2)
        format.opaque = false
        return UIGraphicsImageRenderer(bounds: root.bounds, format: format).image { context in
            root.drawHierarchy(in: root.bounds, afterScreenUpdates: true)
            @MainActor func containsMetal(_ view: UIView) -> Bool {
                if view is MetalSnapshotProviding { return true }
                return view.subviews.contains { !$0.isHidden && containsMetal($0) }
            }
            @MainActor func draw(_ image: UIImage, in view: UIView) {
                context.cgContext.saveGState()
                var ancestor: UIView? = view
                while let parent = ancestor, parent !== root {
                    if parent.clipsToBounds { context.cgContext.clip(to: parent.convert(parent.bounds, to: root)) }
                    ancestor = parent.superview
                }
                let origin = view.convert(view.bounds.origin, to: root)
                let x = view.convert(CGPoint(x: view.bounds.minX + 1, y: view.bounds.minY), to: root)
                let y = view.convert(CGPoint(x: view.bounds.minX, y: view.bounds.minY + 1), to: root)
                context.cgContext.concatenate(CGAffineTransform(a: x.x - origin.x, b: x.y - origin.y,
                    c: y.x - origin.x, d: y.y - origin.y, tx: origin.x, ty: origin.y))
                image.draw(in: CGRect(origin: .zero, size: view.bounds.size), blendMode: .normal, alpha: view.alpha)
                context.cgContext.restoreGState()
            }
            @MainActor func patch(_ parent: UIView) {
                var hasPaintedMetal = false
                for child in parent.subviews where !child.isHidden && child.alpha > 0 && !child.bounds.isEmpty {
                    if !child.convert(child.bounds, to: root).intersects(root.bounds) { continue }
                    if let metal = child as? MetalSnapshotProviding, let image = metal.metalSnapshot() {
                        draw(image, in: child)
                        patch(child)
                        hasPaintedMetal = true
                    } else if containsMetal(child) {
                        let image = UIGraphicsImageRenderer(bounds: child.bounds, format: format).image { _ in
                            child.drawHierarchy(in: child.bounds, afterScreenUpdates: false)
                        }
                        draw(image, in: child)
                        patch(child)
                        hasPaintedMetal = true
                    } else if hasPaintedMetal {
                        let image = UIGraphicsImageRenderer(bounds: child.bounds, format: format).image { _ in
                            child.drawHierarchy(in: child.bounds, afterScreenUpdates: false)
                        }
                        draw(image, in: child)
                    }
                }
            }
            if let metal = root as? MetalSnapshotProviding, let image = metal.metalSnapshot() {
                image.draw(in: root.bounds)
            }
            patch(root)
        }
    }
}
