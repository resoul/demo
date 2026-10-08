//
//  TripCardView.swift
//  demoApp
//

import UIKit

/// Данные поездки для слайдера
struct Trip {
    let title: String
    let location: String
    let dates: String
    let colors: [UIColor]
}

/// Карточка поездки: градиент вместо фото, дата и отметка сверху, название и место в стеклянной панели снизу
final class TripCardView: UIView {

    init(trip: Trip) {
        super.init(frame: .zero)
        setup(trip)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(_ trip: Trip) {
        layer.cornerRadius = 28
        clipsToBounds = true

        let photo = GradientCardView()
        photo.colors = trip.colors
        addSubview(photo)
        pin(photo, to: self)

        // Даты в стеклянной капсуле сверху слева
        let clock = UIImageView(image: UIImage(systemName: "clock"))
        clock.tintColor = .white
        let dateRow = UIStackView(arrangedSubviews: [clock, makeLabel(trip.dates, size: 13, weight: .semibold)])
        dateRow.spacing = 6
        dateRow.alignment = .center
        let dateChip = makeGlass(cornerRadius: 14)
        addSubview(dateChip)
        pin(dateRow, to: dateChip.contentView, insets: UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10))
        NSLayoutConstraint.activate([
            dateChip.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            dateChip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
        ])

        // Отметка в круге сверху справа
        let check = makeGlass(cornerRadius: 15)
        addSubview(check)
        let checkIcon = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
        checkIcon.tintColor = .white
        check.contentView.addSubview(checkIcon)
        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            check.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            check.widthAnchor.constraint(equalToConstant: 30),
            check.heightAnchor.constraint(equalToConstant: 30),
            checkIcon.centerXAnchor.constraint(equalTo: check.contentView.centerXAnchor),
            checkIcon.centerYAnchor.constraint(equalTo: check.contentView.centerYAnchor),
        ])

        // Название и место в стеклянной панели снизу
        let badge = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
        badge.tintColor = .white
        let titleRow = UIStackView(arrangedSubviews: [makeLabel(trip.title, size: 17, weight: .bold), badge])
        titleRow.spacing = 6
        titleRow.alignment = .center

        let pinIcon = UIImageView(image: UIImage(systemName: "mappin.and.ellipse"))
        pinIcon.tintColor = UIColor.white.withAlphaComponent(0.85)
        let locationRow = UIStackView(arrangedSubviews: [pinIcon, makeLabel(trip.location, size: 13, weight: .regular, alpha: 0.85)])
        locationRow.spacing = 6
        locationRow.alignment = .center

        let info = UIStackView(arrangedSubviews: [titleRow, locationRow])
        info.axis = .vertical
        info.alignment = .leading
        info.spacing = 4

        let panel = makeGlass(cornerRadius: 18)
        addSubview(panel)
        pin(info, to: panel.contentView, insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    private func makeGlass(cornerRadius: CGFloat) -> UIVisualEffectView {
        let glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        glass.layer.cornerRadius = cornerRadius
        glass.clipsToBounds = true
        glass.translatesAutoresizingMaskIntoConstraints = false
        return glass
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: UIFont.Weight, alpha: CGFloat = 1) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = UIColor.white.withAlphaComponent(alpha)
        return label
    }

    /// Прижимает child к parent с отступами
    private func pin(_ child: UIView, to parent: UIView, insets: UIEdgeInsets = .zero) {
        // Констрейнты можно активировать только для view с общим предком, поэтому сначала добавляем
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
