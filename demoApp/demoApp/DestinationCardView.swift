//
//  DestinationCardView.swift
//  demoApp
//

import UIKit

/// Карточка достопримечательности: белая карточка с фото нестандартной формы, названием города и капсулой места
final class DestinationCardView: UIView {

    /// Параметры силуэта фото; при изменении карточка перестраивает контур на следующем layout
    var shapeConfiguration = DestinationShapeConfiguration() {
        didSet {
            // При переиспользовании ячейки та же конфигурация не должна перестраивать контур
            guard shapeConfiguration != oldValue else { return }
            applyConfiguration()
        }
    }

    /// Вызывается по нажатию на карточку
    var onTap: (() -> Void)?

    private let imageView = UIImageView()
    private let shapeLayer = DestinationImageShapeLayer()
    /// Тень фото отдельным слоем: маска imageView обрезала бы его собственную тень
    private let imageShadowLayer = CALayer()

    private let cityIcon = UIImageView(
        image: UIImage(systemName: "mappin.and.ellipse", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
    )
    private let cityLabel = UILabel()

    private let landmarkChip = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let landmarkIcon = UIImageView(image: UIImage(systemName: "building.columns.fill"))
    private let landmarkLabel = UILabel()

    private var imageTop: NSLayoutConstraint!
    private var imageLeading: NSLayoutConstraint!
    private var imageTrailing: NSLayoutConstraint!
    private var imageBottom: NSLayoutConstraint!
    private var aspectConstraint: NSLayoutConstraint!
    /// Отступ капсулы от левого края фото внизу; пересчитывается от ширины фото
    private var landmarkLeading: NSLayoutConstraint!
    private let landmarkInset: CGFloat = 10

    /// Высота относительно ширины: ограничение с приоритетом 999, чтобы не конфликтовать с внешней версткой
    init(aspectRatio: CGFloat = DestinationCardCell.aspectRatio) {
        super.init(frame: .zero)
        setup(aspectRatio: aspectRatio)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Заполняет карточку данными
    func configure(with model: DestinationCardModel) {
        cityLabel.text = model.title
        landmarkLabel.text = model.landmark
        imageView.image = model.image
        imageView.backgroundColor = model.image == nil ? .systemGray5 : nil
    }

    // MARK: - Настройка

    private func setup(aspectRatio: CGFloat) {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white
        // Тень рисуется у самого слоя карточки; clipsToBounds не ставим, иначе тень обрежется
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.cornerRadius = shapeConfiguration.cardCornerRadius

        setupImage()
        setupCity()
        setupLandmark()

        aspectConstraint = heightAnchor.constraint(equalTo: widthAnchor, multiplier: aspectRatio)
        aspectConstraint.priority = UILayoutPriority(999)
        aspectConstraint.isActive = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        applyConfiguration()
    }

    private func setupImage() {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        // Маска задаёт силуэт фото; слой не создаём заново, он переиспользуется при layout
        imageView.layer.mask = shapeLayer
        addSubview(imageView)

        // Слой без содержимого: видна только тень по shadowPath
        imageShadowLayer.shadowColor = UIColor.black.cgColor
        layer.insertSublayer(imageShadowLayer, below: imageView.layer)

        imageTop = imageView.topAnchor.constraint(equalTo: topAnchor)
        imageLeading = imageView.leadingAnchor.constraint(equalTo: leadingAnchor)
        imageTrailing = imageView.trailingAnchor.constraint(equalTo: trailingAnchor)
        imageBottom = imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([imageTop, imageLeading, imageTrailing, imageBottom])
    }

    private func setupCity() {
        cityIcon.tintColor = .black
        cityIcon.contentMode = .scaleAspectFit
        cityLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        cityLabel.textColor = .black

        let row = UIStackView(arrangedSubviews: [cityIcon, cityLabel])
        row.spacing = 6
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 19),
        ])
    }

    private func setupLandmark() {
        landmarkChip.layer.cornerRadius = 17
        landmarkChip.clipsToBounds = true
        landmarkChip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(landmarkChip)

        landmarkIcon.tintColor = .white
        landmarkIcon.contentMode = .scaleAspectFit
        landmarkLabel.font = .systemFont(ofSize: 11, weight: .medium)
        landmarkLabel.textColor = .white

        let row = UIStackView(arrangedSubviews: [landmarkIcon, landmarkLabel])
        row.spacing = 6
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        landmarkChip.contentView.addSubview(row)

        landmarkLeading = landmarkChip.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: landmarkInset)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: landmarkChip.contentView.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: landmarkChip.contentView.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: landmarkChip.contentView.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: landmarkChip.contentView.bottomAnchor, constant: -6),

            // Капсула стоит у нижнего левого угла фото
            landmarkLeading,
            landmarkChip.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -12),
        ])
    }

    /// Переносит параметры силуэта на constraints фото и слой маски
    private func applyConfiguration() {
        let cfg = shapeConfiguration
        imageTop.constant = cfg.imageInsets.top
        imageLeading.constant = cfg.imageInsets.left
        imageTrailing.constant = -cfg.imageInsets.right
        imageBottom.constant = -cfg.imageInsets.bottom
        layer.cornerRadius = cfg.cardCornerRadius
        shapeLayer.configuration = cfg
        imageShadowLayer.shadowOpacity = cfg.imageShadowOpacity
        imageShadowLayer.shadowRadius = cfg.imageShadowRadius
        imageShadowLayer.shadowOffset = cfg.imageShadowOffset
        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        // Левый край фото внизу задан долей ширины, поэтому отступ капсулы считаем от него
        let bottomLeftX = shapeConfiguration.outline.filter { $0.y >= 1 }.map(\.x).min() ?? 0
        let chipLeading = imageView.bounds.width * bottomLeftX + landmarkInset
        if abs(landmarkLeading.constant - chipLeading) > 0.5 {
            landmarkLeading.constant = chipLeading
        }

        // Слои не пересоздаются: обновляем frame и path, без анимации CoreAnimation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.frame = imageView.bounds
        shapeLayer.update(size: imageView.bounds.size)
        // Тень берёт тот же контур, что и маска, поэтому повторяет силуэт фото
        imageShadowLayer.frame = imageView.frame
        imageShadowLayer.shadowPath = shapeLayer.path
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: shapeConfiguration.cardCornerRadius).cgPath
        CATransaction.commit()
    }

    @objc private func handleTap() {
        onTap?()
    }
}
