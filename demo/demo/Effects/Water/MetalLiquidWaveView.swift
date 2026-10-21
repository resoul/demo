//
//  MetalLiquidWaveView.swift
//  demo
//

import UIKit

/// GPU implementation of the liquid wave progress (`wave_fragment` in WaveShader.metal).
final class MetalLiquidWaveView: MetalAnimationView {
    override class var fragmentFunction: String? { "wave_fragment" }
}
