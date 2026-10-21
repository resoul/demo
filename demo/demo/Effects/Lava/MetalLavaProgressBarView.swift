//
//  MetalLavaProgressBarView.swift
//  demo
//

import UIKit

/// GPU implementation: the whole bar, including the boiling lava, the meniscus and the empty track,
/// is computed per pixel in `lava_fragment` (LavaShader.metal).
final class MetalLavaProgressBarView: MetalAnimationView {
    override class var fragmentFunction: String? { "lava_fragment" }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
