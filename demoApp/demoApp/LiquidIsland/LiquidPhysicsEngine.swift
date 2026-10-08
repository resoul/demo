//
//  LiquidPhysicsEngine.swift
//  demoApp
//

import UIKit

/// Положение и скорость точки, которую тянет пружина
struct SpringState: Equatable {
    var position: CGPoint
    var velocity: CGPoint = .zero
}

/// Описание формы капли и перемычки на кадр. Считается из физического состояния, рисуется во вью
struct LiquidShape: Equatable {
    /// Центр капли
    var center: CGPoint
    /// Единичный вектор вытягивания: к острову, а вдали от острова — по направлению движения
    var direction: CGPoint
    /// Радиус капли с учётом масштаба
    var radius: CGFloat
    /// Вытягивание вдоль direction: 0 — круг, больше — капля вытянута
    var elongation: CGFloat
    /// Точка крепления перемычки на нижнем крае острова
    var dock: CGPoint
    /// Радиус точки крепления при полном соединении
    var dockRadius: CGFloat
    /// Доля притяжения: 0 — перемычки нет, 1 — капля касается острова
    var neck: CGFloat
    /// Капля видна; при масштабе около нуля её не рисуем
    var isVisible: Bool
}

/// Физика капли: пружины, притяжение к острову и деформация формы. Чистые функции, без состояния и UIKit-вью
enum LiquidPhysicsEngine {

    /// Доля пути до точки притяжения, которую капля проходит при полном притяжении
    static let magnetStrength: CGFloat = 0.7
    /// Зазор между нижним краем острова и каплей при притяжении, points
    static let dockGap: CGFloat = 10
    /// Радиус точки крепления перемычки у острова
    static let dockRadius: CGFloat = 20
    /// Отступ точки крепления от боковых краёв острова, чтобы перемычка не уходила за край
    static let dockInset: CGFloat = 16
    /// Пружина масштаба: появление, возврат размера и небольшой перелёт
    static let scaleStiffness: CGFloat = 320
    static let scaleDamping: CGFloat = 18

    // MARK: - Пружины

    /// Один шаг пружины по двум осям. Полуявная схема Эйлера, шаг дробится на части, чтобы пружина оставалась устойчивой
    static func stepSpring(_ spring: inout SpringState, target: CGPoint, stiffness: CGFloat, damping: CGFloat, dt: CGFloat) {
        let steps = max(1, Int((dt * 240).rounded(.up)))
        let h = dt / CGFloat(steps)
        for _ in 0..<steps {
            spring.velocity.x += (-stiffness * (spring.position.x - target.x) - damping * spring.velocity.x) * h
            spring.velocity.y += (-stiffness * (spring.position.y - target.y) - damping * spring.velocity.y) * h
            spring.position.x += spring.velocity.x * h
            spring.position.y += spring.velocity.y * h
        }
    }

    /// Пружина для одного числа, например масштаба
    static func stepSpring(value: inout CGFloat, velocity: inout CGFloat, target: CGFloat, stiffness: CGFloat, damping: CGFloat, dt: CGFloat) {
        let steps = max(1, Int((dt * 240).rounded(.up)))
        let h = dt / CGFloat(steps)
        for _ in 0..<steps {
            velocity += (-stiffness * (value - target) - damping * velocity) * h
            value += velocity * h
        }
    }

    // MARK: - Геометрия и притяжение

    /// Ближайшая точка прямоугольника к заданной точке
    static func nearestPoint(on rect: CGRect, to point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    /// Расстояние от края круга до прямоугольника; 0, если круг касается или перекрывает прямоугольник
    static func surfaceDistance(from center: CGPoint, radius: CGFloat, to rect: CGRect) -> CGFloat {
        let nearest = nearestPoint(on: rect, to: center)
        let gap = hypot(center.x - nearest.x, center.y - nearest.y) - radius
        return max(0, gap)
    }

    /// Доля притяжения 0...1 по расстоянию: 1 — вплотную к острову, 0 — за пределами радиуса.
    /// Smoothstep даёт плавный старт и плавное затухание без резких переходов
    static func attraction(distance: CGFloat, radius: CGFloat) -> CGFloat {
        guard radius > 0 else { return 0 }
        let t = min(max(1 - distance / radius, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Точка, к которой пружина тянет каплю во время удержания: под нижним краем острова, у ближайшей к пальцу точки по горизонтали.
    /// Чем ближе палец, тем сильнее смещение
    static func magneticTarget(pointer: CGPoint, island: CGRect, radius: CGFloat, attraction: CGFloat) -> CGPoint {
        let dock = CGPoint(
            x: min(max(pointer.x, island.minX), island.maxX),
            y: island.maxY + radius + dockGap
        )
        let k = magnetStrength * attraction
        return CGPoint(
            x: pointer.x + (dock.x - pointer.x) * k,
            y: pointer.y + (dock.y - pointer.y) * k
        )
    }

    // MARK: - Форма

    /// Форма капли и перемычки для текущего состояния.
    /// - Parameters:
    ///   - absorption: прогресс поглощения 0...1, добавляет вытягивание в конце пути к острову
    static func shape(
        center: CGPoint,
        velocity: CGPoint,
        scale: CGFloat,
        absorption: CGFloat,
        island: CGRect,
        configuration: LiquidIslandConfiguration
    ) -> LiquidShape {
        let radius = configuration.dropRadius * scale
        let distance = surfaceDistance(from: center, radius: radius, to: island)
        let neck = attraction(distance: distance, radius: configuration.attractionRadius)

        let dock = CGPoint(
            x: min(max(center.x, island.minX + dockInset), island.maxX - dockInset),
            y: island.maxY
        )

        let speed = hypot(velocity.x, velocity.y)
        let toDock = CGPoint(x: dock.x - center.x, y: dock.y - center.y)
        var direction = CGPoint(x: 0, y: -1)
        if neck > 0.01, hypot(toDock.x, toDock.y) > 0.5 {
            direction = normalized(toDock)
        } else if speed > 40 {
            direction = normalized(velocity)
        }

        // Вытягивание: от притяжения, от скорости и при поглощении. Liquid Stretch задаёт общую силу
        let velocityTerm = min(0.25, speed / 2500)
        let elongation = min(configuration.liquidStretch * (0.8 * neck + velocityTerm) + 0.5 * absorption, 1.2)

        return LiquidShape(
            center: center,
            direction: direction,
            radius: radius,
            elongation: elongation,
            dock: dock,
            dockRadius: dockRadius,
            neck: neck,
            isVisible: scale > 0.02
        )
    }

    /// Единичный вектор; нулевой вектор возвращается как есть
    private static func normalized(_ v: CGPoint) -> CGPoint {
        let length = hypot(v.x, v.y)
        guard length > 0 else { return v }
        return CGPoint(x: v.x / length, y: v.y / length)
    }
}
