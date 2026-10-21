#include "EffectShaderCommon.h"

struct ParticleSimulationUniforms {
    float2 touch;
    float deltaTime;
    float aspect;
    uint count;
    float time;
    float force;
    float interaction;
};

inline float particleRandom(uint value) {
    // Integer mixing preserves entropy for all one million IDs. A float hash
    // of large IDs loses fractional bits and collapses particles into bands.
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return float(value & 0x00ffffffu) / 16777216.0;
}

kernel void initializeParticles(device float4 *particles [[buffer(0)]], constant uint &count [[buffer(1)]],
                                uint id [[thread_position_in_grid]]) {
    if (id >= count) return;
    float2 p = float2(particleRandom(id * 2 + 1), particleRandom(id * 2 + 2));
    float2 v = float2(-(p.y - 0.5), p.x - 0.5) * 0.08;
    particles[id] = float4(p, v);
}

kernel void simulateParticles(device float4 *particles [[buffer(0)]],
                              constant ParticleSimulationUniforms &u [[buffer(1)]], uint id [[thread_position_in_grid]]) {
    if (id >= u.count) return;
    float4 state = particles[id];
    float2 p = state.xy, v = state.zw;
    float2 metric = float2(max(u.aspect, 0.1), 1);
    float2 delta = (u.touch - p) * metric;
    float2 center = (p - 0.5) * metric;
    float2 acceleration = float2(-center.y, center.x) * 0.12 - center * 0.06;
    acceleration += delta * (u.force * u.interaction * 0.28 / (dot(delta, delta) + 0.025));
    acceleration += float2(sin(p.y * 17 + u.time), cos(p.x * 19 - u.time)) * 0.025;
    float dt = clamp(u.deltaTime, 0.0, 1.0 / 30.0);
    v = (v + acceleration / metric * dt) * exp(-dt * 0.45);
    float speed = length(v);
    if (speed > 0.7) v *= 0.7 / speed;
    p += v * dt;
    if (p.x < 0.002 || p.x > 0.998) v.x *= -0.8;
    if (p.y < 0.002 || p.y > 0.998) v.y *= -0.8;
    particles[id] = float4(clamp(p, float2(0.002), float2(0.998)), v);
}

struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float3 color;
};

vertex ParticleVertexOut particlesVertex(uint id [[vertex_id]], const device float4 *particles [[buffer(0)]],
                                         constant EffectUniforms &u [[buffer(1)]]) {
    float4 p = particles[id];
    ParticleVertexOut out;
    out.position = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0, 1);
    out.pointSize = 2.0;
    float heat = clamp(length(p.zw) * 3, 0.0, 1.0);
    out.color = mix(float3(0.12, 0.5, 1.0), float3(1.0, 0.3, 0.12), heat)
              * mix(0.65, 0.12, sqrt(u.progress));
    return out;
}

fragment float4 particlesFragment(ParticleVertexOut in [[stage_in]], float2 point [[point_coord]]) {
    float radius = length(point * 2 - 1);
    if (radius > 1) discard_fragment();
    return float4(in.color * (1.0 - radius * radius), 1);
}
