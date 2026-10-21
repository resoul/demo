//
//  PlasmaShader.metal
//  demo
//
//  Neon plasma: domain warping, fbm(p + fbm(p + time)), mapped to an ultramarine, violet and
//  cyan palette with bright "electric" filaments along the noise mid-level.
//

#include "../Core/ShaderCommon.h"

fragment float4 plasma_fragment(FullscreenVertexOut in [[stage_in]],
                                constant EffectUniforms &u [[buffer(0)]]) {
    float2 px = in.uv * u.resolution;
    float unit = min(u.resolution.x, u.resolution.y);
    float2 p = (px - 0.5 * u.resolution) / unit * 2.2;
    float t = u.time * 0.35;

    // The finger swirls the coordinates around itself.
    float2 toTouch = (px - u.touch) / unit;
    float swirl = u.touchStrength * exp(-dot(toTouch, toTouch) * 6.0);
    p += float2(-toTouch.y, toTouch.x) * swirl * 1.5;

    // Domain warping: each noise layer distorts the input of the next one.
    float2 q = float2(fbm(p + float2(0.0, t)),
                      fbm(p + float2(5.2, 1.3) - t));
    float2 r = float2(fbm(p + 4.0 * q + float2(1.7, 9.2) + 0.7 * t),
                      fbm(p + 4.0 * q + float2(8.3, 2.8) - 0.6 * t));
    float n = fbm(p + 4.0 * r);

    const float3 night       = float3(0.01, 0.00, 0.04);
    const float3 ultramarine = float3(0.07, 0.10, 0.65);
    const float3 violet      = float3(0.62, 0.10, 0.95);
    const float3 cyan        = float3(0.10, 0.95, 0.95);

    float3 color = mix(night, ultramarine, saturate(n * n * 3.0));
    color = mix(color, violet, saturate(length(q) - 0.45));
    color = mix(color, cyan, saturate(r.x * r.x * 1.6 - 0.35));

    // Electric filaments where the warped noise crosses its mid-level.
    float filament = pow(1.0 - abs(n - 0.5) * 2.0, 12.0);
    float energy = 0.35 + 0.65 * u.progress;
    color += float3(0.75, 0.95, 1.0) * filament * 1.2 * energy;
    color *= 0.45 + 0.75 * energy;
    color += cyan * swirl * 0.35;

    return float4(saturate(color), 1.0);
}
