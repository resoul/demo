//
//  EmojiTextureProvider.swift
//  demo
//

import UIKit
import MetalKit

/// Renders emoji into a single texture atlas (one square cell per emoji, side by side), so every
/// emoji kind can be drawn with one texture binding and one draw call.
enum EmojiTextureProvider {
    struct Atlas {
        let texture: MTLTexture
        let emoji: [String]

        var columns: Int { emoji.count }

        /// Base level plus the mip chain (~1/3 extra).
        var byteCount: Int { texture.width * texture.height * 4 * 4 / 3 }
    }

    /// Draws each emoji with UIKit text rendering, then uploads the image with `MTKTextureLoader`
    /// (mipmapped, so tiny emoji stay smooth). Call once and keep the result.
    static func makeAtlas(emoji: [String], cellSize: Int = 128, device: MTLDevice) throws -> Atlas {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let cell = CGFloat(cellSize)
        let size = CGSize(width: cell * CGFloat(emoji.count), height: cell)

        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            // Leave a transparent margin so mip levels do not bleed between neighbouring cells.
            let font = UIFont.systemFont(ofSize: cell * 0.72)
            for (index, character) in emoji.enumerated() {
                let text = NSAttributedString(string: character, attributes: [.font: font])
                let textSize = text.size()
                text.draw(at: CGPoint(
                    x: CGFloat(index) * cell + (cell - textSize.width) / 2,
                    y: (cell - textSize.height) / 2
                ))
            }
        }

        guard let cgImage = image.cgImage else {
            throw CocoaError(.coderInvalidValue)
        }
        let loader = MTKTextureLoader(device: device)
        let texture = try loader.newTexture(cgImage: cgImage, options: [
            .SRGB: false,
            .generateMipmaps: true,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
        ])
        return Atlas(texture: texture, emoji: emoji)
    }
}
