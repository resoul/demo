//
//  StandardMetaBallsView.swift
//  demo
//

import UIKit

/// Baseline implementation without private `CAFilter`s: the metaball field is recomputed on the
/// main thread every frame into a reduced-resolution bitmap, which a layer scales up with linear
/// filtering. The soft edge of the threshold gives the "gooey" look.
final class StandardMetaBallsView: DisplayLinkAnimationView {
    /// Points covered by one field sample.
    private let pointsPerSample: CGFloat = 2

    private var simulation = MetaBallSimulation()
    private let fieldLayer = CALayer()
    private var bitmap: CGContext?

    override var textureMemoryBytes: Int {
        bitmap.map { $0.bytesPerRow * $0.height } ?? 0
    }

    override func setUp() {
        backgroundColor = UIColor(red: 0.03, green: 0.035, blue: 0.05, alpha: 1)
        fieldLayer.contentsGravity = .resize
        fieldLayer.magnificationFilter = .linear
        layer.addSublayer(fieldLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fieldLayer.frame = bounds
        CATransaction.commit()

        let width = Int((bounds.width / pointsPerSample).rounded(.up))
        let height = Int((bounds.height / pointsPerSample).rounded(.up))
        guard bitmap?.width != width || bitmap?.height != height else { return }
        bitmap = width > 0 && height > 0 ? CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) : nil
    }

    override func renderFrame(time: CFTimeInterval, deltaTime: CFTimeInterval) {
        simulation.step(deltaTime: deltaTime, time: time, size: bounds.size, touch: touch)
        guard let bitmap else { return }
        rasterizeField(into: bitmap)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fieldLayer.contents = bitmap.makeImage()
        CATransaction.commit()
    }

    /// Evaluates the same field as `metaball_fragment`, one sample per `pointsPerSample`.
    private func rasterizeField(into bitmap: CGContext) {
        guard let data = bitmap.data else { return }

        // Field sources in sample space: (x, y, r²).
        var sources: [SIMD3<Float>] = simulation.blobs.map { blob in
            let r = simulation.radius(of: blob, progress: displayedProgress) / pointsPerSample
            return SIMD3(Float(blob.position.x / pointsPerSample), Float(blob.position.y / pointsPerSample), Float(r * r))
        }
        let touchRadius = simulation.touchRadius(touch) / pointsPerSample
        if touchRadius > 0.01 {
            sources.append(SIMD3(
                Float(touch.location.x / pointsPerSample),
                Float(touch.location.y / pointsPerSample),
                Float(touchRadius * touchRadius)
            ))
        }

        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let rowBytes = bitmap.bytesPerRow
        for y in 0..<bitmap.height {
            let py = Float(y) + 0.5
            let row = pixels + y * rowBytes
            for x in 0..<bitmap.width {
                let px = Float(x) + 0.5
                var field: Float = 0
                for source in sources {
                    let dx = px - source.x, dy = py - source.y
                    field += source.z / max(dx * dx + dy * dy, 0.25)
                }
                let alpha = smoothstep(Float(0.85), 1.15, field)
                // Premultiplied, brighter towards the blob cores.
                let shade = alpha * (0.55 + 0.45 * smoothstep(Float(1), 4, field))
                let i = x * 4
                row[i] = UInt8(shade * 0.72 * 255)
                row[i + 1] = UInt8(shade * 0.80 * 255)
                row[i + 2] = UInt8(shade * 0.92 * 255)
                row[i + 3] = UInt8(alpha * 255)
            }
        }
    }
}
