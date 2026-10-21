#include "EffectShaderCommon.h"

fragment float4 metaBallFragment(EffectVertexOut in [[stage_in]], constant EffectUniforms &u [[buffer(0)]]) {
    float2 uv = effect::uv(in.position, u);
    float aspect = effect::aspect(u);
    float potential = 0;
    float2 derivative = 0;
    float t = u.time * 0.45;
    for (int index = 0; index < 5; ++index) {
        float i = float(index);
        float2 center = float2(0.5 + 0.32 * sin(t * (0.7 + i * 0.13) + i * 1.7),
                               0.5 + 0.27 * cos(t * (0.9 + i * 0.09) + i * 2.1));
        center = mix(center, u.touch, u.interaction * 0.78);
        float radius = (0.08 + u.progress * 0.075) * (0.85 + i * 0.07);
        float2 delta = (uv - center) * float2(aspect, 1);
        float d2 = max(dot(delta, delta), 0.0001);
        potential += radius * radius / d2;
        derivative += -2.0 * radius * radius * delta / (d2 * d2);
    }
    // An inverse-square implicit surface (metaballs), not a signed distance.
    float aa = max(fwidth(potential), 0.008);
    float mask = smoothstep(1.0 - aa, 1.0 + aa, potential);
    float3 normal = normalize(float3(-derivative * 0.035, 1.0));
    float light = max(dot(normal, normalize(float3(-0.5, -0.8, 1.0))), 0.0);
    float highlight = pow(light, 12.0);
    float rim = pow(1.0 - normal.z, 2.0);
    float3 metal = mix(float3(0.035, 0.15, 0.3), float3(0.24, 0.8, 0.88), light);
    metal += float3(0.75, 0.95, 1.0) * highlight + float3(0.2, 0.7, 0.8) * rim;
    float3 background = float3(0.025, 0.04, 0.075);
    return float4(mix(background, metal, mask), 1);
}
