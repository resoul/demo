//
//  CornerShape.swift
//  demoApp
//

import UIKit

/// Стиль одного угла: выпуклое скругление или вырез по окружности вокруг угла
struct CornerStyle {
    var radius: CGFloat = 0
    var isConcave = false

    static let square = CornerStyle()

    /// Обычное скругление, как border radius
    static func rounded(_ radius: CGFloat) -> CornerStyle {
        CornerStyle(radius: radius, isConcave: false)
    }

    /// Вырез: угол вырезан дугой радиуса `radius` с центром в самом углу, внутрь фигуры
    static func cut(_ radius: CGFloat) -> CornerStyle {
        CornerStyle(radius: radius, isConcave: true)
    }
}

/// Прямоугольник, у каждого угла которого свой стиль. Получаются фигуры с углами больше четырёх,
/// например скругление снаружи и вырез под круглую кнопку в одном углу
struct CornerShape {
    var topLeft = CornerStyle.square
    var topRight = CornerStyle.square
    var bottomRight = CornerStyle.square
    var bottomLeft = CornerStyle.square

    /// Контур по часовой стрелке: сверху слева направо, потом вниз, снизу справа налево, потом вверх
    func path(in rect: CGRect) -> UIBezierPath {
        let x0 = rect.minX, y0 = rect.minY, x1 = rect.maxX, y1 = rect.maxY
        let path = UIBezierPath()

        path.move(to: CGPoint(x: x0 + topLeft.radius, y: y0))

        addCorner(to: path, style: topRight,
                  entry: CGPoint(x: x1 - topRight.radius, y: y0),
                  exit: CGPoint(x: x1, y: y0 + topRight.radius),
                  convexCenter: CGPoint(x: x1 - topRight.radius, y: y0 + topRight.radius),
                  cornerPoint: CGPoint(x: x1, y: y0))

        addCorner(to: path, style: bottomRight,
                  entry: CGPoint(x: x1, y: y1 - bottomRight.radius),
                  exit: CGPoint(x: x1 - bottomRight.radius, y: y1),
                  convexCenter: CGPoint(x: x1 - bottomRight.radius, y: y1 - bottomRight.radius),
                  cornerPoint: CGPoint(x: x1, y: y1))

        addCorner(to: path, style: bottomLeft,
                  entry: CGPoint(x: x0 + bottomLeft.radius, y: y1),
                  exit: CGPoint(x: x0, y: y1 - bottomLeft.radius),
                  convexCenter: CGPoint(x: x0 + bottomLeft.radius, y: y1 - bottomLeft.radius),
                  cornerPoint: CGPoint(x: x0, y: y1))

        addCorner(to: path, style: topLeft,
                  entry: CGPoint(x: x0, y: y0 + topLeft.radius),
                  exit: CGPoint(x: x0 + topLeft.radius, y: y0),
                  convexCenter: CGPoint(x: x0 + topLeft.radius, y: y0 + topLeft.radius),
                  cornerPoint: CGPoint(x: x0, y: y0))

        path.close()
        return path
    }

    /// Доводит линию до входа в угол и обходит угол короткой дугой.
    /// Для скругления центр дуги внутри фигуры, для выреза — в самом углу
    private func addCorner(to path: UIBezierPath, style: CornerStyle,
                           entry: CGPoint, exit: CGPoint,
                           convexCenter: CGPoint, cornerPoint: CGPoint) {
        path.addLine(to: entry)
        guard style.radius > 0 else {
            path.addLine(to: cornerPoint)
            return
        }

        let center = style.isConcave ? cornerPoint : convexCenter
        let start = atan2(entry.y - center.y, entry.x - center.x)
        let end = atan2(exit.y - center.y, exit.x - center.x)
        var delta = end - start
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        path.addArc(withCenter: center, radius: style.radius,
                    startAngle: start, endAngle: start + delta,
                    clockwise: delta > 0)
    }
}

/// View, у которого форма задаётся `CornerShape`: обрезает содержимое и рисует обводку по контуру
class ShapedView: UIView {

    var corners = CornerShape() {
        didSet { setNeedsLayout() }
    }

    var borderWidth: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    var borderColor: UIColor = .clear {
        didSet { borderLayer.strokeColor = borderColor.cgColor }
    }

    private let shapeMask = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        layer.mask = shapeMask
        borderLayer.fillColor = nil
        layer.addSublayer(borderLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Без этого CoreAnimation анимирует смену path при каждом layout
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        shapeMask.frame = bounds
        shapeMask.path = corners.path(in: bounds).cgPath

        // Обводка лежит внутри контура, иначе половина линии была бы обрезана маской
        let inset = borderWidth / 2
        borderLayer.frame = bounds
        borderLayer.path = corners.path(in: bounds.insetBy(dx: inset, dy: inset)).cgPath
        borderLayer.lineWidth = borderWidth
        borderLayer.strokeColor = borderColor.cgColor

        CATransaction.commit()
    }
}
