//
//  LiquidPathBuilder.swift
//  demoApp
//

import UIKit

/// Строит кривые Безье для капли и перемычки по готовой форме `LiquidShape`. Используется всеми вью Liquid-эффектов
enum LiquidPathBuilder {

    /// Капля — эллипс, вытянутый вдоль direction. Короткая ось немного сужается, чтобы объём выглядел постоянным
    static func dropPath(_ shape: LiquidShape) -> UIBezierPath {
        let stretch = min(shape.elongation, 1)
        let halfLong = shape.radius * (1 + 0.6 * shape.elongation)
        let halfShort = shape.radius * (1 - 0.25 * stretch)
        let path = UIBezierPath(ovalIn: CGRect(x: -halfLong, y: -halfShort, width: halfLong * 2, height: halfShort * 2))

        let angle = atan2(shape.direction.y, shape.direction.x)
        let transform = CGAffineTransform(rotationAngle: angle)
            .concatenating(CGAffineTransform(translationX: shape.center.x, y: shape.center.y))
        path.apply(transform)
        return path
    }

    /// Перемычка по касательным двух окружностей: капли и точки крепления на краю.
    /// Ширина зависит от доли притяжения в квадрате: далеко перемычка тонкая, у края полная.
    /// Обе касательные лежат в одной плоскости, сверху и снизу, поэтому получается единая форма с вогнутыми боками.
    /// Возвращает nil, если перемычки не видно
    static func neckPath(_ shape: LiquidShape) -> UIBezierPath? {
        let r1 = shape.radius
        let r2 = shape.dockRadius * shape.neck
        let dx = shape.dock.x - shape.center.x
        let dy = shape.dock.y - shape.center.y
        let distance = hypot(dx, dy)

        // Перемычки нет, если окружности далеко друг от друга или одна полностью внутри другой
        guard r2 > 0.5, distance > 1, abs(r1 - r2) < distance else { return nil }

        let axis = atan2(dy, dx)
        let alpha0 = acos((r1 - r2) / distance)
        let alpha = alpha0 * shape.neck * shape.neck
        // Перемычка тоньше полпункта не рисуется: иначе в покое остаётся видимая нитка
        guard r1 * sin(alpha) > 0.5 else { return nil }
        let upper = axis + alpha
        let lower = axis - alpha

        let c1 = shape.center
        let c2 = shape.dock
        let p1Upper = CGPoint(x: c1.x + r1 * cos(upper), y: c1.y + r1 * sin(upper))
        let p1Lower = CGPoint(x: c1.x + r1 * cos(lower), y: c1.y + r1 * sin(lower))
        let p2Upper = CGPoint(x: c2.x + r2 * cos(upper), y: c2.y + r2 * sin(upper))
        let p2Lower = CGPoint(x: c2.x + r2 * cos(lower), y: c2.y + r2 * sin(lower))
        let control = CGPoint(x: (c1.x + c2.x) / 2, y: (c1.y + c2.y) / 2)

        let path = UIBezierPath()
        path.move(to: p1Upper)
        path.addQuadCurve(to: p2Upper, controlPoint: control)
        path.addLine(to: p2Lower)
        path.addQuadCurve(to: p1Lower, controlPoint: control)
        path.close()
        return path
    }

    /// Линия-капсула шириной width с головой в точке head. Хвост тянется назад от direction на tail.
    /// Ширина ограничена снизу, чтобы линия не пропадала совсем до конца движения
    static func streakPath(head: CGPoint, direction: CGPoint, width: CGFloat, tail: CGFloat) -> UIBezierPath {
        let w = max(3, width)
        // В локальных координатах голова в начале, хвост уходит в -y; потом поворачиваем так, чтобы -y совпал с хвостом
        let rect = CGRect(x: -w / 2, y: -tail, width: w, height: tail + w)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: w / 2)

        let trail = CGPoint(x: -direction.x, y: -direction.y)
        let angle = atan2(trail.x, -trail.y)
        path.apply(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: head.x, y: head.y)))
        return path
    }
}
