#include "EffectShaderCommon.h"

fragment float4 fireFragment(EffectVertexOut in [[stage_in]], constant EffectUniforms &u [[buffer(0)]]) {
    float2 uv = effect::uv(in.position, u);
    float3 background = float3(0.035, 0.02, 0.035);
    if (u.progress <= 0) return float4(background, 1);
    float y = 1.0 - uv.y;
    float aspect = effect::aspect(u);
    float wind = (u.touch.x - 0.5) * u.interaction;
    float2 p = float2((uv.x - 0.5) * aspect - wind * y * 1.3, y);
    float t = u.time;
    // Refraction is simulated within this procedural background.
    float distortion = sin(y * 27.0 - t * 6.0 + p.x * 4) * 0.025 * y;
    p.x += distortion;
    float turbulence = effect::fbm(float2(p.x * 4, y * 4 - t * 1.8));
    float fine = effect::fbm(float2(p.x * 9 + turbulence * 2, y * 8 - t * 3));
    float width = max(0.0, 1.0 - abs(p.x) / max(aspect * 0.5, 0.1));
    float fuel = (0.22 + u.progress * 0.75) * pow(width, 0.45) - y;
    float flame = smoothstep(0.0, 0.16, fuel + (turbulence - 0.5) * 0.5 + (fine - 0.5) * 0.2);
    float temperature = clamp(fuel * 1.7 + fine * 0.35, 0.0, 1.0);
    float3 fire = mix(float3(0.65, 0.025, 0.002), float3(1.0, 0.32, 0.008), smoothstep(0.05, 0.45, temperature));
    fire = mix(fire, float3(1.0, 0.9, 0.38), smoothstep(0.4, 0.85, temperature));
    fire = mix(fire, float3(1.0, 0.98, 0.8), smoothstep(0.8, 1.0, temperature));
    float smoke = smoothstep(0.38, 0.8, turbulence) * smoothstep(0.15, 0.65, y) * (1.0 - y) * width * u.progress;
    float3 color = mix(background, float3(0.18, 0.16, 0.22), smoke);
    color = mix(color, fire, flame);
    for (int i = 0; i < 18; ++i) {
        float seed = float(i);
        float speed = 0.18 + effect::hash(float2(seed, 2)) * 0.3;
        float sy = fract(t * speed + effect::hash(float2(seed, 5)));
        float sx = (effect::hash(float2(seed, 8)) - 0.5) * 0.8 + wind * sy * 0.6
                 + sin(t * 2 + seed) * 0.025;
        float2 delta = float2((uv.x - 0.5 - sx) * aspect, y - sy);
        float spark = exp(-dot(delta, delta * float2(1, 0.4)) * 22000.0);
        color += float3(1.0, 0.65, 0.1) * spark * (1.0 - sy) * u.progress;
    }
    return float4(color, 1);
}
