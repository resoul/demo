//
//  MetaBallSimulation.swift
//  demo
//

import CoreGraphics
import Foundation

/// Blob motion shared by both metaball implementations, so they render the same scene and only
/// the rendering cost differs. Coordinates are in points, top-left origin.
struct MetaBallSimulation {
    struct Blob {
        var position: CGPoint
        var velocity: CGVector
        let sizeFactor: CGFloat
        let phase: CGFloat
    }

    static let blobCount = 5

    private(set) var blobs: [Blob] = []
    private var size: CGSize = .zero

    private var unit: CGFloat { min(size.width, size.height) }

    mutating func step(deltaTime: Double, time: Double, size newSize: CGSize, touch: TouchInput) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        if blobs.isEmpty {
            size = newSize
            spawnBlobs()
        } else if newSize != size {
            let sx = newSize.width / size.width, sy = newSize.height / size.height
            for i in blobs.indices {
                blobs[i].position.x *= sx
                blobs[i].position.y *= sy
            }
            size = newSize
        }

        let dt = CGFloat(deltaTime), t = CGFloat(time)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let attraction = CGFloat(touch.strength)
        let damping = exp(-dt * (1.0 + 3.0 * attraction))

        for i in blobs.indices {
            var blob = blobs[i]
            // Wander along slowly turning directions; a soft pull to the center keeps the group
            // together so blobs keep meeting and separating.
            let angle = t * 0.6 + blob.phase
            var ax = cos(angle) * unit * 0.9 + (center.x - blob.position.x) * 0.8
            var ay = sin(angle * 1.3) * unit * 0.9 + (center.y - blob.position.y) * 0.8
            // The finger is a strong spring: the blobs clump around it and merge like mercury.
            ax += (touch.location.x - blob.position.x) * 9 * attraction
            ay += (touch.location.y - blob.position.y) * 9 * attraction

            blob.velocity.dx = (blob.velocity.dx + ax * dt) * damping
            blob.velocity.dy = (blob.velocity.dy + ay * dt) * damping
            blob.position.x += blob.velocity.dx * dt
            blob.position.y += blob.velocity.dy * dt

            let r = unit * 0.1 * blob.sizeFactor
            if blob.position.x < r || blob.position.x > size.width - r {
                blob.position.x = min(max(blob.position.x, r), size.width - r)
                blob.velocity.dx = -blob.velocity.dx
            }
            if blob.position.y < r || blob.position.y > size.height - r {
                blob.position.y = min(max(blob.position.y, r), size.height - r)
                blob.velocity.dy = -blob.velocity.dy
            }
            blobs[i] = blob
        }
    }

    /// Progress scales the blobs, so higher values make them merge more often.
    func radius(of blob: Blob, progress: Float) -> CGFloat {
        unit * (0.07 + 0.08 * CGFloat(progress)) * blob.sizeFactor
    }

    /// While touching, the finger is an extra small blob (same formula as metaball_fragment).
    func touchRadius(_ touch: TouchInput) -> CGFloat {
        unit * 0.08 * CGFloat(touch.strength)
    }

    private mutating func spawnBlobs() {
        blobs = (0..<Self.blobCount).map { _ in
            Blob(
                position: CGPoint(
                    x: .random(in: size.width * 0.2...size.width * 0.8),
                    y: .random(in: size.height * 0.2...size.height * 0.8)
                ),
                velocity: CGVector(dx: .random(in: -1...1) * unit * 0.3, dy: .random(in: -1...1) * unit * 0.3),
                sizeFactor: .random(in: 0.8...1.25),
                phase: .random(in: 0...(2 * .pi))
            )
        }
    }
}
