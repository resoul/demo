#include "EffectShaderCommon.h"

fragment float4 plasmaFragment(EffectVertexOut in [[stage_in]], constant EffectUniforms &u [[buffer(0)]]) {
    float2 uv = effect::uv(in.position, u);
    float2 p = uv * float2(effect::aspect(u), 1.0) * 3.5;
    float2 touch = u.touch * float2(effect::aspect(u), 1.0) * 3.5;
    float2 delta = p - touch;
    p += u.interaction * float2(-delta.y, delta.x) * exp(-dot(delta, delta) * 0.5) * 2.0;
    float t = u.time * 0.25;
    float2 q = float2(effect::fbm(p + float2(t, -t)), effect::fbm(p + 5.2 - t));
    float2 warp = float2(effect::fbm(p + 3.2 * q + float2(1.7, 9.2) + t),
                         effect::fbm(p + 3.2 * q + float2(8.3, 2.8) - t));
    float field = effect::fbm(p + 4.0 * warp);
    float veins = pow(1.0 - abs(field * 2.0 - 1.0), 12.0);
    float3 color = mix(float3(0.025, 0.015, 0.12), float3(0.38, 0.015, 0.9), field);
    color = mix(color, float3(0.02, 0.18, 1.0), warp.x * 0.7);
    color += float3(0.0, 0.9, 1.0) * veins * (0.35 + u.progress * 1.3);
    color += float3(0.72, 0.1, 1.0) * pow(warp.y, 3.0);
    color *= 0.35 + u.progress * 0.65;
    return float4(color, 1);
}
