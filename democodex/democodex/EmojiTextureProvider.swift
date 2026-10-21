import UIKit
import MetalKit

struct EmojiTextureAtlas {
    let texture: MTLTexture
    let symbols: [String]
    let tileSize: Int
}

/// Native color glyphs are rasterized and uploaded only on cache misses.
/// One horizontal atlas lets all mixed emoji share a single draw call.
@MainActor
enum EmojiTextureProvider {
    nonisolated static let symbols = ["🔥", "❤️", "🚀", "💥", "🦊"]
    nonisolated static let tileSize = 128
    private struct Key: Hashable {
        let device: UInt64
        let symbols: [String]
    }
    private static var cache: [Key: EmojiTextureAtlas] = [:]

    static func texture(for emoji: String, device: MTLDevice) throws -> MTLTexture {
        try atlas(for: device, symbols: [emoji]).texture
    }

    static func atlas(for device: MTLDevice, symbols: [String] = EmojiTextureProvider.symbols) throws -> EmojiTextureAtlas {
        let key = Key(device: device.registryID, symbols: symbols)
        if let cached = cache[key] { return cached }
        guard !symbols.isEmpty else { throw MetalLabError.allocation }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(tileSize * symbols.count), height: CGFloat(tileSize)), format: format).image { _ in
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 92)]
            for (index, emoji) in symbols.enumerated() {
                let glyph = emoji as NSString
                let size = glyph.size(withAttributes: attributes)
                let origin = CGPoint(x: CGFloat(index * tileSize) + (CGFloat(tileSize) - size.width) / 2,
                                     y: (CGFloat(tileSize) - size.height) / 2)
                glyph.draw(at: origin, withAttributes: attributes)
            }
        }
        guard let cgImage = image.cgImage else { throw MetalLabError.allocation }
        let texture = try MTKTextureLoader(device: device).newTexture(cgImage: cgImage, options: [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft.rawValue,
            .generateMipmaps: true,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
        ])
        texture.label = "Cached native emoji atlas"
        let atlas = EmojiTextureAtlas(texture: texture, symbols: symbols, tileSize: tileSize)
        cache[key] = atlas
        return atlas
    }
}
