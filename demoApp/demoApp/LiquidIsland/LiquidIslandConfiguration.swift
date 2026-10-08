//
//  LiquidIslandConfiguration.swift
//  demoApp
//

import UIKit

/// Параметры эффекта Liquid Island. Читаются каждый кадр, поэтому правки из debug-панели действуют сразу
struct LiquidIslandConfiguration: Equatable {
    /// Расстояние от края капли до острова, на котором начинается притяжение, points
    var attractionRadius: CGFloat = 160
    /// Жёсткость пружины: насколько быстро капля возвращается и догоняет точку притяжения
    var springStiffness: CGFloat = 260
    /// Демпфирование пружины: больше — меньше колебаний
    var damping: CGFloat = 24
    /// Сила вытягивания капли к острову и по направлению движения, от 0 до 1
    var liquidStretch: CGFloat = 0.6
    /// Расстояние от края капли до острова, при котором отпускание приводит к поглощению, points
    var absorptionThreshold: CGFloat = 36
    /// Базовый радиус капли, points
    var dropRadius: CGFloat = 28
}
