#include <metal_stdlib>
using namespace metal;

struct VertexOut { float4 position [[position]]; float2 uv; };
struct Uniforms { float4 viewport; float4 input; float4 state; float4 options; };

vertex VertexOut effectVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return { float4(p * float2(2, -2) + float2(-1, 1), 0, 1), p };
}

float hash21(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), f.x),
               mix(hash21(i + float2(0, 1)), hash21(i + 1.0), f.x), f.y);
}
float fbm(float2 p) {
    return noise(p) * 0.57 + noise(p * 2.03) * 0.28 + noise(p * 4.01) * 0.15;
}
float3 spectrum(float t) { return 0.5 + 0.5 * cos(6.28318 * (t + float3(0, 0.33, 0.67))); }
float roundedBox(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

fragment float4 effectFragment(VertexOut v [[stage_in]], constant Uniforms &u [[buffer(0)]],
                               texture2d<float> source [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = v.uv;
    float2 size = u.viewport.xy;
    float t = u.viewport.z, strength = u.viewport.w;
    float2 touch = u.input.xy, tilt = u.input.zw;
    float2 p = (uv - 0.5) * float2(size.x / size.y, 1.0);
    float age = u.state.y;
    uint effect = uint(u.state.x);
    float3 color = float3(0.025, 0.032, 0.049);
    float alpha = 1;

    if (effect == 0) {
        float2 q = p * 1.8 + tilt * 0.35 + (touch - 0.5) * 0.65;
        q += float2(sin(q.y * 2.2 + t * 0.24), cos(q.x * 2.1 - t * 0.19)) * 0.45;
        float field = fbm(q * 2.2 + t * 0.09);
        float flow = sin(q.x * 2.0 + q.y * 2.5 + field * 4.0 + t * 0.3);
        color = mix(float3(0.08, 0.05, 0.26), float3(0.53, 0.36, 0.91), smoothstep(-0.9, 0.8, flow));
        color = mix(color, float3(0.88, 0.58, 0.43), smoothstep(0.46, 0.8, field + q.x * 0.12));
        color = mix(color, float3(0.20, 0.72, 0.79), pow(max(0.0, sin(q.y * 2.0 - field * 3.0)), 5.0) * 0.8);
        color *= 0.7 + strength * 0.45;
        color += (hash21(uv * size + fract(t)) - 0.5) * 0.025;
    } else if (effect == 1) {
        // The backdrop is a real UIKit snapshot; all refraction samples that texture.
        float2 panelSize = float2(0.39, 0.28);
        float d = roundedBox(p, panelSize * float2(size.x / size.y, 1), 0.11);
        float panel = 1.0 - smoothstep(-0.002, 0.003, d);
        float2 normal = normalize(p + 0.0001);
        float edge = exp(-abs(d) * 85.0);
        float2 delta = normal * edge * 0.022 * strength;
        delta += sin(uv.yx * 16.0 + t * 0.7) * 0.003 * strength;
        delta += (touch - 0.5 + tilt * 0.4) * 0.026 * strength;
        float3 blurred = 0;
        for (int x = -2; x <= 2; x++) {
            for (int y = -2; y <= 2; y++) {
                float2 sampleUV = uv + float2(x, y) * 0.007 + delta;
                float3 c = source.sample(s, sampleUV).rgb;
                c.r = source.sample(s, sampleUV + normal * edge * 0.009).r;
                c.b = source.sample(s, sampleUV - normal * edge * 0.009).b;
                blurred += c / 25.0;
            }
        }
        float3 glass = mix(blurred, float3(0.83, 0.88, 0.98), 0.13);
        glass += edge * (0.25 + 0.17 * sin(uv.x * 4.0 + t)) * strength;
        color = mix(source.sample(s, uv).rgb, glass, panel);
    } else if (effect == 2) {
        float d = roundedBox((uv - 0.5) * size, size * 0.5 - 13.0, 23.0);
        float angle = atan2(p.y, p.x);
        float3 aurora = spectrum(angle / 6.28318 - t * 0.14 + noise(p * 3.0 + t * 0.2) * 0.3);
        aurora = mix(aurora, float3(0.56, 0.41, 1.0), 0.18);
        color += aurora * (exp(-abs(d) * 0.5) * 1.1 + exp(-abs(d) * 0.075) * 0.35) * strength;
        color += float3(0.08, 0.045, 0.14) * (1.0 - smoothstep(-1.0, 1.0, d));
    } else if (effect == 3) {
        color = mix(float3(0.04, 0.09, 0.10), float3(0.06, 0.16, 0.15), uv.x);
        float2 dp = (uv - touch) * float2(size.x / size.y, 1);
        float dist = length(dp);
        float life = step(0.0, age) * (1.0 - smoothstep(0.1, 1.6, age));
        float wave = exp(-abs(dist - age * 0.75) * 35.0);
        float electricity = pow(max(0.0, sin(atan2(dp.y, dp.x) * 19.0 + dist * 50.0 - age * 16.0)), 12.0);
        float burst = exp(-dist * 7.0) * exp(-max(age, 0.0) * 4.0);
        color += float3(0.34, 1.0, 0.75) * (wave * (0.7 + electricity) + burst * 1.8) * life * strength;
    } else if (effect == 4) {
        float2 direction = (touch - 0.5) + tilt * 0.8;
        float band = uv.x * 1.3 + uv.y * 0.8 + dot(direction, float2(0.9, 1.2));
        float3 foil = spectrum(band + sin(uv.y * 5.0 + t * 0.2) * 0.09);
        float sheen = pow(max(0.0, 1.0 - abs(band - 0.85)), 12.0);
        float fine = pow(max(0.0, sin((uv.x + uv.y) * 420.0)), 18.0) * 0.1;
        color = mix(float3(0.13, 0.17, 0.24), foil, 0.45 + 0.25 * strength) + sheen * 0.55 + fine;
        float4 artwork = source.sample(s, uv);
        color = artwork.rgb + color * (1.0 - artwork.a);
    } else if (effect == 5) {
        float progress = u.state.z;
        float field = fbm(uv * float2(12, 7));
        // Threshold extends beyond the noise range so both endpoints are exact.
        float threshold = mix(-0.15, 1.15, progress);
        float remain = smoothstep(threshold, threshold + 0.035, field);
        float ember = exp(-abs(field - threshold - 0.02) * 65.0) * step(0.001, progress) * step(progress, 0.999);
        float4 original = source.sample(s, uv);
        color = original.rgb * remain + float3(1.0, 0.34, 0.06) * ember * strength;
        alpha = max(original.a * remain, ember);
        // GPU dust: drifting, scattered remnants near the moving burn front.
        float2 dustUV = uv + float2(-0.07, 0.18) * progress;
        float2 cell = floor(dustUV * size / 5.0);
        float seed = hash21(cell);
        float cellNoise = fbm((cell + 0.5) * 5.0 / size * float2(12, 7));
        float dust = step(0.88, seed) * exp(-length(fract(dustUV * size / 5.0) - 0.5) * 11.0);
        dust *= exp(-abs(cellNoise - threshold) * 18.0) * sin(progress * 3.14159);
        color += float3(1, 0.64, 0.25) * dust * strength;
        alpha = max(alpha, dust);
        if (progress >= 1.0) { color = 0; alpha = 0; }
    } else {
        float4 glyph = source.sample(s, uv);
        float bloom = 0;
        for (int i = 0; i < 12; i++) {
            float angle = float(i) * 6.28318 / 12.0;
            float2 offset = float2(cos(angle), sin(angle)) / size;
            bloom += source.sample(s, uv + offset * 5.0).a * 0.045;
            bloom += source.sample(s, uv + offset * 13.0).a * 0.025;
        }
        float breathe = 0.8 + 0.2 * sin(t * 1.5);
        color = float3(0.60, 0.40, 1) * bloom * breathe * strength + glyph.rgb;
        alpha = saturate(bloom * strength + glyph.a);
        float life = step(0.0, age) * (1.0 - smoothstep(0.2, 1.7, age));
        for (int i = 0; i < 28; i++) {
            float seed = hash21(float2(i, 7));
            float angle = seed * 6.28318;
            float2 velocity = float2(cos(angle), sin(angle)) * (0.13 + hash21(float2(i, 2)) * 0.22);
            float2 pos = touch + velocity * age * float2(size.y / size.x, 1) + float2(0, age * age * 0.07);
            float spark = exp(-length((uv - pos) * size) * 0.55) * life * strength;
            color += float3(0.8, 0.63, 1) * spark;
            alpha = max(alpha, spark);
        }
    }
    // CAMetalLayer compositing expects premultiplied color for transparent surfaces.
    return float4(min(color, float3(alpha)), alpha);
}
