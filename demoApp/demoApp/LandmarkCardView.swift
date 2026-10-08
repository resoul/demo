//
//  LandmarkCardView.swift
//  demoApp
//

import UIKit

/// Карточка места: фото с вырезами в правых углах, плашка с городом сверху слева и стеклянная плашка места снизу
final class LandmarkCardView: ShapedView {

    private let photo = GradientCardView()
    private let cityPill = UIView()
    private let placeChip = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))

    init(city: String, place: String) {
        super.init(frame: .zero)
        setup(city: city, place: place)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(city: String, place: String) {
        // Левые углы скруглены, правые вырезаны дугами: верхний угол глубже нижнего
        corners = CornerShape(
            topLeft: .rounded(20),
            topRight: .cut(64),
            bottomRight: .cut(48),
            bottomLeft: .rounded(20)
        )

        photo.colors = [
            UIColor(red: 0.80, green: 0.86, blue: 0.90, alpha: 1),
            UIColor(red: 0.12, green: 0.38, blue: 0.52, alpha: 1),
            UIColor(red: 0.22, green: 0.42, blue: 0.24, alpha: 1),
        ]
        addSubview(photo)
        photo.translatesAutoresizingMaskIntoConstraints = false
        pin(photo, to: self)

        // Город: белая капсула с иконкой
        let pinIcon = UIImageView(image: UIImage(systemName: "mappin.and.ellipse"))
        pinIcon.tintColor = .black
        let cityLabel = UILabel()
        cityLabel.text = city
        cityLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        let cityRow = UIStackView(arrangedSubviews: [pinIcon, cityLabel])
        cityRow.spacing = 6
        cityRow.alignment = .center
        cityPill.backgroundColor = .white
        cityPill.layer.cornerRadius = 18
        cityPill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cityPill)
        pin(cityRow, to: cityPill, insets: UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14))
        NSLayoutConstraint.activate([
            cityPill.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            cityPill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
        ])

        // Место: стеклянная капсула внизу слева
        let buildingIcon = UIImageView(image: UIImage(systemName: "building.columns.fill"))
        buildingIcon.tintColor = .black
        let placeLabel = UILabel()
        placeLabel.text = place
        placeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        placeLabel.textColor = .black
        let placeRow = UIStackView(arrangedSubviews: [buildingIcon, placeLabel])
        placeRow.spacing = 6
        placeRow.alignment = .center
        placeChip.layer.cornerRadius = 16
        placeChip.clipsToBounds = true
        placeChip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeChip)
        pin(placeRow, to: placeChip.contentView, insets: UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 14))
        NSLayoutConstraint.activate([
            placeChip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            placeChip.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    /// Прижимает child к parent с отступами; child добавляется во вью, чтобы констрейнты были валидны
    private func pin(_ child: UIView, to parent: UIView, insets: UIEdgeInsets = .zero) {
        parent.addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
        ])
    }
}
