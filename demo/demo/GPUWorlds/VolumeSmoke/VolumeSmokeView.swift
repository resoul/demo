//
//  VolumeSmokeView.swift
//  demo
//

import UIKit
import Metal
import simd

/// Mirrors `VolumeParams` in VolumeSmoke.metal (176 bytes).
private struct VolumeParams {
    var inverseViewProjection: simd_float4x4
    var cameraPosition: SIMD4<Float>
    var lightPosition: SIMD4<Float>
    var source: SIMD4<Float>
    var sourceForce: SIMD4<Float>
    var emitter: SIMD4<Float>
    var gridSize: UInt32
    var deltaTime: Float
    var buoyancy: Float
    var dissipation: Float
    var time: Float
    var padding: (Float, Float, Float) = (0, 0, 0)
}

/// Volumetric smoke in a glass cube: a 3D Stable Fluids simulation (48³ to 96³ voxels) with a
/// self-shadowing light pass and a ray-marched renderer. The finger injects smoke along its drag,
/// rotates the cube or moves the lamp, depending on the mode.
final class VolumeSmokeView: MetalAnimationView, MetalLabEffectView {
    private enum FingerMode: Int {
        case inject
        case rotate
        case light
    }

    private static let sizes = [48, 64, 96]

    private var sizeIndex = 1
    private var iterations = 24
    private var fingerMode: FingerMode = .inject
    private var needsClear = false

    private var velocity: [MTLTexture] = []
    private var density: [MTLTexture] = []
    private var pressure: [MTLTexture] = []
    private var divergence: MTLTexture?
    private var transmittance: MTLTexture?
    private var velocityIndex = 0
    private var densityIndex = 0
    private var pressureIndex = 0

    private var yaw: Float = 0.7
    private var pitch: Float = 0.3
    private var lightYaw: Float = -0.8
    private var lightPitch: Float = 0.9
    private var previousTouch: CGPoint?
    private var fingerVelocity = SIMD2<Float>.zero
    private var frames = RateMeter()

    private let advectVelocity = MetalEffectContext.shared?.computePipeline(function: "volume_advect_velocity")
    private let advectDensity = MetalEffectContext.shared?.computePipeline(function: "volume_advect_density")
    private let divergencePipeline = MetalEffectContext.shared?.computePipeline(function: "volume_divergence")
    private let jacobiPipeline = MetalEffectContext.shared?.computePipeline(function: "volume_jacobi")
    private let gradientPipeline = MetalEffectContext.shared?.computePipeline(function: "volume_subtract_gradient")
    private let lightPipeline = MetalEffectContext.shared?.computePipeline(function: "volume_light")
    private let renderPipeline = MetalEffectContext.shared?.renderPipeline(vertex: "fullscreen_vertex", fragment: "volume_render_fragment")

    private var gridSize: Int { Self.sizes[sizeIndex] }
    private var voxels: Int { gridSize * gridSize * gridSize }

    var activeEntityDescription: String {
        "\(gridSize)³ = \(compactCount(Double(voxels))) вокселей"
    }

    var throughputDescription: String? {
        // Advect ×2, divergence, Jacobi iterations, gradient and the 24-step light march.
        let voxelPasses = Double(voxels) * Double(4 + iterations + 24) * frames.framesPerSecond
        return "\(compactCount(voxelPasses)) воксель-проходов/с"
    }

    var controls: [LabControl] {
        [
            .segments(items: ["Палец: дым", "Вращение", "Свет"], selected: fingerMode.rawValue) { [weak self] index in
                self?.fingerMode = FingerMode(rawValue: index) ?? .inject
            },
            .segments(items: Self.sizes.map { "\($0)³" }, selected: sizeIndex) { [weak self] index in
                self?.sizeIndex = index
            },
            .slider(
                title: "Итераций",
                range: 8...60,
                value: Float(iterations),
                format: { "\(Int($0.rounded()))" },
                onChange: { [weak self] value in self?.iterations = Int(value.rounded()) }
            ),
            .button(title: "Очистить куб") { [weak self] in
                self?.needsClear = true
            },
        ]
    }

    override var textureMemoryBytes: Int {
        // velocity ×2 (rgba16f), density ×2, pressure ×2, divergence, transmittance (r16f)
        voxels * (8 * 2 + 2 * 6)
    }

    override func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {
        if touch.isActive, let previous = previousTouch, deltaTime > 0 {
            let delta = SIMD2(Float(touch.location.x - previous.x), Float(touch.location.y - previous.y))
            fingerVelocity = fingerVelocity * 0.5 + delta / Float(deltaTime) * 0.5
            switch fingerMode {
            case .inject:
                break
            case .rotate:
                yaw -= delta.x * 0.008
                pitch = min(max(pitch + delta.y * 0.006, -0.6), 1.2)
            case .light:
                lightYaw -= delta.x * 0.01
                lightPitch = min(max(lightPitch - delta.y * 0.008, -0.2), 1.4)
            }
        } else {
            fingerVelocity = .zero
        }
        previousTouch = touch.isActive ? touch.location : nil
        if !touch.isActive || fingerMode != .rotate {
            yaw += Float(deltaTime) * 0.12
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        guard let advectVelocity, let advectDensity, let divergencePipeline, let jacobiPipeline,
              let gradientPipeline, let lightPipeline, let renderPipeline else { return }
        allocateIfNeeded()
        guard velocity.count == 2, density.count == 2, pressure.count == 2, let divergence, let transmittance else { return }
        if needsClear, let blit = commandBuffer.makeBlitCommandEncoder() {
            needsClear = false
            for texture in velocity + density + pressure {
                clear(texture, with: blit)
            }
            blit.endEncoding()
        }

        let n = gridSize
        let aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1)
        let eye = Camera3D.orbit(target: .zero, yaw: yaw, pitch: pitch, distance: 4.2)
        let viewProjection = Camera3D.perspective(fovY: 0.8, aspect: aspect, near: 0.1, far: 30)
            * Camera3D.lookAt(eye: eye, center: .zero)
        let light = Camera3D.orbit(target: .zero, yaw: lightYaw, pitch: lightPitch, distance: 2.2)

        var params = VolumeParams(
            inverseViewProjection: viewProjection.inverse,
            cameraPosition: SIMD4(eye, 1),
            lightPosition: SIMD4(light, 1),
            source: .zero,
            sourceForce: .zero,
            emitter: SIMD4(Float(n) * 0.5, Float(n) * 0.08, Float(n) * 0.5, Float(n) * 0.07),
            gridSize: UInt32(n),
            deltaTime: 1.0 / 60,
            buoyancy: Float(n) * 1.2,
            dissipation: 0.985,
            time: uniforms.time
        )
        if fingerMode == .inject, touch.isActive {
            injectFromFinger(into: &params, viewProjection: viewProjection, eye: eye, resolution: uniforms.resolution)
        }

        let size = MemoryLayout<VolumeParams>.stride
        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setBytes(&params, length: size, index: 0)

            compute.setTexture(velocity[velocityIndex], index: 0)
            compute.setTexture(density[densityIndex], index: 1)
            compute.setTexture(velocity[1 - velocityIndex], index: 2)
            compute.dispatch(advectVelocity, width: n, height: n, depth: n)
            velocityIndex = 1 - velocityIndex

            compute.setTexture(velocity[velocityIndex], index: 0)
            compute.setTexture(divergence, index: 1)
            compute.dispatch(divergencePipeline, width: n, height: n, depth: n)
            for _ in 0..<iterations {
                compute.setTexture(pressure[pressureIndex], index: 0)
                compute.setTexture(divergence, index: 1)
                compute.setTexture(pressure[1 - pressureIndex], index: 2)
                compute.dispatch(jacobiPipeline, width: n, height: n, depth: n)
                pressureIndex = 1 - pressureIndex
            }
            compute.setTexture(pressure[pressureIndex], index: 0)
            compute.setTexture(velocity[velocityIndex], index: 1)
            compute.setTexture(velocity[1 - velocityIndex], index: 2)
            compute.dispatch(gradientPipeline, width: n, height: n, depth: n)
            velocityIndex = 1 - velocityIndex

            compute.setTexture(velocity[velocityIndex], index: 0)
            compute.setTexture(density[densityIndex], index: 1)
            compute.setTexture(density[1 - densityIndex], index: 2)
            compute.dispatch(advectDensity, width: n, height: n, depth: n)
            densityIndex = 1 - densityIndex

            compute.setTexture(density[densityIndex], index: 0)
            compute.setTexture(transmittance, index: 1)
            compute.dispatch(lightPipeline, width: n, height: n, depth: n)
            compute.endEncoding()
        }
        frames.tick(at: CACurrentMediaTime())

        pass.colorAttachments[0].loadAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EffectUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&params, length: size, index: 1)
        encoder.setFragmentTexture(density[densityIndex], index: 0)
        encoder.setFragmentTexture(transmittance, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// The finger's ray through the cube: smoke is injected halfway through, pushed along the drag.
    private func injectFromFinger(into params: inout VolumeParams, viewProjection: simd_float4x4, eye: SIMD3<Float>, resolution: SIMD2<Float>) {
        let inverse = viewProjection.inverse
        let farPoint = Camera3D.unproject(pixel: SIMD2(Float(touch.location.x), Float(touch.location.y)) * Float(pixelsPerPoint),
                                          ndcDepth: 1, resolution: resolution, inverseViewProjection: inverse)
        let direction = simd_normalize(farPoint - eye)
        let inverseDirection = 1 / direction
        let t0 = (SIMD3<Float>(repeating: -1) - eye) * inverseDirection
        let t1 = (SIMD3<Float>(repeating: 1) - eye) * inverseDirection
        let near = simd_reduce_max(simd_min(t0, t1)), far = simd_reduce_min(simd_max(t0, t1))
        guard near < far, far > 0 else { return }
        let world = eye + direction * ((max(near, 0) + far) * 0.5)
        let n = Float(gridSize)
        let cell = (world + 1) * 0.5 * n

        // Screen drag → world directions: along the camera's right and up vectors.
        let forward = simd_normalize(-eye)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)
        let drag = (right * fingerVelocity.x - up * fingerVelocity.y) * (n / Float(max(bounds.width, 1))) * 2.5
        params.source = SIMD4(cell, n * 0.06)
        params.sourceForce = SIMD4(drag, 6)
    }

    private func allocateIfNeeded() {
        let n = gridSize
        guard velocity.first?.width != n else { return }
        guard let context = MetalEffectContext.shared else { return }
        velocity = (0..<2).compactMap { _ in context.makeTexture(width: n, height: n, depth: n, format: .rgba16Float) }
        density = (0..<2).compactMap { _ in context.makeTexture(width: n, height: n, depth: n, format: .r16Float) }
        pressure = (0..<2).compactMap { _ in context.makeTexture(width: n, height: n, depth: n, format: .r16Float) }
        divergence = context.makeTexture(width: n, height: n, depth: n, format: .r16Float)
        transmittance = context.makeTexture(width: n, height: n, depth: n, format: .r16Float)
        needsClear = true
    }

    /// Private textures start undefined; zero them by copying from a zero-filled buffer.
    private func clear(_ texture: MTLTexture, with blit: MTLBlitCommandEncoder) {
        let bytesPerPixel = texture.pixelFormat == .rgba16Float ? 8 : 2
        let bytesPerRow = texture.width * bytesPerPixel
        let bytesPerImage = bytesPerRow * texture.height
        let length = bytesPerImage * texture.depth
        guard let zeros = MetalEffectContext.shared?.device.makeBuffer(length: length, options: .storageModePrivate) else { return }
        blit.fill(buffer: zeros, range: 0..<length, value: 0)
        blit.copy(
            from: zeros, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerImage,
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: texture.depth),
            to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
    }
}
