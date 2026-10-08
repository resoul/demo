//
//  GradientCardView.swift
//  demoApp
//

import UIKit

/// Карточка с градиентом вместо фото: слой сам CAGradientLayer, поэтому растягивается вместе с view
final class GradientCardView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    var colors: [UIColor] = [] {
        didSet { gradientLayer.colors = colors.map(\.cgColor) }
    }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }
}
