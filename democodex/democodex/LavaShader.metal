#include <metal_stdlib>
using namespace metal;

// Matches the 16-byte Swift LavaUniforms layout exactly.
struct LavaUniforms {
    float2 resolution;
    float progress;
    float time;
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut lavaVertex(uint id [[vertex_id]]) {
    // An oversized triangle covers the viewport without a vertex buffer.
    const float2 vertices[] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
    VertexOut out;
    out.position = float4(vertices[id], 0, 1);
    return out;
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

float fbm(float2 p) {
    float sum = 0.0;
    float amplitude = 0.5;
    const float2x2 rotation = float2x2(0.8, -0.6, 0.6, 0.8);
    for (int octave = 0; octave < 5; ++octave) {
        sum += amplitude * noise(p);
        p = rotation * p * 2.03 + 7.1;
        amplitude *= 0.5;
    }
    return sum;
}

fragment float4 lavaFragment(VertexOut in [[stage_in]], constant LavaUniforms &u [[buffer(0)]]) {
    float2 uv = in.position.xy / max(u.resolution, float2(1));
    float3 track = float3(0.075, 0.045, 0.04);
    float progress = clamp(u.progress, 0.0, 1.0);
    if (progress <= 0.0) return float4(track, 1);

    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y) * 3.4;
    float t = u.time * 0.32;
    float2 flow = float2(fbm(p + float2(-t, t * 0.4)),
                         fbm(p + float2(5.2, -t * 0.7)));
    float heat = fbm(p + 2.7 * flow + float2(-t * 1.2, t * 0.3));
    float veins = pow(1.0 - abs(heat * 2.0 - 1.0), 7.0);
    float3 color = mix(float3(0.18, 0.006, 0.003), float3(0.92, 0.07, 0.005),
                       smoothstep(0.18, 0.55, heat));
    color = mix(color, float3(1.0, 0.42, 0.015), smoothstep(0.32, 0.88, veins));
    color = mix(color, float3(1.0, 0.83, 0.18), smoothstep(0.86, 1.0, veins) * 0.8);
    color *= 0.78 + 0.22 * sin(uv.y * M_PI_F);

    float pixel = 1.0 / max(u.resolution.x, 1.0);
    // The disturbance tapers near 0/1 so endpoints remain exact.
    float wave = sin(uv.y * 13.0 + t * 5.0) * 0.0035
               + (noise(float2(uv.y * 9, t * 2)) - 0.5) * 0.007;
    float edge = progress + wave * smoothstep(0.0, 0.04, progress)
                                * (1.0 - smoothstep(0.96, 1.0, progress));
    float distance = edge - uv.x;
    if (progress < 1.0) {
        float glow = exp(-abs(distance) * u.resolution.x / 9.0);
        float whiteEdge = exp(-abs(distance) * u.resolution.x / 1.8);
        color = mix(color, float3(1.0, 0.69, 0.13), glow * 0.85);
        color = mix(color, float3(1.0, 0.98, 0.83), whiteEdge);
        color = mix(track, color, smoothstep(-pixel, pixel, distance));
    }
    return float4(color, 1.0);
}
