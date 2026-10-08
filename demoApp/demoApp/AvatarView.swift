//
//  AvatarView.swift
//  demoApp
//

import UIKit

final class AvatarView: UIView {

    /// Вызывается при нажатии на кнопку редактирования
    var onEditTap: (() -> Void)?

    var image: UIImage? {
        get { photoView.image }
        set { photoView.image = newValue }
    }

    private let photoView = UIImageView()
    private let photoMask = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private let editButton = UIButton(type: .system)

    private let waveCount: CGFloat = 14
    private let waveAmplitude: CGFloat = 7
    /// Меньше 1 — вершины и ямки становятся шире и мягче
    private let wavePower: Double = 0.7
    private let ringLineWidth: CGFloat = 3
    /// Белая полоска между синей обводкой и фото
    private let whiteGap: CGFloat = 4
    private let editButtonSize: CGFloat = 36

    /// Базовые полуоси волнистой линии (эллипс), с запасом под амплитуду и толщину обводки
    private var ringRadii: CGSize {
        CGSize(
            width: bounds.width / 2 - waveAmplitude - 2,
            height: bounds.height / 2 - waveAmplitude - 2
        )
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.backgroundColor = .systemGray5
        photoView.layer.mask = photoMask
        addSubview(photoView)

        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = ringLineWidth
        layer.addSublayer(ringLayer)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        editButton.backgroundColor = .black
        editButton.tintColor = .white
        editButton.setImage(UIImage(systemName: "pencil", withConfiguration: symbolConfig), for: .normal)
        editButton.layer.cornerRadius = editButtonSize / 2
        editButton.layer.borderWidth = 2
        editButton.layer.borderColor = UIColor.systemBackground.cgColor
        editButton.accessibilityLabel = "Edit photo"
        editButton.addAction(UIAction { [weak self] _ in self?.onEditTap?() }, for: .touchUpInside)
        addSubview(editButton)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Без этого CoreAnimation анимирует смену path при каждом layout
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let path = wavyPath().cgPath

        photoView.frame = bounds
        photoMask.frame = bounds
        // Фото меньше обводки на её половину и белую полоску
        photoMask.path = wavyPath(offset: -(ringLineWidth / 2 + whiteGap)).cgPath

        ringLayer.frame = bounds
        ringLayer.path = path
        ringLayer.strokeColor = UIColor.systemBlue.cgColor

        // Кнопка на линии волны под 45°, в правом нижнем углу
        let angle = CGFloat.pi / 4
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radii = ringRadii
        let buttonCenter = CGPoint(
            x: center.x + radii.width * cos(angle),
            y: center.y + radii.height * sin(angle)
        )
        editButton.frame = CGRect(
            x: buttonCenter.x - editButtonSize / 2,
            y: buttonCenter.y - editButtonSize / 2,
            width: editButtonSize,
            height: editButtonSize
        )

        CATransaction.commit()
    }

    private func wavyPath(offset: CGFloat = 0) -> UIBezierPath {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radii = ringRadii
        let path = UIBezierPath()
        let steps = 360

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let s = sin(Double(waveCount * t))
            let shaped = CGFloat((s < 0 ? -1 : 1) * pow(abs(s), wavePower))
            let rx = radii.width + offset + waveAmplitude * shaped
            let ry = radii.height + offset + waveAmplitude * shaped
            let point = CGPoint(x: center.x + rx * cos(t), y: center.y + ry * sin(t))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.close()
        return path
    }
}
