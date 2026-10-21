#ifndef EffectShaderCommon_h
#define EffectShaderCommon_h
#include <metal_stdlib>
using namespace metal;

// First 16 bytes also match the original LavaUniforms; total Swift stride = 32.
struct EffectUniforms {
    float2 resolution;
    float progress;
    float time;
    float2 touch;
    float interaction;
    float padding;
};
struct EffectVertexOut { float4 position [[position]]; };

namespace effect {
inline float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
inline float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), u.x),
               mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}
inline float fbm(float2 p) {
    float sum = 0, amplitude = 0.5;
    const float2x2 rotation = float2x2(0.8, -0.6, 0.6, 0.8);
    for (int i = 0; i < 5; ++i) {
        sum += amplitude * noise(p);
        p = rotation * p * 2.03 + 7.1;
        amplitude *= 0.5;
    }
    return sum;
}
inline float2 uv(float4 position, constant EffectUniforms &u) {
    return position.xy / max(u.resolution, float2(1));
}
inline float aspect(constant EffectUniforms &u) { return u.resolution.x / max(u.resolution.y, 1.0); }
}
#endif
