//
//  MetalFireView.swift
//  demo
//

import UIKit

/// GPU implementation of the procedural fire (`fire_fragment` in FireShader.metal).
final class MetalFireView: MetalAnimationView {
    override class var fragmentFunction: String? { "fire_fragment" }
}
