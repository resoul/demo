//
//  MetalMetaBallsView.swift
//  demo
//

import UIKit

/// GPU implementation: blob positions come from the shared simulation, the field and shading
/// are evaluated per pixel in `metaball_fragment` (MetaBallShader.metal).
final class MetalMetaBallsView: MetalAnimationView {
    override class var fragmentFunction: String? { "metaball_fragment" }

    private var simulation = MetaBallSimulation()

    override func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {
        simulation.step(deltaTime: deltaTime, time: Double(uniforms.time), size: bounds.size, touch: touch)
        let scale = Float(pixelsPerPoint)
        let blobs = simulation.blobs.prefix(EffectUniforms.maxBlobs)
        for (index, blob) in blobs.enumerated() {
            let radius = simulation.radius(of: blob, progress: uniforms.progress)
            uniforms.setBlob(index, SIMD4(Float(blob.position.x), Float(blob.position.y), Float(radius), 0) * scale)
        }
        uniforms.blobCount = Int32(blobs.count)
    }
}
