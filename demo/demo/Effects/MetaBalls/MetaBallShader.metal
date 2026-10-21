//
//  MetaBallShader.metal
//  demo
//
//  Metaballs: the field f(x, y) = sum(R_i^2 / |p - c_i|^2) is evaluated per pixel and the
//  iso-surface f = 1 is cut out with smoothstep. The field gradient gives a normal for
//  liquid-metal shading.
//

#include "../Core/ShaderCommon.h"

fragment float4 metaball_fragment(FullscreenVertexOut in [[stage_in]],
                                  constant EffectUniforms &u [[buffer(0)]]) {
    float2 px = in.uv * u.resolution;
    float unit = min(u.resolution.x, u.resolution.y);

    float field = 0.0;
    float2 gradient = 0.0;
    for (int i = 0; i < u.blobCount; i++) {
        float2 d = px - u.blobs[i].xy;
        float r2 = u.blobs[i].z * u.blobs[i].z;
        float dist2 = max(dot(d, d), 1.0);
        field += r2 / dist2;
        gradient += -2.0 * r2 * d / (dist2 * dist2);
    }
    // While touching, the finger is an extra small blob that the others merge into.
    if (u.touchStrength > 0.001) {
        float2 d = px - u.touch;
        float r = unit * 0.08 * u.touchStrength;
        float dist2 = max(dot(d, d), 1.0);
        field += r * r / dist2;
        gradient += -2.0 * r * r * d / (dist2 * dist2);
    }

    // Anti-aliased iso-surface at f = 1.
    float fw = max(fwidth(field), 1e-4);
    float inside = smoothstep(1.0 - fw, 1.0 + fw, field);

    // Liquid metal: environment reflection by normal, colored rim, sharp specular.
    float3 n = normalize(float3(-gradient * unit * 0.07, 1.0));
    float3 r = reflect(float3(0.0, 0.0, -1.0), n);
    float3 sky = mix(float3(0.85, 0.90, 1.00), float3(0.12, 0.14, 0.20), saturate(r.y * 0.5 + 0.5));
    float3 tint = mix(float3(0.20, 0.90, 1.00), float3(1.00, 0.30, 0.80), saturate(r.x * 0.5 + 0.5));
    float rim = pow(1.0 - n.z, 2.0);
    float specular = pow(saturate(dot(r, normalize(float3(-0.4, -0.6, 0.7)))), 40.0);
    float3 metal = sky * 0.75 + tint * (0.15 + 0.5 * rim) + specular;

    // Background with a soft glow where blobs are close.
    float3 background = mix(float3(0.03, 0.035, 0.05), float3(0.05, 0.06, 0.09), in.uv.y);
    background += float3(0.10, 0.45, 0.60) * smoothstep(0.25, 1.0, field) * 0.25;

    return float4(mix(background, metal, inside), 1.0);
}
