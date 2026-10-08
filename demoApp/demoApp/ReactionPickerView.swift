//
//  ReactionPickerView.swift
//  demoApp
//

import UIKit

/// Реакция на пост: иконка, цвет кружка и подпись
enum ReactionType: CaseIterable {
    case helpful
    case insightful
    case supportive
    case celebrate
    case inspiring

    var title: String {
        switch self {
        case .helpful: return "Helpful"
        case .insightful: return "Insightful"
        case .supportive: return "Supportive"
        case .celebrate: return "Celebrate"
        case .inspiring: return "Inspiring"
        }
    }

    var symbolName: String {
        switch self {
        case .helpful: return "hand.thumbsup"
        case .insightful: return "lightbulb"
        // В SF Symbols нет «handshake», поэтому берём ближайший по смыслу
        case .supportive: return "hands.clap"
        case .celebrate: return "party.popper"
        case .inspiring: return "sparkles"
        }
    }

    var color: UIColor {
        switch self {
        case .helpful: return UIColor(red: 1.00, green: 0.62, blue: 0.30, alpha: 1)
        case .insightful: return UIColor(red: 0.42, green: 0.56, blue: 0.94, alpha: 1)
        case .supportive: return UIColor(red: 0.44, green: 0.80, blue: 0.62, alpha: 1)
        case .celebrate: return UIColor(red: 0.89, green: 0.47, blue: 0.68, alpha: 1)
        case .inspiring: return UIColor(red: 1.00, green: 0.36, blue: 0.24, alpha: 1)
        }
    }
}

extension ReactionType {
    /// Кружок реакции с иконкой: используется в дуге и для иконки, которая летит в пилюлю
    func makeBadge(diameter: CGFloat) -> UIView {
        let badge = UIView(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        badge.backgroundColor = color
        badge.layer.cornerRadius = diameter / 2

        let icon = UIImageView(
            image: UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        )
        icon.tintColor = .white
        icon.contentMode = .center
        icon.frame = badge.bounds
        badge.addSubview(icon)
        return badge
    }
}

/// Дуга с реакциями, которая раскрывается из пилюли.
/// Жесты не ловит: контроллер передаёт точку пальца через `updateSelection(at:)`
final class ReactionPickerView: UIView {

    private let anchor: CGPoint
    private let reactions: [ReactionType]
    private let counts: [ReactionType: Int]

    /// Радиус дуги от центра пилюли и размер кружка
    private let radius: CGFloat = 90
    private let buttonSize: CGFloat = 36
    private let bandWidth: CGFloat = 56
    /// Первый кружок слева вверху, далее шаг по дуге по часовой стрелке
    private let startAngle: CGFloat = -104 * .pi / 180
    private let angleStep: CGFloat = 29.5 * .pi / 180
    /// На каком расстоянии от кружка палец ещё выбирает его
    private let hitRadius: CGFloat = 50
    private let selectedScale: CGFloat = 1.25

    private let bandLayer = CAShapeLayer()
    private var buttons: [UIView] = []
    private var centers: [CGPoint] = []
    private let tooltip = UIView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let feedback = UISelectionFeedbackGenerator()

    private(set) var selectedIndex: Int?

    init(anchor: CGPoint, reactions: [ReactionType], counts: [ReactionType: Int]) {
        self.anchor = anchor
        self.reactions = reactions
        self.counts = counts
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        // Дуга лежит под кружками и «вырастает» при показе
        bandLayer.fillColor = nil
        bandLayer.strokeColor = UIColor(white: 0.12, alpha: 1).cgColor
        bandLayer.lineWidth = bandWidth
        bandLayer.lineCap = .round
        bandLayer.strokeEnd = 0
        layer.addSublayer(bandLayer)

        centers = reactions.indices.map { index in
            let angle = startAngle + CGFloat(index) * angleStep
            return CGPoint(x: anchor.x + radius * cos(angle), y: anchor.y + radius * sin(angle))
        }

        for reaction in reactions {
            let button = reaction.makeBadge(diameter: buttonSize)

            // Стартуем из точки нажатия: маленький и прозрачный
            button.layer.borderColor = UIColor.white.cgColor
            button.center = anchor
            button.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            button.alpha = 0
            addSubview(button)
            buttons.append(button)
        }

        tooltip.backgroundColor = UIColor(white: 0.12, alpha: 1)
        tooltip.layer.cornerRadius = 10
        tooltip.alpha = 0
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = UIColor(white: 1, alpha: 0.7)
        tooltip.addSubview(titleLabel)
        tooltip.addSubview(countLabel)
        addSubview(tooltip)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Дуга охватывает все кружки, с запасом по краям
        let padding: CGFloat = 10 * .pi / 180
        let endAngle = startAngle + CGFloat(reactions.count - 1) * angleStep

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bandLayer.frame = bounds
        bandLayer.path = UIBezierPath(
            arcCenter: anchor,
            radius: radius,
            startAngle: startAngle - padding,
            endAngle: endAngle + padding,
            clockwise: true
        ).cgPath
        CATransaction.commit()
    }

    // MARK: - Показ и выбор

    /// Дуга вырастает, кружки разлетаются с пружиной по очереди
    func show() {
        let grow = CABasicAnimation(keyPath: "strokeEnd")
        grow.fromValue = 0
        grow.toValue = 1
        grow.duration = 0.3
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        bandLayer.strokeEnd = 1
        bandLayer.add(grow, forKey: "grow")

        feedback.prepare()
        for (index, button) in buttons.enumerated() {
            UIView.animate(
                withDuration: 0.5,
                delay: 0.03 * Double(index),
                usingSpringWithDamping: 0.6,
                initialSpringVelocity: 0.8,
                options: [],
                animations: {
                    button.center = self.centers[index]
                    button.transform = .identity
                    button.alpha = 1
                }
            )
        }
    }

    /// Выбирает ближайший кружок к пальцу, если он достаточно близко
    func updateSelection(at point: CGPoint) {
        var nearest: Int?
        var nearestDistance = hitRadius
        for (index, center) in centers.enumerated() {
            let distance = hypot(point.x - center.x, point.y - center.y)
            if distance < nearestDistance {
                nearest = index
                nearestDistance = distance
            }
        }

        guard nearest != selectedIndex else { return }
        if nearest != nil {
            feedback.selectionChanged()
        }
        selectedIndex = nearest

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.55,
            initialSpringVelocity: 0.6,
            options: [.beginFromCurrentState],
            animations: {
                for (index, button) in self.buttons.enumerated() {
                    let isSelected = index == nearest
                    let scale = isSelected ? self.selectedScale : 1
                    button.transform = CGAffineTransform(scaleX: scale, y: scale)
                    // Белое кольцо вокруг выбранного кружка
                    button.layer.borderWidth = isSelected ? 2 : 0
                }
            }
        )
        updateTooltip()
    }

    /// Выбранная реакция и центр её кружка (координаты picker совпадают с координатами экрана)
    var selectedReaction: ReactionType? { selectedIndex.map { reactions[$0] } }
    var selectedCenter: CGPoint? { selectedIndex.map { buttons[$0].center } }

    /// Сворачивает дугу обратно в точку нажатия.
    /// При `commit` выбранный кружок сразу прячется: его место займёт летящая иконка в карточке
    func dismiss(commit: Bool) {
        if commit, let index = selectedIndex {
            buttons[index].alpha = 0
        }

        // Дуга втягивается к пилюле: конец штриха уходит к началу, как в видео
        let retract = CABasicAnimation(keyPath: "strokeEnd")
        retract.fromValue = bandLayer.strokeEnd
        retract.toValue = 0
        retract.duration = 0.25
        retract.timingFunction = CAMediaTimingFunction(name: .easeIn)
        bandLayer.strokeEnd = 0
        bandLayer.add(retract, forKey: "retract")

        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.curveEaseIn],
            animations: {
                for button in self.buttons {
                    button.center = self.anchor
                    button.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                    button.alpha = 0
                }
                self.tooltip.alpha = 0
            },
            completion: { _ in
                self.removeFromSuperview()
            }
        )
    }

    // MARK: - Подсказка над выбранным кружком

    private func updateTooltip() {
        guard let index = selectedIndex else {
            UIView.animate(withDuration: 0.15) { self.tooltip.alpha = 0 }
            return
        }

        let reaction = reactions[index]
        titleLabel.text = reaction.title
        countLabel.text = "\(counts[reaction, default: 0]) people"
        titleLabel.sizeToFit()
        countLabel.sizeToFit()

        let width = max(titleLabel.frame.width, countLabel.frame.width) + 20
        let height = titleLabel.frame.height + countLabel.frame.height + 10
        titleLabel.frame.origin = CGPoint(x: (width - titleLabel.frame.width) / 2, y: 5)
        countLabel.frame.origin = CGPoint(x: (width - countLabel.frame.width) / 2, y: 5 + titleLabel.frame.height)

        // Подсказка висит над кружком, но не выходит за края экрана
        let button = buttons[index]
        let x = min(max(button.center.x, width / 2 + 12), bounds.width - width / 2 - 12)
        let y = button.center.y - buttonSize * selectedScale / 2 - 10 - height / 2
        tooltip.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        tooltip.center = CGPoint(x: x, y: y)
        UIView.animate(withDuration: 0.15) { self.tooltip.alpha = 1 }
    }
}
