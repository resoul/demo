//
//  Aquarium.metal
//  demo
//
//  Position Based Fluids (Macklin & Müller 2013) in 2D, smoothing radius h = 1:
//  predict → build neighbour grid → [density constraint λ → position correction] × iterations
//  → velocity from the corrected positions → XSPH viscosity. Collisions with the tank walls,
//  the removable partition, a rock and the finger are resolved in every correction.
//  Rendering splats every particle into a half-resolution field and shades its iso-surface.
//

#include "../../Effects/Core/ShaderCommon.h"
#include "../../Effects/Core/SpatialGrid.h"

// Mirrored by `PBFParams` in AquariumFluidView.swift (80 bytes).
struct PBFParams {
    float2 domain;          // tank size in h
    float2 gravity;         // h / s², screen orientation (y down)
    float deltaTime;
    float restDensity;
    float relaxation;       // ε in the λ denominator
    float viscosity;        // XSPH coefficient
    float2 finger;          // h
    float fingerRadius;     // 0 when not touching
    float partitionX;       // < 0 when removed
    float2 rockCenter;
    float rockRadius;
    uint count;
    float maxSpeed;
    float splatRadius;      // pixels of the field texture
    float2 fieldPixelsPerUnit;
};

constant float kPoly6 = 4.0 / M_PI_F;           // 2D poly6 normalisation for h = 1
constant float kSpikyGradient = -30.0 / M_PI_F; // 2D spiky gradient normalisation for h = 1
constant float kTensileK = 0.002;               // artificial pressure (s_corr) strength
constant float kTensileDq = 0.2;                // s_corr reference distance

static float poly6(float r2) {
    float x = 1.0 - r2;
    return r2 < 1.0 ? kPoly6 * x * x * x : 0.0;
}

static float2 spikyGradient(float2 d, float r) {
    if (r <= 1e-5 || r >= 1.0) return float2(0.0);
    float x = 1.0 - r;
    return kSpikyGradient * x * x * (d / r);
}

static float2 pushOutOfCircle(float2 x, float2 center, float radius) {
    float2 offset = x - center;
    float distance = length(offset);
    return distance < radius ? center + offset / max(distance, 1e-4) * radius : x;
}

// `previous` decides which side of the partition a particle belongs to.
static float2 collide(float2 x, float2 previous, constant PBFParams &p) {
    const float margin = 0.25;
    x = pushOutOfCircle(x, p.rockCenter, p.rockRadius + margin);
    if (p.fingerRadius > 0.0) {
        x = pushOutOfCircle(x, p.finger, p.fingerRadius + margin);
    }
    if (p.partitionX > 0.0 && abs(x.x - p.partitionX) < 0.5 + margin) {
        float side = previous.x < p.partitionX ? -1.0 : 1.0;
        x.x = p.partitionX + side * (0.5 + margin);
    }
    return clamp(x, float2(margin), p.domain - margin);
}

// Counts neighbour pairs: one atomic add per SIMD group.
static void countPairs(uint pairs, device atomic_uint *counter) {
    uint total = simd_sum(pairs);
    if (simd_is_first()) {
        atomic_fetch_add_explicit(counter, total, memory_order_relaxed);
    }
}

kernel void pbf_predict(device const float2 *positions [[buffer(0)]],
                        device const float2 *velocities [[buffer(1)]],
                        device float2 *predicted [[buffer(2)]],
                        constant PBFParams &p [[buffer(3)]],
                        uint id [[thread_position_in_grid]]) {
    if (id >= p.count) return;
    float2 v = velocities[id] + p.gravity * p.deltaTime;
    float speed = length(v);
    if (speed > p.maxSpeed) v *= p.maxSpeed / speed;
    float2 x = positions[id];
    predicted[id] = collide(x + v * p.deltaTime, x, p);
}

kernel void pbf_lambda(device const float2 *predicted [[buffer(0)]],
                       device float *lambdas [[buffer(1)]],
                       device const uint *cellStart [[buffer(2)]],
                       device const uint *cellCounts [[buffer(3)]],
                       device const uint *sorted [[buffer(4)]],
                       constant GridParams &grid [[buffer(5)]],
                       constant PBFParams &p [[buffer(6)]],
                       device atomic_uint *pairCounter [[buffer(7)]],
                       uint id [[thread_position_in_grid]]) {
    if (id >= p.count) return;
    float2 xi = predicted[id];
    int2 cell = gridCell(xi, grid);
    float density = 0.0;
    float2 gradientI = float2(0.0);
    float sumGradient2 = 0.0;
    uint pairs = 0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int2 c = cell + int2(dx, dy);
            if (any(c < 0) || any(c >= int2(grid.dims))) continue;
            uint index = gridCellIndex(c, grid);
            uint end = cellStart[index] + cellCounts[index];
            for (uint k = cellStart[index]; k < end; k++) {
                uint j = sorted[k];
                float2 d = xi - predicted[j];
                float r2 = dot(d, d);
                if (r2 >= 1.0) continue;
                pairs++;
                density += poly6(r2);
                if (j != id) {
                    float2 g = spikyGradient(d, sqrt(r2)) / p.restDensity;
                    gradientI += g;
                    sumGradient2 += dot(g, g);
                }
            }
        }
    }
    // Only compression is resisted; the free surface stays free.
    float constraint = max(density / p.restDensity - 1.0, 0.0);
    lambdas[id] = -constraint / (sumGradient2 + dot(gradientI, gradientI) + p.relaxation);
    countPairs(pairs, pairCounter);
}

kernel void pbf_delta(device const float2 *predictedIn [[buffer(0)]],
                      device const float *lambdas [[buffer(1)]],
                      device const uint *cellStart [[buffer(2)]],
                      device const uint *cellCounts [[buffer(3)]],
                      device const uint *sorted [[buffer(4)]],
                      constant GridParams &grid [[buffer(5)]],
                      constant PBFParams &p [[buffer(6)]],
                      device atomic_uint *pairCounter [[buffer(7)]],
                      device float2 *predictedOut [[buffer(8)]],
                      device const float2 *positions [[buffer(9)]],
                      uint id [[thread_position_in_grid]]) {
    if (id >= p.count) return;
    float2 xi = predictedIn[id];
    float li = lambdas[id];
    int2 cell = gridCell(xi, grid);
    float2 delta = float2(0.0);
    float tensileReference = poly6(kTensileDq * kTensileDq);
    uint pairs = 0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int2 c = cell + int2(dx, dy);
            if (any(c < 0) || any(c >= int2(grid.dims))) continue;
            uint index = gridCellIndex(c, grid);
            uint end = cellStart[index] + cellCounts[index];
            for (uint k = cellStart[index]; k < end; k++) {
                uint j = sorted[k];
                if (j == id) continue;
                float2 d = xi - predictedIn[j];
                float r2 = dot(d, d);
                if (r2 >= 1.0) continue;
                pairs++;
                float ratio = poly6(r2) / tensileReference;
                float tensile = -kTensileK * ratio * ratio * ratio * ratio;
                delta += (li + lambdas[j] + tensile) * spikyGradient(d, sqrt(r2));
            }
        }
    }
    predictedOut[id] = collide(xi + delta / p.restDensity, positions[id], p);
    countPairs(pairs, pairCounter);
}

kernel void pbf_velocity(device const float2 *positions [[buffer(0)]],
                         device const float2 *predicted [[buffer(1)]],
                         device float2 *velocityScratch [[buffer(2)]],
                         constant PBFParams &p [[buffer(3)]],
                         uint id [[thread_position_in_grid]]) {
    if (id >= p.count) return;
    velocityScratch[id] = (predicted[id] - positions[id]) / p.deltaTime;
}

// XSPH viscosity, then commit the step: velocities and positions for the next substep.
kernel void pbf_viscosity(device const float2 *predicted [[buffer(0)]],
                          device const float2 *velocityScratch [[buffer(1)]],
                          device const uint *cellStart [[buffer(2)]],
                          device const uint *cellCounts [[buffer(3)]],
                          device const uint *sorted [[buffer(4)]],
                          constant GridParams &grid [[buffer(5)]],
                          constant PBFParams &p [[buffer(6)]],
                          device atomic_uint *pairCounter [[buffer(7)]],
                          device float2 *velocities [[buffer(8)]],
                          device float2 *positions [[buffer(9)]],
                          uint id [[thread_position_in_grid]]) {
    if (id >= p.count) return;
    float2 xi = predicted[id];
    float2 vi = velocityScratch[id];
    int2 cell = gridCell(xi, grid);
    float2 smoothing = float2(0.0);
    uint pairs = 0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int2 c = cell + int2(dx, dy);
            if (any(c < 0) || any(c >= int2(grid.dims))) continue;
            uint index = gridCellIndex(c, grid);
            uint end = cellStart[index] + cellCounts[index];
            for (uint k = cellStart[index]; k < end; k++) {
                uint j = sorted[k];
                float2 d = xi - predicted[j];
                float r2 = dot(d, d);
                if (j == id || r2 >= 1.0) continue;
                pairs++;
                smoothing += (velocityScratch[j] - vi) * poly6(r2);
            }
        }
    }
    velocities[id] = vi + p.viscosity * smoothing;
    positions[id] = xi;
    countPairs(pairs, pairCounter);
}

// MARK: - Rendering

struct SplatOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float speed;
};

vertex SplatOut aquarium_splat_vertex(device const float2 *positions [[buffer(0)]],
                                      device const float2 *velocities [[buffer(1)]],
                                      constant PBFParams &p [[buffer(2)]],
                                      uint vid [[vertex_id]]) {
    float2 clip = positions[vid] / p.domain * 2.0 - 1.0;
    SplatOut out;
    out.position = float4(clip.x, -clip.y, 0.0, 1.0);
    out.pointSize = p.splatRadius * 2.0;
    out.speed = saturate(length(velocities[vid]) / (p.maxSpeed * 0.5));
    return out;
}

// Accumulates a smooth "water amount" (r) and speed-weighted amount (g) per pixel.
fragment float4 aquarium_splat_fragment(SplatOut in [[stage_in]],
                                        float2 pointCoord [[point_coord]]) {
    float2 d = pointCoord * 2.0 - 1.0;
    float r2 = dot(d, d);
    if (r2 >= 1.0) discard_fragment();
    float w = (1.0 - r2) * (1.0 - r2);
    return float4(w, w * in.speed, 0.0, 0.0);
}

// custom[0] = (partition x px or -1, rock center x px, rock center y px, rock radius px)
// custom[1] = (finger radius px, partition half width px, unused, unused)
fragment float4 aquarium_fragment(FullscreenVertexOut in [[stage_in]],
                                  constant EffectUniforms &u [[buffer(0)]],
                                  texture2d<float> field [[texture(0)]]) {
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float2 px = in.uv * u.resolution;
    float unit = min(u.resolution.x, u.resolution.y);
    float2 texel = 1.0 / float2(field.get_width(), field.get_height());

    // Tank: dark back wall with faint tiles.
    float3 color = mix(float3(0.03, 0.05, 0.08), float3(0.01, 0.02, 0.04), in.uv.y);
    float2 tile = abs(fract(px / (unit * 0.08)) - 0.5);
    color += 0.02 * smoothstep(0.46, 0.5, max(tile.x, tile.y));

    // Rock.
    float2 rockCenter = u.custom[0].yz;
    float rockRadius = u.custom[0].w;
    float rockDistance = length(px - rockCenter) - rockRadius;
    float rockShade = 0.65 + 0.35 * saturate((rockCenter.y - px.y) / rockRadius);
    float3 rock = float3(0.26, 0.25, 0.23) * (0.7 + 0.3 * valueNoise(px * 0.04)) * rockShade;
    color = mix(color, rock, smoothstep(1.0, -1.0, rockDistance));

    // Water: iso-surface of the splatted field, lit through its gradient.
    float2 f = field.sample(linear, in.uv).xy;
    float fx = field.sample(linear, in.uv + float2(texel.x, 0.0)).x - field.sample(linear, in.uv - float2(texel.x, 0.0)).x;
    float fy = field.sample(linear, in.uv + float2(0.0, texel.y)).x - field.sample(linear, in.uv - float2(0.0, texel.y)).x;
    float3 normal = normalize(float3(-fx * 1.5, -fy * 1.5, 1.0));
    float water = smoothstep(0.6, 1.1, f.x);
    float thickness = saturate(f.x / 4.0);
    float3 waterColor = mix(float3(0.12, 0.58, 0.88), float3(0.02, 0.18, 0.45), thickness);
    float specular = pow(saturate(dot(reflect(float3(0.0, 0.0, -1.0), normal), normalize(float3(-0.4, -0.6, 0.7)))), 30.0);
    float foam = saturate(f.y / max(f.x, 1e-3) * 1.6) * smoothstep(0.6, 1.5, f.x);
    waterColor = mix(waterColor, float3(0.85, 0.95, 1.0), foam * 0.6) + specular * 0.6;
    waterColor += water * (1.0 - smoothstep(1.1, 1.8, f.x)) * 0.25;      // bright meniscus
    color = mix(color, waterColor, water * 0.92);

    // Partition: a glass plate.
    if (u.custom[0].x >= 0.0) {
        float d = abs(px.x - u.custom[0].x) - u.custom[1].y;
        float glass = smoothstep(1.0, -1.0, d);
        float rim = smoothstep(2.0, 0.0, abs(d));
        color = mix(color, float3(0.75, 0.85, 0.95), glass * 0.3) + rim * 0.25;
    }

    // Finger: a soft ring where it pushes the water.
    if (u.touchStrength > 0.01) {
        float ring = smoothstep(2.0, 0.0, abs(length(px - u.touch) - u.custom[1].x));
        color += float3(0.6, 0.85, 1.0) * ring * 0.5 * u.touchStrength;
    }
    return float4(color, 1.0);
}
