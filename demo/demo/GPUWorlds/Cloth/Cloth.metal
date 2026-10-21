//
//  Cloth.metal
//  demo
//
//  Position-based cloth on a W×H node grid, entirely on the GPU: predict → Jacobi distance
//  constraints (structural, shear, bending) × iterations → velocities and tearing → normals and a
//  fresh index buffer that drops triangles across torn edges. Each node owns four edges
//  (right, down, diagonal, anti-diagonal) as bits, so tearing has a single writer per edge.
//

#include <metal_stdlib>
using namespace metal;

// Mirrored by `ClothParams` in ClothView.swift (160 bytes).
struct ClothParams {
    float4x4 viewProjection;
    float4 sphere;          // xyz centre, w radius
    float4 grabTarget;      // xyz, w = 1 while a node is grabbed
    float4 lightDirection;  // towards the light
    float4 cameraPosition;
    uint2 gridSize;
    uint grabIndex;
    uint pinned;            // 1 pins the two far corners
    float spacing;          // rest length of a structural edge
    float deltaTime;
    float tearFactor;       // stretch ratio that breaks an edge; 0 disables tearing
    float relaxation;       // Jacobi over-relaxation
};

constant uint kRight = 1u, kDown = 2u, kDiagonal = 4u, kAntiDiagonal = 8u;

static bool isPinned(uint id, constant ClothParams &p) {
    return p.pinned != 0 && (id == 0 || id == p.gridSize.x - 1);
}

static float3 collide(float3 x, constant ClothParams &p) {
    float3 offset = x - p.sphere.xyz;
    float distance = length(offset);
    float radius = p.sphere.w + 0.015;
    if (distance < radius) {
        x = p.sphere.xyz + offset / max(distance, 1e-4) * radius;
    }
    x.y = max(x.y, 0.01);
    return x;
}

kernel void cloth_predict(device const float4 *positions [[buffer(0)]],
                          device const float4 *velocities [[buffer(1)]],
                          device float4 *predicted [[buffer(2)]],
                          constant ClothParams &p [[buffer(3)]],
                          uint id [[thread_position_in_grid]]) {
    if (id >= p.gridSize.x * p.gridSize.y) return;
    float3 x = positions[id].xyz;
    if (isPinned(id, p)) {
        predicted[id] = float4(x, 0.0);
        return;
    }
    if (p.grabTarget.w > 0.0 && id == p.grabIndex) {
        predicted[id] = float4(p.grabTarget.xyz, 0.0);
        return;
    }
    float3 v = velocities[id].xyz * 0.995 + float3(0.0, -9.8, 0.0) * p.deltaTime;
    predicted[id] = float4(collide(x + v * p.deltaTime, p), 1.0);   // w = inverse mass
}

static void addConstraint(thread float3 &sum, thread float &count, float4 self, float4 other, float rest, float stiffness) {
    float3 d = self.xyz - other.xyz;
    float length = metal::length(d);
    float weight = self.w + other.w;
    if (length < 1e-6 || weight <= 0.0) return;
    sum -= (self.w / weight) * (length - rest) * (d / length) * stiffness;
    count += 1.0;
}

kernel void cloth_constraints(device const float4 *predictedIn [[buffer(0)]],
                              device const uint *edges [[buffer(1)]],
                              device float4 *predictedOut [[buffer(2)]],
                              constant ClothParams &p [[buffer(3)]],
                              device atomic_uint *solveCounter [[buffer(4)]],
                              uint id [[thread_position_in_grid]]) {
    uint w = p.gridSize.x, h = p.gridSize.y;
    if (id >= w * h) return;
    float4 self = predictedIn[id];
    if (self.w == 0.0) {
        predictedOut[id] = self;
        return;
    }
    int x = int(id % w), y = int(id / w);
    float s = p.spacing, diagonal = s * M_SQRT2_F;
    float3 sum = float3(0.0);
    float count = 0.0;

    // Structural.
    if (x + 1 < int(w) && (edges[id] & kRight)) addConstraint(sum, count, self, predictedIn[id + 1], s, 1.0);
    if (x > 0 && (edges[id - 1] & kRight)) addConstraint(sum, count, self, predictedIn[id - 1], s, 1.0);
    if (y + 1 < int(h) && (edges[id] & kDown)) addConstraint(sum, count, self, predictedIn[id + w], s, 1.0);
    if (y > 0 && (edges[id - w] & kDown)) addConstraint(sum, count, self, predictedIn[id - w], s, 1.0);
    // Shear.
    if (x + 1 < int(w) && y + 1 < int(h) && (edges[id] & kDiagonal)) addConstraint(sum, count, self, predictedIn[id + w + 1], diagonal, 0.8);
    if (x > 0 && y > 0 && (edges[id - w - 1] & kDiagonal)) addConstraint(sum, count, self, predictedIn[id - w - 1], diagonal, 0.8);
    if (x > 0 && y + 1 < int(h) && (edges[id] & kAntiDiagonal)) addConstraint(sum, count, self, predictedIn[id + w - 1], diagonal, 0.8);
    if (x + 1 < int(w) && y > 0 && (edges[id - w + 1] & kAntiDiagonal)) addConstraint(sum, count, self, predictedIn[id - w + 1], diagonal, 0.8);
    // Bending (two cells apart), only while both structural edges in between hold.
    if (x + 2 < int(w) && (edges[id] & kRight) && (edges[id + 1] & kRight)) addConstraint(sum, count, self, predictedIn[id + 2], 2.0 * s, 0.25);
    if (x > 1 && (edges[id - 1] & kRight) && (edges[id - 2] & kRight)) addConstraint(sum, count, self, predictedIn[id - 2], 2.0 * s, 0.25);
    if (y + 2 < int(h) && (edges[id] & kDown) && (edges[id + w] & kDown)) addConstraint(sum, count, self, predictedIn[id + 2 * w], 2.0 * s, 0.25);
    if (y > 1 && (edges[id - w] & kDown) && (edges[id - 2 * w] & kDown)) addConstraint(sum, count, self, predictedIn[id - 2 * w], 2.0 * s, 0.25);

    float3 x1 = self.xyz + (count > 0.0 ? sum * (p.relaxation / count) : float3(0.0));
    predictedOut[id] = float4(collide(x1, p), self.w);

    uint solved = simd_sum(uint(count));
    if (simd_is_first()) {
        atomic_fetch_add_explicit(solveCounter, solved, memory_order_relaxed);
    }
}

// Velocities from the solved positions, commit, and break over-stretched edges this node owns.
kernel void cloth_finish(device float4 *positions [[buffer(0)]],
                         device const float4 *predicted [[buffer(1)]],
                         device float4 *velocities [[buffer(2)]],
                         device uint *edges [[buffer(3)]],
                         constant ClothParams &p [[buffer(4)]],
                         uint id [[thread_position_in_grid]]) {
    uint w = p.gridSize.x, h = p.gridSize.y;
    if (id >= w * h) return;
    float3 x = predicted[id].xyz;
    float3 v = (x - positions[id].xyz) / p.deltaTime;
    if (x.y <= 0.0101) v.xz *= 0.8;     // ground friction
    velocities[id] = float4(v, 0.0);
    positions[id] = float4(x, 1.0);

    if (p.tearFactor <= 0.0) return;
    uint x0 = id % w, y0 = id / w;
    uint flags = edges[id];
    float limit = p.spacing * p.tearFactor;
    if ((flags & kRight) && x0 + 1 < w && distance(x, predicted[id + 1].xyz) > limit) flags &= ~kRight;
    if ((flags & kDown) && y0 + 1 < h && distance(x, predicted[id + w].xyz) > limit) flags &= ~kDown;
    if ((flags & kDiagonal) && x0 + 1 < w && y0 + 1 < h && distance(x, predicted[id + w + 1].xyz) > limit * M_SQRT2_F) flags &= ~kDiagonal;
    if ((flags & kAntiDiagonal) && x0 > 0 && y0 + 1 < h && distance(x, predicted[id + w - 1].xyz) > limit * M_SQRT2_F) flags &= ~kAntiDiagonal;
    edges[id] = flags;
}

kernel void cloth_normals(device const float4 *positions [[buffer(0)]],
                          device float4 *normals [[buffer(1)]],
                          constant ClothParams &p [[buffer(2)]],
                          uint id [[thread_position_in_grid]]) {
    uint w = p.gridSize.x, h = p.gridSize.y;
    if (id >= w * h) return;
    uint x = id % w, y = id / w;
    float3 right = positions[y * w + min(x + 1, w - 1)].xyz - positions[y * w + (x > 0 ? x - 1 : 0)].xyz;
    float3 down = positions[min(y + 1, h - 1) * w + x].xyz - positions[(y > 0 ? y - 1 : 0) * w + x].xyz;
    normals[id] = float4(normalize(cross(down, right) + float3(0.0, 1e-5, 0.0)), 0.0);
}

// Two triangles per grid quad; a triangle whose edges are torn collapses to a degenerate one.
kernel void cloth_indices(device const uint *edges [[buffer(0)]],
                          device uint *indices [[buffer(1)]],
                          constant ClothParams &p [[buffer(2)]],
                          uint id [[thread_position_in_grid]]) {
    uint w = p.gridSize.x, h = p.gridSize.y;
    if (id >= (w - 1) * (h - 1)) return;
    uint x = id % (w - 1), y = id / (w - 1);
    uint a = y * w + x, b = a + 1, c = a + w, d = c + 1;
    bool first = (edges[a] & kRight) && (edges[b] & kDown) && (edges[a] & kDiagonal);
    bool second = (edges[a] & kDiagonal) && (edges[c] & kRight) && (edges[a] & kDown);
    uint base = id * 6;
    indices[base + 0] = first ? a : 0;
    indices[base + 1] = first ? b : 0;
    indices[base + 2] = first ? d : 0;
    indices[base + 3] = second ? a : 0;
    indices[base + 4] = second ? d : 0;
    indices[base + 5] = second ? c : 0;
}

// MARK: - Rendering

struct MeshVertex {
    float4 position;
    float4 normal;
};

struct SceneVertexOut {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float2 uv;
    uint material [[flat]];
};

vertex SceneVertexOut cloth_vertex(device const float4 *positions [[buffer(0)]],
                                   device const float4 *normals [[buffer(1)]],
                                   constant ClothParams &p [[buffer(2)]],
                                   uint vid [[vertex_id]]) {
    SceneVertexOut out;
    float3 world = positions[vid].xyz;
    out.position = p.viewProjection * float4(world, 1.0);
    out.world = world;
    out.normal = normals[vid].xyz;
    out.uv = float2(vid % p.gridSize.x, vid / p.gridSize.x) / float2(p.gridSize - 1);
    out.material = 0;
    return out;
}

// Static meshes: `transform` = (offset xyz, uniform scale); material 1 = sphere, 2 = ground.
vertex SceneVertexOut cloth_mesh_vertex(device const MeshVertex *vertices [[buffer(0)]],
                                        constant ClothParams &p [[buffer(1)]],
                                        constant float4 &transform [[buffer(2)]],
                                        constant uint &material [[buffer(3)]],
                                        uint vid [[vertex_id]]) {
    SceneVertexOut out;
    float3 world = vertices[vid].position.xyz * transform.w + transform.xyz;
    out.position = p.viewProjection * float4(world, 1.0);
    out.world = world;
    out.normal = vertices[vid].normal.xyz;
    out.uv = world.xz;
    out.material = material;
    return out;
}

fragment float4 cloth_scene_fragment(SceneVertexOut in [[stage_in]],
                                     bool frontFacing [[front_facing]],
                                     constant ClothParams &p [[buffer(0)]]) {
    float3 n = normalize(in.normal);
    float3 view = normalize(p.cameraPosition.xyz - in.world);
    if (dot(n, view) < 0.0) n = -n;     // two-sided cloth
    float3 l = normalize(p.lightDirection.xyz);
    float diffuse = saturate(dot(n, l));
    float3 h = normalize(l + view);

    float3 albedo;
    float shininess = 16.0, specularStrength = 0.1;
    if (in.material == 0) {
        // Tartan: crossing stripes of two widths plus a fine weave.
        float2 uv = in.uv * 6.0;
        float2 band = smoothstep(0.35, 0.4, abs(fract(uv) - 0.5));
        float2 thin = 1.0 - smoothstep(0.02, 0.05, abs(fract(uv * 2.0 + 0.25) - 0.5));
        albedo = float3(0.55, 0.07, 0.09);
        albedo = mix(albedo, float3(0.08, 0.22, 0.14), (band.x + band.y) * 0.45);
        albedo = mix(albedo, float3(0.95, 0.8, 0.35), max(thin.x, thin.y) * 0.6);
        float weave = 0.9 + 0.1 * sin(in.uv.x * 900.0) * sin(in.uv.y * 900.0);
        albedo *= weave;
        specularStrength = 0.05;
    } else if (in.material == 1) {
        albedo = float3(0.15, 0.35, 0.75);
        shininess = 64.0;
        specularStrength = 0.6;
    } else {
        float2 checker = floor(in.uv * 2.0);
        float tile = fmod(abs(checker.x + checker.y), 2.0);
        albedo = mix(float3(0.22), float3(0.3), tile) * (1.0 - smoothstep(4.0, 9.0, length(in.uv)));
    }

    float specular = pow(saturate(dot(n, h)), shininess) * specularStrength;
    float rim = pow(1.0 - saturate(dot(n, view)), 3.0) * 0.15;
    float3 color = albedo * (0.25 + 0.85 * diffuse) + specular + rim;
    return float4(color, 1.0);
}
