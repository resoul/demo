//
//  Camera3D.swift
//  demo
//

import simd

/// Minimal right-handed camera math for the 3D effects (Metal clip space: z in 0...1).
nonisolated enum Camera3D {
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovY * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, z * near, 0)
        ))
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float> = SIMD3(0, 1, 0)) -> simd_float4x4 {
        let forward = simd_normalize(center - eye)
        let right = simd_normalize(simd_cross(forward, up))
        let upward = simd_cross(right, forward)
        return simd_float4x4(columns: (
            SIMD4(right.x, upward.x, -forward.x, 0),
            SIMD4(right.y, upward.y, -forward.y, 0),
            SIMD4(right.z, upward.z, -forward.z, 0),
            SIMD4(-simd_dot(right, eye), -simd_dot(upward, eye), simd_dot(forward, eye), 1)
        ))
    }

    /// Orbit position around `target` from yaw / pitch angles and a distance.
    static func orbit(target: SIMD3<Float>, yaw: Float, pitch: Float, distance: Float) -> SIMD3<Float> {
        target + SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * distance
    }

    /// Six inward-facing planes (xyz normal, w offset) of a view-projection matrix:
    /// a point p is inside when dot(plane.xyz, p) + plane.w >= 0 for all of them.
    static func frustumPlanes(_ m: simd_float4x4) -> [SIMD4<Float>] {
        let row0 = SIMD4(m.columns.0.x, m.columns.1.x, m.columns.2.x, m.columns.3.x)
        let row1 = SIMD4(m.columns.0.y, m.columns.1.y, m.columns.2.y, m.columns.3.y)
        let row2 = SIMD4(m.columns.0.z, m.columns.1.z, m.columns.2.z, m.columns.3.z)
        let row3 = SIMD4(m.columns.0.w, m.columns.1.w, m.columns.2.w, m.columns.3.w)
        return [row3 + row0, row3 - row0, row3 + row1, row3 - row1, row2, row3 - row2].map { plane in
            plane / simd_length(SIMD3(plane.x, plane.y, plane.z))
        }
    }

    /// Screen point (pixels, top-left origin) and NDC depth → world position.
    static func unproject(pixel: SIMD2<Float>, ndcDepth: Float, resolution: SIMD2<Float>, inverseViewProjection: simd_float4x4) -> SIMD3<Float> {
        let ndc = SIMD2(pixel.x / resolution.x * 2 - 1, 1 - pixel.y / resolution.y * 2)
        let world = inverseViewProjection * SIMD4(ndc.x, ndc.y, ndcDepth, 1)
        return SIMD3(world.x, world.y, world.z) / world.w
    }
}

/// Position + normal vertex for simple meshes (32 bytes, matches `MeshVertex` in the shaders).
nonisolated struct MeshVertex {
    var position: SIMD4<Float>
    var normal: SIMD4<Float>
}

nonisolated enum MeshBuilder {
    /// Unit UV sphere centred at the origin.
    static func sphere(segments: Int = 32, rings: Int = 16) -> (vertices: [MeshVertex], indices: [UInt16]) {
        var vertices: [MeshVertex] = []
        var indices: [UInt16] = []
        for ring in 0...rings {
            let v = Float(ring) / Float(rings) * .pi
            for segment in 0...segments {
                let u = Float(segment) / Float(segments) * 2 * .pi
                let n = SIMD3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
                vertices.append(MeshVertex(position: SIMD4(n, 1), normal: SIMD4(n, 0)))
            }
        }
        let stride = segments + 1
        for ring in 0..<rings {
            for segment in 0..<segments {
                let a = UInt16(ring * stride + segment), b = a + 1
                let c = UInt16((ring + 1) * stride + segment), d = c + 1
                indices += [a, c, b, b, c, d]
            }
        }
        return (vertices, indices)
    }

    /// Axis-aligned box from `min` to `max` with flat normals (24 vertices, 36 indices).
    static func box(min lower: SIMD3<Float>, max upper: SIMD3<Float>, indexOffset: UInt16 = 0) -> (vertices: [MeshVertex], indices: [UInt16]) {
        let faces: [(normal: SIMD3<Float>, corners: [SIMD3<Float>])] = [
            (SIMD3(1, 0, 0), [SIMD3(upper.x, lower.y, upper.z), SIMD3(upper.x, lower.y, lower.z), SIMD3(upper.x, upper.y, lower.z), SIMD3(upper.x, upper.y, upper.z)]),
            (SIMD3(-1, 0, 0), [SIMD3(lower.x, lower.y, lower.z), SIMD3(lower.x, lower.y, upper.z), SIMD3(lower.x, upper.y, upper.z), SIMD3(lower.x, upper.y, lower.z)]),
            (SIMD3(0, 1, 0), [SIMD3(lower.x, upper.y, upper.z), SIMD3(upper.x, upper.y, upper.z), SIMD3(upper.x, upper.y, lower.z), SIMD3(lower.x, upper.y, lower.z)]),
            (SIMD3(0, -1, 0), [SIMD3(lower.x, lower.y, lower.z), SIMD3(upper.x, lower.y, lower.z), SIMD3(upper.x, lower.y, upper.z), SIMD3(lower.x, lower.y, upper.z)]),
            (SIMD3(0, 0, 1), [SIMD3(lower.x, lower.y, upper.z), SIMD3(upper.x, lower.y, upper.z), SIMD3(upper.x, upper.y, upper.z), SIMD3(lower.x, upper.y, upper.z)]),
            (SIMD3(0, 0, -1), [SIMD3(upper.x, lower.y, lower.z), SIMD3(lower.x, lower.y, lower.z), SIMD3(lower.x, upper.y, lower.z), SIMD3(upper.x, upper.y, lower.z)]),
        ]
        var vertices: [MeshVertex] = []
        var indices: [UInt16] = []
        for face in faces {
            let base = indexOffset + UInt16(vertices.count)
            vertices += face.corners.map { MeshVertex(position: SIMD4($0, 1), normal: SIMD4(face.normal, 0)) }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return (vertices, indices)
    }
}
