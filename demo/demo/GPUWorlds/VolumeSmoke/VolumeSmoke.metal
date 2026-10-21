//
//  VolumeSmoke.metal
//  demo
//
//  3D smoke in a glass cube: Stable Fluids on an N³ grid of 3D textures (advection with buoyancy,
//  pressure projection by Jacobi iterations), a light pass that marches from every voxel towards
//  the lamp to get its transmittance, and a ray-marched volume renderer. Grid y points up.
//

#include "../../Effects/Core/ShaderCommon.h"

// Mirrored by `VolumeParams` in VolumeSmokeView.swift (176 bytes).
struct VolumeParams {
    float4x4 inverseViewProjection;
    float4 cameraPosition;      // world; the cube spans [-1, 1]³
    float4 lightPosition;       // world
    float4 source;              // finger injection: xyz cells, w radius in cells (0 = none)
    float4 sourceForce;         // xyz cells / s, w density per second
    float4 emitter;             // bottom chimney: xyz cells, w radius in cells
    uint gridSize;
    float deltaTime;
    float buoyancy;
    float dissipation;
    float time;
    float padding0;
    float padding1;
    float padding2;
};

constexpr sampler volumeSampler(filter::linear, address::clamp_to_edge);

static float gaussian(float3 position, float4 center) {
    if (center.w <= 0.0) return 0.0;
    float3 d = position - center.xyz;
    return exp(-dot(d, d) / (center.w * center.w));
}

static bool outside(uint3 gid, uint n) {
    return gid.x >= n || gid.y >= n || gid.z >= n;
}

kernel void volume_advect_velocity(texture3d<float> velocity [[texture(0)]],
                                   texture3d<float> density [[texture(1)]],
                                   texture3d<float, access::write> out [[texture(2)]],
                                   constant VolumeParams &p [[buffer(0)]],
                                   uint3 gid [[thread_position_in_grid]]) {
    if (outside(gid, p.gridSize)) return;
    float n = float(p.gridSize);
    float3 position = float3(gid) + 0.5;
    float3 v = velocity.sample(volumeSampler, position / n).xyz;
    float3 result = velocity.sample(volumeSampler, (position - p.deltaTime * v) / n).xyz * 0.995;
    // Hot smoke rises; the chimney blows upwards; the finger pushes along its drag.
    result.y += p.buoyancy * density.sample(volumeSampler, position / n).x * p.deltaTime;
    result += float3(0.0, n * 0.6, 0.0) * gaussian(position, p.emitter) * p.deltaTime;
    result += p.sourceForce.xyz * gaussian(position, p.source) * p.deltaTime;
    out.write(float4(result, 0.0), gid);
}

kernel void volume_advect_density(texture3d<float> velocity [[texture(0)]],
                                  texture3d<float> density [[texture(1)]],
                                  texture3d<float, access::write> out [[texture(2)]],
                                  constant VolumeParams &p [[buffer(0)]],
                                  uint3 gid [[thread_position_in_grid]]) {
    if (outside(gid, p.gridSize)) return;
    float n = float(p.gridSize);
    float3 position = float3(gid) + 0.5;
    float3 v = velocity.sample(volumeSampler, position / n).xyz;
    float d = density.sample(volumeSampler, (position - p.deltaTime * v) / n).x * p.dissipation;
    d += 3.0 * gaussian(position, p.emitter) * p.deltaTime;
    d += p.sourceForce.w * gaussian(position, p.source) * p.deltaTime;
    out.write(float4(min(d, 3.0)), gid);
}

kernel void volume_divergence(texture3d<float, access::read> velocity [[texture(0)]],
                              texture3d<float, access::write> divergence [[texture(1)]],
                              constant VolumeParams &p [[buffer(0)]],
                              uint3 gid [[thread_position_in_grid]]) {
    if (outside(gid, p.gridSize)) return;
    int n = int(p.gridSize);
    int3 c = int3(gid);
    float3 center = velocity.read(gid).xyz;
    // Solid walls: the neighbour outside mirrors the normal velocity.
    float right = c.x + 1 < n ? velocity.read(uint3(c + int3(1, 0, 0))).x : -center.x;
    float left = c.x > 0 ? velocity.read(uint3(c - int3(1, 0, 0))).x : -center.x;
    float up = c.y + 1 < n ? velocity.read(uint3(c + int3(0, 1, 0))).y : -center.y;
    float down = c.y > 0 ? velocity.read(uint3(c - int3(0, 1, 0))).y : -center.y;
    float front = c.z + 1 < n ? velocity.read(uint3(c + int3(0, 0, 1))).z : -center.z;
    float back = c.z > 0 ? velocity.read(uint3(c - int3(0, 0, 1))).z : -center.z;
    divergence.write(float4(0.5 * (right - left + up - down + front - back)), gid);
}

static float readClamped(texture3d<float, access::read> field, int3 cell, int n) {
    return field.read(uint3(clamp(cell, int3(0), int3(n - 1)))).x;
}

kernel void volume_jacobi(texture3d<float, access::read> pressure [[texture(0)]],
                          texture3d<float, access::read> divergence [[texture(1)]],
                          texture3d<float, access::write> out [[texture(2)]],
                          constant VolumeParams &p [[buffer(0)]],
                          uint3 gid [[thread_position_in_grid]]) {
    if (outside(gid, p.gridSize)) return;
    int n = int(p.gridSize);
    int3 c = int3(gid);
    float sum = readClamped(pressure, c + int3(1, 0, 0), n) + readClamped(pressure, c - int3(1, 0, 0), n)
              + readClamped(pressure, c + int3(0, 1, 0), n) + readClamped(pressure, c - int3(0, 1, 0), n)
              + readClamped(pressure, c + int3(0, 0, 1), n) + readClamped(pressure, c - int3(0, 0, 1), n);
    out.write(float4((sum - divergence.read(gid).x) / 6.0), gid);
}

kernel void volume_subtract_gradient(texture3d<float, access::read> pressure [[texture(0)]],
                                     texture3d<float, access::read> velocity [[texture(1)]],
                                     texture3d<float, access::write> out [[texture(2)]],
                                     constant VolumeParams &p [[buffer(0)]],
                                     uint3 gid [[thread_position_in_grid]]) {
    if (outside(gid, p.gridSize)) return;
    int n = int(p.gridSize);
    int3 c = int3(gid);
    float3 gradient = 0.5 * float3(
        readClamped(pressure, c + int3(1, 0, 0), n) - readClamped(pressure, c - int3(1, 0, 0), n),
        readClamped(pressure, c + int3(0, 1, 0), n) - readClamped(pressure, c - int3(0, 1, 0), n),
        readClamped(pressure, c + int3(0, 0, 1), n) - readClamped(pressure, c - int3(0, 0, 1), n));
    float3 v = velocity.read(gid).xyz - gradient;
    if (c.x == 0 || c.x == n - 1) v.x = 0.0;
    if (c.y == 0 || c.y == n - 1) v.y = 0.0;
    if (c.z == 0 || c.z == n - 1) v.z = 0.0;
    out.write(float4(v, 0.0), gid);
}

// Transmittance from every voxel towards the lamp, for self-shadowing.
kernel void volume_light(texture3d<float> density [[texture(0)]],
                         texture3d<float, access::write> transmittance [[texture(1)]],
                         constant VolumeParams &p [[buffer(0)]],
                         uint3 gid [[thread_position_in_grid]]) {
    if (outside(gid, p.gridSize)) return;
    float n = float(p.gridSize);
    float3 position = (float3(gid) + 0.5) / n;                     // 0...1
    float3 light = (p.lightPosition.xyz + 1.0) * 0.5;
    float3 direction = normalize(light - position);
    const int steps = 24;
    float stepLength = 1.5 / n;
    float optical = 0.0;
    for (int i = 1; i <= steps; i++) {
        float3 q = position + direction * stepLength * float(i);
        if (any(q < 0.0) || any(q > 1.0)) break;
        optical += density.sample(volumeSampler, q).x;
    }
    transmittance.write(float4(exp(-optical * stepLength * 2.0 * 9.0)), gid);
}

static float2 boxIntersection(float3 origin, float3 direction) {
    float3 inverse = 1.0 / direction;
    float3 t0 = (-1.0 - origin) * inverse;
    float3 t1 = (1.0 - origin) * inverse;
    float3 nearT = min(t0, t1), farT = max(t0, t1);
    return float2(max(max(nearT.x, nearT.y), nearT.z), min(min(farT.x, farT.y), farT.z));
}

fragment float4 volume_render_fragment(FullscreenVertexOut in [[stage_in]],
                                       constant VolumeParams &p [[buffer(1)]],
                                       texture3d<float> density [[texture(0)]],
                                       texture3d<float> transmittance [[texture(1)]]) {
    float2 ndc = in.uv * 2.0 - 1.0;
    float4 far = p.inverseViewProjection * float4(ndc.x, -ndc.y, 1.0, 1.0);
    float3 origin = p.cameraPosition.xyz;
    float3 direction = normalize(far.xyz / far.w - origin);

    // Backdrop: dark studio with a soft floor glow under the cube.
    float3 background = mix(float3(0.05, 0.05, 0.07), float3(0.01, 0.01, 0.02), in.uv.y * 0.5 + 0.25);
    if (direction.y < 0.0) {
        float3 floorPoint = origin + direction * ((-1.02 - origin.y) / direction.y);
        background += float3(0.18, 0.16, 0.13) * exp(-dot(floorPoint.xz, floorPoint.xz) * 0.6) * 0.5;
    }

    float2 span = boxIntersection(origin, direction);
    if (span.x >= span.y || span.y < 0.0) {
        return float4(background, 1.0);
    }
    float start = max(span.x, 0.0);
    const int steps = 96;
    float stepLength = (span.y - start) / float(steps);
    float3 light = p.lightPosition.xyz;
    const float sigma = 9.0;

    float3 color = float3(0.0);
    float throughput = 1.0;
    for (int i = 0; i < steps && throughput > 0.01; i++) {
        float3 world = origin + direction * (start + (float(i) + 0.5) * stepLength);
        float3 uvw = (world + 1.0) * 0.5;
        float d = density.sample(volumeSampler, uvw).x;
        if (d < 0.002) continue;
        float shadow = transmittance.sample(volumeSampler, uvw).x;
        float3 toLight = normalize(light - world);
        float phase = 0.6 + 0.4 * dot(-direction, toLight);         // a little forward scattering
        float3 lit = float3(1.0, 0.92, 0.8) * shadow * phase * 2.2 + float3(0.15, 0.17, 0.22);
        float absorbed = 1.0 - exp(-sigma * d * stepLength);
        color += throughput * absorbed * lit;
        throughput *= 1.0 - absorbed;
    }

    // Glass cube: faint tint and bright edges where the entry point is near two faces at once.
    float3 entry = origin + direction * start;
    float3 edgeDistance = 1.0 - abs(entry);
    float minA = min(edgeDistance.x, min(edgeDistance.y, edgeDistance.z));
    float secondMin = edgeDistance.x + edgeDistance.y + edgeDistance.z - minA
                    - max(edgeDistance.x, max(edgeDistance.y, edgeDistance.z));
    float edge = 1.0 - smoothstep(0.0, 0.015, secondMin);
    float3 glass = background + float3(0.012, 0.015, 0.02);

    float3 result = color + throughput * glass + edge * float3(0.45, 0.55, 0.65);
    // The lamp, as a small glowing dot.
    float3 toLamp = light - origin;
    float lampAlong = dot(toLamp, direction);
    float lampDistance = length(toLamp - direction * lampAlong);
    result += float3(1.0, 0.9, 0.7) * exp(-lampDistance * lampDistance * 900.0) * (lampAlong > 0.0 ? 1.0 : 0.0);
    return float4(pow(1.0 - exp(-result * 1.2), float3(1.0 / 1.8)), 1.0);
}
