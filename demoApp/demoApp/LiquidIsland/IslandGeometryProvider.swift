//
//  IslandGeometryProvider.swift
//  demoApp
//

import UIKit

/// Геометрия острова в координатах вью
struct IslandGeometry: Equatable {
    /// Прямоугольник острова; для системного острова это приближение, публичной геометрии у него нет
    var frame: CGRect
    /// true — остров нарисован системой, приложение его не рисует и не перехватывает касания внутри.
    /// false — острова нет (старый iPhone или симулятор без острова), тогда приложение рисует его само
    var isSystemIsland: Bool
}

/// Определяет положение острова через safe area и размеры экрана. Приватные API не используются
enum IslandGeometryProvider {

    /// Приближённые размеры острова в points
    struct Metrics: Equatable {
        var width: CGFloat
        var height: CGFloat
        /// Отступ верхнего края острова от верхнего края экрана
        var top: CGFloat
    }

    /// Значения для iPhone 14 Pro и новее. Системный остров примерно такого размера на всех моделях
    static let defaultMetrics = Metrics(width: 126, height: 37, top: 11)

    /// Отдельные размеры для конкретных моделей, ключ — ширина экрана в points.
    /// Заполняется, если на каком-то устройстве остров заметно отличается от значения по умолчанию
    static let metricsByScreenWidth: [CGFloat: Metrics] = [:]

    /// Верхний отступ safe area, начиная с которого на экране есть Dynamic Island
    private static let dynamicIslandSafeAreaTop: CGFloat = 51

    /// Геометрия острова для вью, которая занимает весь экран. Вызывать после layout: safeAreaInsets валидны только тогда
    static func geometry(in view: UIView) -> IslandGeometry {
        let width = view.bounds.width
        let metrics = metricsByScreenWidth[width] ?? defaultMetrics
        let frame = CGRect(
            x: (width - metrics.width) / 2,
            y: metrics.top,
            width: metrics.width,
            height: metrics.height
        )
        let isSystemIsland = view.safeAreaInsets.top >= dynamicIslandSafeAreaTop
        return IslandGeometry(frame: frame, isSystemIsland: isSystemIsland)
    }
}
