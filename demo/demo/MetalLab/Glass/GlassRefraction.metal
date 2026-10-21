//
//  GlassRefraction.metal
//  demo
//
//  Raymarched glass lens over an animated backdrop: the lens is an ellipsoid SDF (stretched into
//  a droplet along the drag direction). Each pixel's ray is refracted into the glass, marched to
//  the back surface, refracted out and projected onto the backdrop plane. Fresnel reflection,
//  specular and inner highlights and per-channel dispersion (RGB shift at the rim) on top.
//
//  custom[0] = (lens center x, y in pixels, radius in pixels, unused)
//  custom[1] = (lens velocity x, y in pixels per second, unused, unused)
//

#include "../../Effects/Core/ShaderCommon.h"

constant float3 kDiscColors[3] = {
    float3(1.00, 0.35, 0.55),
    float3(0.25, 0.85, 1.00),
    float3(1.00, 0.80, 0.25),
};

// Animated backdrop. A pure function of position, so refracted rays can sample it anywhere.
static float3 backdrop(float2 px, float2 resolution, float t) {
    float unit = min(resolution.x, resolution.y);
    float2 q = px / unit;

    // Slowly flowing color field (cosine palette).
    float2 warp = 0.3 * sin(q.yx * 2.0 + t * 0.4);
    float phase = q.x * 0.35 + q.y * 0.25 + t * 0.05 + warp.x + warp.y;
    float3 color = (0.5 + 0.5 * cos(6.2831 * (phase + float3(0.0, 0.33, 0.67)))) * 0.55;

    // Orbiting bright discs.
    float2 size = resolution / unit;
    for (int i = 0; i < 3; i++) {
        float a = t * 0.35 + float(i) * 2.094;
        float2 c = size * float2(0.5 + 0.3 * cos(a), 0.5 + 0.25 * sin(a * 1.3));
        float d = length(q - c) * unit;
        float r = unit * 0.13;
        color = mix(color, kDiscColors[i], 1.0 - smoothstep(r - 1.0, r + 1.0, d));
    }

    // Thin grid lines, so the refraction visibly bends straight edges.
    const float cells = 7.0;
    float2 g = abs(fract(q * cells) - 0.5);
    float lineDistance = (0.5 - max(g.x, g.y)) / cells * unit;
    color = mix(color, float3(1.0), (1.0 - smoothstep(0.5, 1.5, lineDistance)) * 0.35);
    return color;
}

static float sdEllipsoid(float3 p, float3 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

// Lens space: units of the lens radius, z towards the viewer.
static float lensSDF(float3 p, float2 axis, float stretch) {
    float2 local = float2(dot(p.xy, axis), dot(p.xy, float2(-axis.y, axis.x)));
    float3 q = float3(local.x / (1.0 + stretch), local.y / (1.0 - 0.4 * stretch), p.z);
    // Scaled by the smallest axis factor to stay a conservative distance bound.
    return sdEllipsoid(q, float3(1.0, 1.0, 0.42)) * (1.0 - 0.4 * stretch);
}

static float3 lensNormal(float3 p, float2 axis, float stretch) {
    const float2 e = float2(0.001, -0.001);
    return normalize(e.xyy * lensSDF(p + e.xyy, axis, stretch)
                   + e.yyx * lensSDF(p + e.yyx, axis, stretch)
                   + e.yxy * lensSDF(p + e.yxy, axis, stretch)
                   + e.xxx * lensSDF(p + e.xxx, axis, stretch));
}

fragment float4 glass_fragment(FullscreenVertexOut in [[stage_in]],
                               constant EffectUniforms &u [[buffer(0)]]) {
    float2 px = in.uv * u.resolution;
    float t = u.time;
    float3 base = backdrop(px, u.resolution, t);

    float2 center = u.custom[0].xy;
    float radius = max(u.custom[0].z, 1.0);
    float2 velocity = u.custom[1].xy;
    float speed = length(velocity);
    float stretch = clamp(speed / (radius * 12.0), 0.0, 0.35);
    float2 axis = speed > 1.0 ? velocity / speed : float2(1.0, 0.0);
    float2 lp = (px - center) / radius;

    // Soft shadow on the backdrop, with light focused through the lens in its middle.
    float2 sp = lp - float2(0.08, 0.18);
    base *= 1.0 - 0.35 * (1.0 - smoothstep(0.6, 1.25, length(sp)));
    base += float3(1.0, 0.95, 0.85) * pow(1.0 - smoothstep(0.0, 0.5, length(sp)), 2.0) * 0.12;

    // Only pixels under the lens are raymarched.
    if (length(lp) > 1.0 + stretch + 0.05) {
        return float4(base, 1.0);
    }

    // Orthographic ray straight into the screen.
    const float3 rd = float3(0.0, 0.0, -1.0);
    float3 p = float3(lp, 1.0);
    bool hit = false;
    for (int i = 0; i < 48; i++) {
        float d = lensSDF(p, axis, stretch);
        if (d < 0.0005) {
            hit = true;
            break;
        }
        p += rd * d * 0.9;
        if (p.z < -1.0) break;
    }
    if (!hit) {
        return float4(base, 1.0);
    }

    float3 n = lensNormal(p, axis, stretch);
    const float ior = 1.5;
    float3 inside = refract(rd, n, 1.0 / ior);

    // March through the glass to the back surface.
    float3 q = p - n * 0.002;
    float thickness = 0.0;
    for (int i = 0; i < 32; i++) {
        float d = -lensSDF(q, axis, stretch);
        if (d < 0.0005) break;
        float step = max(d * 0.9, 0.004);
        q += inside * step;
        thickness += step;
    }
    float3 backNormal = lensNormal(q, axis, stretch);
    float3 outside = refract(inside, -backNormal, ior);
    if (dot(outside, outside) < 1e-4) {
        outside = reflect(inside, -backNormal);   // total internal reflection
    }

    // Where the ray lands on the backdrop plane below the lens, relative to the straight path.
    const float backdropDepth = -0.6;
    float travel = (backdropDepth - q.z) / min(outside.z, -0.05);
    float2 landing = q.xy + outside.xy * travel;
    float2 offset = (landing - lp) * radius;

    // Dispersion: red bends less, blue more, strongest towards the rim.
    float rim = 1.0 - n.z;
    float spread = 0.05 + 0.3 * rim;
    float3 refracted = float3(backdrop(px + offset * (1.0 - spread), u.resolution, t).r,
                              backdrop(px + offset, u.resolution, t).g,
                              backdrop(px + offset * (1.0 + spread), u.resolution, t).b);
    refracted *= mix(float3(1.0), float3(0.86, 0.94, 1.0), saturate(thickness));

    // Fresnel reflection of a soft studio light, a sharp specular and an inner crescent where
    // light entering from the top-left focuses on the opposite rim.
    const float3 light = normalize(float3(-0.5, -0.6, 0.65));
    float3 reflected = reflect(rd, n);
    float facing = saturate(dot(reflected, light));
    float fresnel = 0.04 + 0.96 * pow(1.0 - saturate(n.z), 5.0);
    float3 environment = float3(0.85, 0.9, 1.0) * (0.25 + 0.75 * saturate(dot(reflected, light) * 0.5 + 0.5));
    float specular = pow(facing, 80.0) * 1.5 + pow(facing, 8.0) * 0.15;
    float crescent = pow(saturate(dot(n.xy, normalize(-light.xy))), 3.0) * pow(rim, 1.5) * 0.6;
    float3 color = mix(refracted, environment, fresnel) + specular + crescent * float3(1.0, 0.97, 0.9);

    // Anti-aliased silhouette.
    float edge = lensSDF(float3(lp, 0.0), axis, stretch);
    float coverage = 1.0 - smoothstep(-1.0 / radius, 0.5 / radius, edge);
    return float4(mix(base, saturate(color), coverage), 1.0);
}
