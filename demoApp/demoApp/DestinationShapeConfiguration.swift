//
//  DestinationShapeConfiguration.swift
//  demoApp
//

import UIKit

/// Вершина контура фото. Контур задаётся списком вершин, а скругление каждой вершины — дугой,
/// поэтому одинаково работают и выпуклые углы, и вогнутые ступени
struct ShapeVertex: Equatable {
    /// Положение вершины: доля ширины и высоты фото, от 0 до 1
    var x: CGFloat
    var y: CGFloat
    /// Радиус скругления в points; 0 — острый угол
    var radius: CGFloat
}

/// Параметры силуэта карточки. Меняются здесь, без правок геометрии в слое
struct DestinationShapeConfiguration: Equatable {
    /// Контур фото по часовой стрелке, начиная с верхней границы.
    /// Значения сняты с референса: ступенчатый левый край с двумя вогнутыми переходами
    var outline: [ShapeVertex] = [
        ShapeVertex(x: 0.48, y: 0.00, radius: 30),   // начало верхней границы фото
        ShapeVertex(x: 1.00, y: 0.00, radius: 22),   // верхний правый угол
        ShapeVertex(x: 1.00, y: 1.00, radius: 18),   // нижний правый угол
        ShapeVertex(x: 0.05, y: 1.00, radius: 30),   // нижний левый угол
        ShapeVertex(x: 0.05, y: 0.455, radius: 20),  // верх нижнего блока
        ShapeVertex(x: 0.215, y: 0.41, radius: 28),  // вогнутый переход на нижнюю ступень: ниже и резче
        ShapeVertex(x: 0.215, y: 0.132, radius: 29), // угол колонки и полки под верхней ступенью
        ShapeVertex(x: 0.46, y: 0.12, radius: 30),   // вогнутый переход на верхнюю границу
    ]

    /// Отступы фото от краёв карточки: сверху и справа остаётся белая рамка, как на референсе
    var imageInsets = UIEdgeInsets(top: 18, left: 0, bottom: 10, right: 16)

    /// Радиус внешних углов карточки
    var cardCornerRadius: CGFloat = 16

    /// Тень фото: повторяет его силуэт, лежит под фото на белой карточке
    var imageShadowOpacity: Float = 0.18
    var imageShadowRadius: CGFloat = 8
    var imageShadowOffset = CGSize(width: 0, height: 4)
}

// MARK: - Готовые силуэты

extension DestinationShapeConfiguration {

    /// Ступенчатый вырез сверху слева, как на референсе
    static let stepped = DestinationShapeConfiguration()

    /// Один прямоугольный вырез сверху слева со скруглёнными углами вместо ступеней.
    /// `width` и `height` — размер выреза в долях фото
    static func squareNotch(width: CGFloat = 0.48, height: CGFloat = 0.155) -> DestinationShapeConfiguration {
        var configuration = DestinationShapeConfiguration()
        configuration.outline = [
            ShapeVertex(x: width, y: 0.00, radius: 30),    // начало верхней границы фото
            ShapeVertex(x: 1.00, y: 0.00, radius: 22),     // верхний правый угол
            ShapeVertex(x: 1.00, y: 1.00, radius: 18),     // нижний правый угол
            ShapeVertex(x: 0.05, y: 1.00, radius: 30),     // нижний левый угол
            ShapeVertex(x: 0.05, y: height, radius: 24),   // низ выреза у левого края
            ShapeVertex(x: width, y: height, radius: 30),  // внутренний угол выреза, вогнутый
        ]
        return configuration
    }
}
