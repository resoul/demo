//
//  LiquidIslandDebugPanel.swift
//  demoApp
//

import UIKit

/// Панель с ползунками параметров Liquid Island. Каждое изменение сразу отдаётся в `onChange`
final class LiquidIslandDebugPanel: UIView {

    /// Один параметр: название, диапазон и путь к полю конфигурации
    private struct Parameter {
        let title: String
        let range: ClosedRange<Float>
        let keyPath: WritableKeyPath<LiquidIslandConfiguration, CGFloat>
        let fractionDigits: Int
    }

    private static let parameters: [Parameter] = [
        Parameter(title: "Attraction Radius", range: 60...320, keyPath: \.attractionRadius, fractionDigits: 0),
        Parameter(title: "Spring Stiffness", range: 80...600, keyPath: \.springStiffness, fractionDigits: 0),
        Parameter(title: "Damping", range: 4...60, keyPath: \.damping, fractionDigits: 0),
        Parameter(title: "Liquid Stretch", range: 0...1, keyPath: \.liquidStretch, fractionDigits: 2),
        Parameter(title: "Absorption Threshold", range: 0...80, keyPath: \.absorptionThreshold, fractionDigits: 0),
    ]

    /// Текущие параметры; при установке ползунки синхронизируются с ними
    var configuration = LiquidIslandConfiguration() {
        didSet { syncControls() }
    }

    /// Вызывается при каждом изменении ползунка
    var onChange: ((LiquidIslandConfiguration) -> Void)?

    private var sliders: [UISlider] = []
    private var valueLabels: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Настройка

    private func setup() {
        backgroundColor = .white
        layer.cornerRadius = 16
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for (index, parameter) in Self.parameters.enumerated() {
            let titleLabel = UILabel()
            titleLabel.text = parameter.title
            titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
            titleLabel.textColor = .darkGray

            let valueLabel = UILabel()
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            valueLabel.textColor = .black
            valueLabel.textAlignment = .right
            valueLabels.append(valueLabel)

            let header = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
            header.axis = .horizontal

            let slider = UISlider()
            slider.minimumValue = parameter.range.lowerBound
            slider.maximumValue = parameter.range.upperBound
            slider.addAction(UIAction { [weak self] action in
                guard let slider = action.sender as? UISlider else { return }
                self?.sliderChanged(index: index, value: slider.value)
            }, for: .valueChanged)
            sliders.append(slider)

            let row = UIStackView(arrangedSubviews: [header, slider])
            row.axis = .vertical
            row.spacing = 4
            stack.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])

        syncControls()
    }

    // MARK: - Синхронизация

    private func sliderChanged(index: Int, value: Float) {
        let parameter = Self.parameters[index]
        configuration[keyPath: parameter.keyPath] = CGFloat(value)
        valueLabels[index].text = format(value, digits: parameter.fractionDigits)
        onChange?(configuration)
    }

    /// Переносит значения конфигурации на ползунки и подписи
    private func syncControls() {
        for (index, parameter) in Self.parameters.enumerated() where index < sliders.count {
            let value = Float(configuration[keyPath: parameter.keyPath])
            sliders[index].value = value
            valueLabels[index].text = format(value, digits: parameter.fractionDigits)
        }
    }

    private func format(_ value: Float, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}
