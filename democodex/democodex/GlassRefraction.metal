#include "EffectShaderCommon.h"

namespace glass {
inline float sdf(float3 p, float radius, float t) {
    return length(p) - radius + sin(p.x * 9 + t * 0.7) * sin(p.y * 8 - t * 0.4) * 0.012;
}
inline float3 normal(float3 p, float radius, float t) {
    const float e = 0.001;
    return normalize(float3(sdf(p + float3(e,0,0),radius,t) - sdf(p - float3(e,0,0),radius,t),
                            sdf(p + float3(0,e,0),radius,t) - sdf(p - float3(0,e,0),radius,t),
                            sdf(p + float3(0,0,e),radius,t) - sdf(p - float3(0,0,e),radius,t)));
}
inline float3 backdrop(float2 p, float t) {
    float3 color = mix(float3(0.025, 0.04, 0.12), float3(0.14, 0.08, 0.35), clamp(p.y * 0.3 + 0.5, 0.0, 1.0));
    float2 q = p + float2(t * 0.08, 0);
    float2 grid = abs(fract(q * 2.5) - 0.5);
    float line = 1 - smoothstep(0.015, 0.025, min(grid.x, grid.y));
    color += float3(0.05, 0.12, 0.16) * line;
    float ribbon = exp(-pow((p.y - sin(p.x * 2 + t * 0.6) * 0.35) * 10, 2.0));
    color += float3(0.02, 0.7, 0.95) * ribbon;
    float circle = abs(length(p - float2(sin(t * 0.3) * 0.6, 0.5)) - 0.37);
    color += float3(1.0, 0.3, 0.12) * exp(-circle * 70);
    float bars = smoothstep(0.2, 0.24, abs(sin(q.x * 6))) * exp(-pow((p.y + 0.65) * 12, 2.0));
    return color + float3(0.3, 0.12, 0.75) * bars;
}
inline float3 environment(float3 origin, float3 dir, float t) {
    if (dir.z >= -0.01) return mix(float3(0.1, 0.2, 0.3), float3(0.8, 0.95, 1), pow(max(dir.y, 0.0), 8.0));
    float distance = (-2.0 - origin.z) / dir.z;
    return backdrop((origin + dir * distance).xy, t);
}
inline float3 transmit(float3 hit, float3 ray, float3 n, float radius, float ior, float t) {
    float3 inside = refract(ray, n, 1.0 / ior);
    float3 p = hit + inside * 0.005;
    float traveled = 0.005;
    // March from the entry to the second interface, inside the actual SDF.
    for (int i = 0; i < 32; ++i) {
        float d = sdf(p, radius, t);
        if (d > -0.001 && traveled > 0.01) break;
        float step = max(abs(d) * 0.8, 0.001);
        p += inside * step;
        traveled += step;
    }
    return p;
}
inline float3 channelRay(float3 hit, float3 ray, float3 n, float3 center, float radius, float ior, float t) {
    float3 p = transmit(hit, ray, n, radius, ior, t);
    float3 inside = refract(ray, n, 1.0 / ior);
    float3 outgoing = refract(inside, -normal(p, radius, t), ior);
    if (dot(outgoing, outgoing) < 0.001) outgoing = reflect(inside, -normal(p, radius, t));
    float absorption = exp(-length(p - hit) * 0.13);
    return environment(p + center, outgoing, t) * absorption;
}
}

fragment float4 glassRefractionFragment(EffectVertexOut in [[stage_in]], constant EffectUniforms &u [[buffer(0)]]) {
    float2 uv = effect::uv(in.position, u);
    float aspect = effect::aspect(u);
    float3 origin = float3(0, 0, 3);
    float3 ray = normalize(float3((uv.x - 0.5) * aspect * 1.8, (0.5 - uv.y) * 1.8, -2.4));
    float3 center = float3((u.touch.x - 0.5) * aspect * 2.25, (0.5 - u.touch.y) * 2.25, 0);
    float3 background = glass::environment(origin, ray, u.time);
    float radius = 0.34 + u.progress * 0.08;
    float3 relative = origin - center;
    // Bound the raymarch: background pixels avoid all surface iterations.
    float b = dot(relative, ray);
    float bound = radius + 0.03;
    float discriminant = b * b - dot(relative, relative) + bound * bound;
    if (discriminant < 0) return float4(background, 1);
    float distance = max(-b - sqrt(discriminant), 0.0);
    bool hit = false;
    float3 p = relative + ray * distance;
    for (int i = 0; i < 48; ++i) {
        p = relative + ray * distance;
        float d = glass::sdf(p, radius, u.time);
        if (d < 0.001) { hit = true; break; }
        distance += d * 0.8;
        if (distance > -b + sqrt(discriminant)) break;
    }
    if (!hit) return float4(background, 1);
    float3 n = glass::normal(p, radius, u.time);
    float ior = 1.12 + u.progress * 0.5;
    float3 red = glass::channelRay(p, ray, n, center, radius, ior - 0.02, u.time);
    float3 green = glass::channelRay(p, ray, n, center, radius, ior, u.time);
    float3 blue = glass::channelRay(p, ray, n, center, radius, ior + 0.025, u.time);
    float3 transmitted = float3(red.r, green.g, blue.b);
    float r0 = pow((1 - ior) / (1 + ior), 2.0);
    float fresnel = r0 + (1 - r0) * pow(1 - max(dot(-ray, n), 0.0), 5.0);
    float3 reflected = glass::environment(p + center, reflect(ray, n), u.time);
    float shine = pow(max(dot(reflect(normalize(float3(-1, 1.5, 2)), n), ray), 0.0), 80.0);
    float3 color = mix(transmitted, reflected, fresnel) + float3(0.8, 0.95, 1) * shine * 0.8;
    return float4(color, 1);
}
