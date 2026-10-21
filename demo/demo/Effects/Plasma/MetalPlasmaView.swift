//
//  MetalPlasmaView.swift
//  demo
//

import UIKit

/// GPU implementation of the neon plasma (`plasma_fragment` in PlasmaShader.metal).
final class MetalPlasmaView: MetalAnimationView {
    override class var fragmentFunction: String? { "plasma_fragment" }
}
