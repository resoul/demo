#include "EffectShaderCommon.h"

struct LiquidPhysicsUniforms { float2 tilt; float impulseTime; float padding; };

fragment float4 liquidWavesFragment(EffectVertexOut in [[stage_in]], constant EffectUniforms &u [[buffer(0)]],
                                    constant LiquidPhysicsUniforms &physics [[buffer(1)]]) {
    float2 uv = effect::uv(in.position, u);
    float t = u.time;
    float age = max(t - physics.impulseTime, 0.0);
    float dx = (uv.x - u.touch.x) * effect::aspect(u);
    float impulse = sin(abs(dx) * 32 - age * 8) * exp(-abs(dx) * 2.0 - age * 0.8) * 0.055;
    float wave = sin(uv.x * 10 + t * 1.4) * 0.018 + sin(uv.x * 19 - t * 1.8) * 0.012
               + sin(uv.x * 33 + t * 2.5) * 0.006 + sin(uv.x * 51 - t * 3.2) * 0.003;
    float level = 1.0 - u.progress + physics.tilt.x * (uv.x - 0.5) * 0.35;
    float surface = level + (wave + impulse) * sin(u.progress * M_PI_F);
    float depth = uv.y - surface;
    float pixel = 1.0 / max(u.resolution.y, 1.0);
    float3 sky = mix(float3(0.015, 0.035, 0.08), float3(0.025, 0.1, 0.16), uv.y);
    if (u.progress <= 0) return float4(sky, 1);
    float3 water = mix(float3(0.02, 0.65, 0.78), float3(0.005, 0.065, 0.22),
                       smoothstep(0.0, 0.8, depth));
    float2 bottom = float2(uv.x * effect::aspect(u) * 7, uv.y * 7);
    bottom.x += sin(bottom.y * 1.8 - t * 1.3) * 0.3 + physics.tilt.x;
    float c = sin(bottom.x * 3 + sin(bottom.y * 2 + t))
            + sin(bottom.y * 3 - t * 1.2 + sin(bottom.x * 2));
    float caustic = pow(clamp(1.0 - abs(c) * 0.5, 0.0, 1.0), 12.0);
    water += float3(0.02, 0.24, 0.25) * caustic * smoothstep(0.01, 0.25, depth);
    float backSurface = level + sin(uv.x * 13 + t * 0.9) * 0.023;
    sky = mix(sky, float3(0.02, 0.22, 0.36), smoothstep(-pixel, pixel, uv.y - backSurface) * 0.65);
    float foam = exp(-abs(depth) * u.resolution.y / 3.0)
               * (0.5 + 0.5 * effect::noise(float2(uv.x * 100, t * 2)));
    water = mix(water, float3(0.85, 1, 1), foam);
    float mask = u.progress >= 1 ? 1.0 : smoothstep(-pixel, pixel, depth);
    return float4(mix(sky, water, mask), 1);
}
