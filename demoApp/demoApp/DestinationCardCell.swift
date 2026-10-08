//
//  DestinationCardCell.swift
//  demoApp
//

import UIKit

/// Ячейка коллекции с карточкой достопримечательности. Карточка обрезается ячейкой не должна:
/// тень и вырезы видны полностью, поэтому отступы даём внутри contentView
final class DestinationCardCell: UICollectionViewCell {

    static let reuseIdentifier = "DestinationCardCell"

    /// Отступы карточки внутри ячейки, нужны и для расчёта размера ячейки
    static let inset: CGFloat = 12
    /// Высота карточки относительно ширины: как на референсе, карточка почти квадратная
    static let aspectRatio: CGFloat = 1.05

    let cardView = DestinationCardView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with model: DestinationCardModel) {
        cardView.configure(with: model)
    }

    private func setup() {
        contentView.addSubview(cardView)
        let inset = DestinationCardCell.inset
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: inset),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -inset),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -inset),
        ])
    }
}
