import UIKit

/// Public-API baseline: sample the same potential as Metal, then extract its
/// isocontour with marching triangles. No private Core Animation filters.
final class StandardMetaBallView: AnimationView {
    private let surface = CAGradientLayer()
    private let contour = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = UIColor(red: 0.025, green: 0.04, blue: 0.075, alpha: 1)
        accessibilityLabel = "Жидкие капли, UIKit"
        surface.colors = [UIColor.white.cgColor,
                          UIColor(red: 0.3, green: 0.92, blue: 0.95, alpha: 1).cgColor,
                          UIColor(red: 0.09, green: 0.23, blue: 0.47, alpha: 1).cgColor,
                          UIColor(red: 0.5, green: 0.94, blue: 0.95, alpha: 1).cgColor]
        surface.locations = [0, 0.24, 0.65, 1]
        surface.startPoint = CGPoint(x: 0.2, y: 0)
        surface.endPoint = CGPoint(x: 0.8, y: 1)
        surface.mask = contour
        layer.addSublayer(surface)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.frame = bounds
        contour.frame = bounds
        updateFrame(time: animationTime)
        CATransaction.commit()
    }

    override func updateFrame(time: CFTimeInterval) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let columns = max(24, min(96, Int(bounds.width / 4)))
        let rows = max(16, min(64, Int(bounds.height / 4)))
        let blobs = EffectDynamics.blobs(time: time, progress: progress, touch: interactionPoint, strength: interactionStrength)
        let aspect = bounds.width / bounds.height
        var values = [CGFloat](repeating: 0, count: (columns + 1) * (rows + 1))
        for y in 0...rows {
            for x in 0...columns {
                values[y * (columns + 1) + x] = EffectDynamics.potential(
                    at: CGPoint(x: CGFloat(x) / CGFloat(columns), y: CGFloat(y) / CGFloat(rows)),
                    blobs: blobs, aspect: aspect)
            }
        }
        let path = CGMutablePath()
        for y in 0..<rows {
            for x in 0..<columns {
                let ids = [y * (columns + 1) + x, y * (columns + 1) + x + 1,
                           (y + 1) * (columns + 1) + x + 1, (y + 1) * (columns + 1) + x]
                let points = [CGPoint(x: CGFloat(x), y: CGFloat(y)), CGPoint(x: CGFloat(x + 1), y: CGFloat(y)),
                              CGPoint(x: CGFloat(x + 1), y: CGFloat(y + 1)), CGPoint(x: CGFloat(x), y: CGFloat(y + 1))]
                    .map { CGPoint(x: $0.x / CGFloat(columns) * bounds.width, y: $0.y / CGFloat(rows) * bounds.height) }
                for triangle in [[0, 1, 2], [0, 2, 3]] {
                    var polygon: [CGPoint] = []
                    for edge in 0..<3 {
                        let a = triangle[edge], b = triangle[(edge + 1) % 3]
                        let va = values[ids[a]], vb = values[ids[b]]
                        if va >= 1 { polygon.append(points[a]) }
                        if (va >= 1) != (vb >= 1) {
                            let t = (1 - va) / (vb - va)
                            polygon.append(CGPoint(x: points[a].x + (points[b].x - points[a].x) * t,
                                                   y: points[a].y + (points[b].y - points[a].y) * t))
                        }
                    }
                    if let first = polygon.first {
                        path.move(to: first)
                        polygon.dropFirst().forEach { path.addLine(to: $0) }
                        path.closeSubpath()
                    }
                }
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contour.path = path
        CATransaction.commit()
    }
}
