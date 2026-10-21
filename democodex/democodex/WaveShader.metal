#include "EffectShaderCommon.h"

float waveSurface(float x, float t, constant EffectUniforms &u) {
    float waves = sin(x * 9 + t * 1.4) * 0.018
                + sin(x * 17 - t * 1.9) * 0.010
                + sin(x * 27 + t * 2.7) * 0.006
                + sin(x * 41 - t * 3.2) * 0.003;
    float dx = x - u.touch.x;
    float ripple = u.interaction * (sin(dx * 32 - t * 7) * exp(-dx * dx * 12) * 0.055 + dx * 0.12);
    return 1.0 - u.progress + (waves + ripple) * sin(u.progress * M_PI_F);
}

fragment float4 waveFragment(EffectVertexOut in [[stage_in]], constant EffectUniforms &u [[buffer(0)]]) {
    float2 uv = effect::uv(in.position, u);
    float3 background = float3(0.02, 0.06, 0.12);
    if (u.progress <= 0) return float4(background, 1);
    float edge = waveSurface(uv.x, u.time, u);
    float backEdge = waveSurface(uv.x, u.time + 1.5, u);
    float pixel = 1.0 / max(u.resolution.y, 1.0);
    float depth = uv.y - edge;
    float backMask = smoothstep(-pixel, pixel, uv.y - backEdge);
    float3 color = mix(background, float3(0.02, 0.27, 0.41), backMask * 0.65);
    float3 water = mix(float3(0.06, 0.91, 0.88), float3(0.005, 0.15, 0.54),
                       clamp(depth / max(u.progress, 0.01), 0.0, 1.0));
    float caustic = pow(0.5 + 0.5 * sin(uv.x * 38 + sin(uv.y * 18 + u.time) * 2 + u.time), 12.0);
    water += float3(0.03, 0.12, 0.16) * caustic * exp(-depth * 3.0);
    float foamWidth = (2.0 + effect::noise(float2(uv.x * 90, u.time * 2)) * 4.0) * pixel;
    float foam = (1.0 - smoothstep(0.0, foamWidth, abs(depth))) * (0.55 + 0.45 * caustic);
    if (u.progress < 1) water = mix(water, float3(0.88, 1, 1), foam);
    color = mix(color, water, u.progress >= 1 ? 1.0 : smoothstep(-pixel, pixel, depth));
    return float4(color, 1);
}
