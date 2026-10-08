//
//  DestinationImageShapeLayer.swift
//  demoApp
//

import UIKit

/// Маска фото по списку вершин: каждая вершина скругляется дугой, касательной к обеим сторонам.
/// Один слой на жизненный цикл карточки: при layout меняется только path, и только если изменился размер или параметры
final class DestinationImageShapeLayer: CAShapeLayer {

    var configuration = DestinationShapeConfiguration() {
        didSet { builtSize = .zero }
    }

    private var builtSize: CGSize = .zero

    override init() {
        super.init()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Перестраивает контур под размер фото, если он изменился
    func update(size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            path = nil
            return
        }
        guard size != builtSize else { return }
        builtSize = size
        path = makePath(in: CGRect(origin: .zero, size: size)).cgPath
    }

    // MARK: - Геометрия

    /// Дуга скругления одной вершины
    private struct Fillet {
        /// Точка, где дуга касается входящей стороны
        var start: CGPoint
        /// Точка касания исходящей стороны
        var end: CGPoint
        var center: CGPoint
        var radius: CGFloat
        var startAngle: CGFloat
        /// Угол дуги со знаком: положительный — по часовой стрелке. 0 — угол острый, дуги нет
        var delta: CGFloat
    }

    private func makePath(in rect: CGRect) -> UIBezierPath {
        let vertices = configuration.outline
        guard vertices.count >= 3 else { return UIBezierPath(rect: rect) }

        // Вершины переводим из долей в координаты фото
        let points = vertices.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }

        let path = UIBezierPath()
        for index in points.indices {
            let previous = points[(index - 1 + points.count) % points.count]
            let next = points[(index + 1) % points.count]
            let fillet = makeFillet(previous: previous, at: points[index], next: next, radius: vertices[index].radius)

            if index == 0 {
                path.move(to: fillet.start)
            } else {
                path.addLine(to: fillet.start)
            }
            if fillet.delta != 0 {
                path.addArc(withCenter: fillet.center, radius: fillet.radius,
                            startAngle: fillet.startAngle, endAngle: fillet.startAngle + fillet.delta,
                            clockwise: fillet.delta > 0)
            }
        }
        path.close()
        return path
    }

    /// Дуга радиуса `radius`, касательная к обеим сторонам вершины `p`.
    /// Касательные точки не дальше половины соседних сторон, поэтому острые вершины не ломают контур
    private func makeFillet(previous: CGPoint, at p: CGPoint, next: CGPoint, radius: CGFloat) -> Fillet {
        let flat = Fillet(start: p, end: p, center: p, radius: 0, startAngle: 0, delta: 0)
        guard radius > 0 else { return flat }

        let toPrevious = CGPoint(x: previous.x - p.x, y: previous.y - p.y)
        let toNext = CGPoint(x: next.x - p.x, y: next.y - p.y)
        let lengthPrevious = hypot(toPrevious.x, toPrevious.y)
        let lengthNext = hypot(toNext.x, toNext.y)
        guard lengthPrevious > 0, lengthNext > 0 else { return flat }

        // Единичные направления от вершины к соседям
        let a = CGPoint(x: toPrevious.x / lengthPrevious, y: toPrevious.y / lengthPrevious)
        let b = CGPoint(x: toNext.x / lengthNext, y: toNext.y / lengthNext)
        let cosine = max(-1, min(1, a.x * b.x + a.y * b.y))
        let angle = acos(cosine)
        guard angle > 0.001, angle < .pi - 0.001 else { return flat }

        let half = angle / 2
        var tangentLength = radius / tan(half)
        tangentLength = min(tangentLength, lengthPrevious / 2, lengthNext / 2)
        let effectiveRadius = tangentLength * tan(half)

        let start = CGPoint(x: p.x + a.x * tangentLength, y: p.y + a.y * tangentLength)
        let end = CGPoint(x: p.x + b.x * tangentLength, y: p.y + b.y * tangentLength)

        // Центр дуги лежит на биссектрисе угла между сторонами
        let bisector = CGPoint(x: a.x + b.x, y: a.y + b.y)
        let bisectorLength = hypot(bisector.x, bisector.y)
        let distance = effectiveRadius / sin(half)
        let center = CGPoint(
            x: p.x + bisector.x / bisectorLength * distance,
            y: p.y + bisector.y / bisectorLength * distance
        )

        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)
        var delta = endAngle - startAngle
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        return Fillet(start: start, end: end, center: center, radius: effectiveRadius,
                      startAngle: startAngle, delta: delta)
    }
}
