//
//  Shaders.metal
//  controller
//
//  Fragment shaders for MetalTransitionAnimator.
//  Texture 0 = outgoing screen, texture 1 = incoming screen, buffer 0 = TransitionUniforms.
//  UV origin is top-left (matches the snapshot textures). Every effect returns exactly
//  `fromTex` at progress 0 and exactly `toTex` at progress 1, so the hand-off to UIKit is seamless.
//

#include <metal_stdlib>
using namespace metal;

// Keep in sync with `TransitionUniforms` in MetalTransitionAnimator.swift.
struct TransitionUniforms {
    float  progress;   // 0 → 1, linear in time (or finger position when interactive)
    float  time;       // seconds since the transition started
    float2 resolution; // drawable size in pixels
    float2 touch;      // touch point, normalized 0…1, top-left origin
    float  aspect;     // width / height
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// One oversized triangle covers the whole screen — no vertex buffer needed.
vertex VertexOut transition_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    VertexOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

constexpr sampler texSampler(coord::normalized, address::clamp_to_edge, filter::linear);

#define TRANSITION_ARGS                                   \
    VertexOut in [[stage_in]],                            \
    texture2d<float> fromTex [[texture(0)]],              \
    texture2d<float> toTex   [[texture(1)]],              \
    constant TransitionUniforms &u [[buffer(0)]]

// MARK: - Helpers

static float2 rotate2d(float2 v, float a) {
    float s = sin(a), c = cos(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// UV → aspect-corrected offset from `c`, so circles stay circular on a tall screen.
static float2 toAspect(float2 uv, float2 c, float aspect) {
    float2 d = uv - c;
    d.x *= aspect;
    return d;
}

static float2 fromAspect(float2 d, float2 c, float aspect) {
    return c + float2(d.x / aspect, d.y);
}

// Distance from `c` to the farthest screen corner, in aspect space.
static float maxCornerDistance(float2 c, float aspect) {
    float2 f = max(c, 1.0 - c);
    f.x *= aspect;
    return length(f);
}

static float easeInOutCubic(float t) {
    return t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5;
}

// 0 at both ends, 1 in the middle. Clamped: sin(π·1.0) is slightly negative in float.
static float bell(float p) {
    return max(sin(M_PI_F * p), 0.0);
}

static float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 2D simplex noise (Ashima Arts / Ian McEwan, MIT).
static float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float2 mod289(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float3 permute(float3 x) { return mod289(((x * 34.0) + 10.0) * x); }

static float simplex(float2 v) {
    const float4 C = float4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
    float2 i  = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);
    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289(i);
    float3 p = permute(permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));
    float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), float3(0.0));
    m = m * m;
    m = m * m;
    float3 x = 2.0 * fract(p * C.www) - 1.0;
    float3 h = abs(x) - 0.5;
    float3 ox = floor(x + 0.5);
    float3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    float3 g;
    g.x  = a0.x  * x0.x   + h.x  * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

// Fractal Brownian motion, roughly in [-1, 1].
static float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; ++i) {
        value += amplitude * simplex(p);
        p = p * 2.03 + 17.0;
        amplitude *= 0.5;
    }
    return value;
}

// =====================================================================
// MARK: - 1. Distortion & Geometry
// =====================================================================

// Ripple Dissolve — concentric waves run out from the touch point; the old screen
// refracts along a damped sine and dissolves into the new one behind the wave front.
fragment float4 ripple_dissolve_fragment(TRANSITION_ARGS) {
    float p = u.progress;
    float2 d = toAspect(in.uv, u.touch, u.aspect);
    float dist = length(d);
    float2 dir = dist > 1e-5 ? d / dist : float2(0.0);

    float maxR = maxCornerDistance(u.touch, u.aspect);
    float front = mix(-0.25, maxR + 0.25, p);

    // Waves live behind (and slightly ahead of) the front, decaying with radius and time.
    float envelope = bell(p) * exp(-dist * 2.2) * (1.0 - smoothstep(front, front + 0.3, dist));
    float wave = sin(dist * 60.0 - p * 50.0);
    float2 offset = dir * wave * envelope * 0.035;
    offset.x /= u.aspect;

    float4 a = fromTex.sample(texSampler, in.uv + offset);
    float4 b = toTex.sample(texSampler, in.uv - offset * 0.6);

    float reveal = 1.0 - smoothstep(front - 0.22, front, dist);
    float3 color = mix(a.rgb, b.rgb, reveal);

    // Specular glint on the wave crests.
    color += pow(max(wave, 0.0), 10.0) * envelope * 0.45;
    return float4(color, 1.0);
}

// Vortex / Swirl — the old screen twists into a spiral around the center and gets sucked
// into it, while the new screen unwinds from a slight counter-twist underneath.
fragment float4 vortex_fragment(TRANSITION_ARGS) {
    float p = u.progress;
    float e = easeInOutCubic(p);
    float2 c = float2(0.5);
    float2 d = toAspect(in.uv, c, u.aspect);
    float r = length(d);
    float rn = r / maxCornerDistance(c, u.aspect);

    // Twist angle grows with progress; the inner area spins faster, giving a spiral.
    float angle = e * (3.0 + 11.0 * (1.0 - rn) * (1.0 - rn));
    float2 sd = rotate2d(d, angle) * (1.0 + 7.0 * e * e * e);   // > 1: content contracts inward
    float2 suv = fromAspect(sd, c, u.aspect);

    float2 aa = fwidth(suv);
    float2 inside = smoothstep(-aa, float2(0.0), suv) * smoothstep(-aa, float2(0.0), 1.0 - suv);
    float fromMask = inside.x * inside.y * (1.0 - smoothstep(0.75, 1.0, p));
    float4 a = fromTex.sample(texSampler, suv);
    a.rgb *= mix(1.0, 0.6, e * smoothstep(0.0, 0.6, 1.0 - rn)); // the eye of the vortex darkens

    float back = 1.0 - e;
    float2 td = rotate2d(d, -back * 1.4 * (1.0 - rn)) * (1.0 - 0.25 * back);
    float4 b = toTex.sample(texSampler, fromAspect(td, c, u.aspect));
    b.rgb *= mix(0.55, 1.0, e);

    return float4(mix(b.rgb, a.rgb, fromMask), 1.0);
}

// MARK: Page curl helpers

static float2 curlMaterialUV(float tAlong, float tAcross, float2 n, float2 w, float aspect) {
    float2 P = n * tAlong + w * tAcross;
    return float2(P.x / aspect, P.y);
}

static bool insidePage(float2 uv) {
    return all(uv >= 0.0) && all(uv <= 1.0);
}

// Lambert + Blinn-Phong, normalized so a flat page facing the camera keeps its original color.
static float3 shadeCurl(float3 base, float3 N, float specular) {
    const float3 L = normalize(float3(0.8, 0.0, 0.6));  // (along curl, across curl, up)
    const float3 V = float3(0.0, 0.0, 1.0);
    const float ambient = 0.35;
    float flat = ambient + (1.0 - ambient) * L.z;
    float diffuse = ambient + (1.0 - ambient) * max(dot(N, L), 0.0);
    float spec = pow(max(dot(N, normalize(L + V)), 0.0), 64.0) * specular;
    return base * (diffuse / flat) + spec;
}

static float3 paperBack(float3 c) {
    return mix(c, float3(0.96), 0.6);   // translucent paper: mirrored content shows through
}

// 3D Page Curl & Wave — the page rolls around a cylinder that travels from the
// bottom-right corner to the top-left, with per-pixel normals, lighting and shadow.
// The fold line ripples slightly so the material feels flexible.
fragment float4 page_curl_fragment(TRANSITION_ARGS) {
    float p = easeInOutCubic(u.progress);
    float aspect = u.aspect;
    float2 P = float2(in.uv.x * aspect, in.uv.y);

    const float2 n = normalize(float2(-1.0, -0.3));  // direction the fold travels
    const float2 w = float2(-n.y, n.x);              // along the fold line
    const float R = 0.14;                            // cylinder radius (in screen heights)

    float t = dot(P, n);
    float across = dot(P, w);

    float c1 = aspect * n.x, c2 = n.y, c3 = aspect * n.x + n.y;
    float tMin = min(min(0.0, c1), min(c2, c3));
    float tMax = max(max(0.0, c1), max(c2, c3));

    float f = mix(tMin, tMax + M_PI_F * R + 0.05, p);
    f += 0.025 * sin(across * 7.0 + p * 9.0) * bell(u.progress);   // flexible wave in the fold

    float4 under = toTex.sample(texSampler, in.uv);
    float3 color;

    if (t >= f) {
        // Either the back of the page that already turned over, or the untouched flat page.
        float2 uvBack = curlMaterialUV(2.0 * f - t - M_PI_F * R, across, n, w, aspect);
        if (insidePage(uvBack)) {
            color = paperBack(fromTex.sample(texSampler, uvBack).rgb);
            // Contact shadow where the turned page meets the cylinder.
            color *= 1.0 - 0.15 * exp(-(t - f) / (R * 0.5));
        } else {
            color = fromTex.sample(texSampler, in.uv).rgb;
            color *= 1.0 - 0.3 * exp(-(t - f) / (R * 0.7)) * smoothstep(0.0, 0.05, u.progress);
        }
    } else if (t >= f - R) {
        // On the cylinder: the upper half (back side) occludes the lower half (front side).
        float th1 = asin(clamp((f - t) / R, 0.0, 1.0));
        float th2 = M_PI_F - th1;
        float2 uvUpper = curlMaterialUV(f - th2 * R, across, n, w, aspect);
        float2 uvLower = curlMaterialUV(f - th1 * R, across, n, w, aspect);
        if (insidePage(uvUpper)) {
            float3 N = float3(-sin(th2), 0.0, -cos(th2));
            color = shadeCurl(paperBack(fromTex.sample(texSampler, uvUpper).rgb), N, 0.25);
        } else if (insidePage(uvLower)) {
            float3 N = float3(sin(th1), 0.0, cos(th1));
            color = shadeCurl(fromTex.sample(texSampler, uvLower).rgb, N, 0.6);
        } else {
            color = under.rgb * 0.55;
        }
    } else {
        // Exposed new screen, with a soft shadow cast by the curl.
        float2 uvTop = curlMaterialUV(f - 0.5 * M_PI_F * R, across, n, w, aspect);
        float shadow = insidePage(uvTop) ? 0.45 * exp(-(f - R - t) / 0.08) : 0.0;
        color = under.rgb * (1.0 - shadow);
    }
    return float4(color, 1.0);
}

// =====================================================================
// MARK: - 2. Digital & Glitch
// =====================================================================

// Perlin Noise Dissolve — the old screen burns away in organic fbm-noise blotches
// spreading from the touch point, with a glowing neon rim on the burning edge.
fragment float4 noise_dissolve_fragment(TRANSITION_ARGS) {
    float p = u.progress;
    float2 np = float2(in.uv.x * u.aspect, in.uv.y) * 4.0;
    float noise = fbm(np + float2(0.0, u.time * 0.15)) * 0.5 + 0.5;
    float radial = length(toAspect(in.uv, u.touch, u.aspect)) / maxCornerDistance(u.touch, u.aspect);
    float v = mix(noise, radial, 0.45);

    const float edge = 0.08;
    float threshold = mix(-2.0 * edge, 1.0 + edge, p);
    float aa = max(fwidth(v), 1e-4);
    float burned = 1.0 - smoothstep(threshold - aa, threshold + aa, v);
    float band = (1.0 - smoothstep(threshold, threshold + edge, v)) * (1.0 - burned);

    float3 a = fromTex.sample(texSampler, in.uv).rgb;
    float3 b = toTex.sample(texSampler, in.uv).rgb;

    float3 charred = a * (1.0 - 0.85 * smoothstep(0.0, 1.0, band));
    const float3 neonOuter = float3(1.0, 0.1, 0.75);
    const float3 neonInner = float3(0.3, 1.0, 1.0);
    float3 glow = mix(neonOuter, neonInner, pow(band, 3.0)) * band * band * 2.4;

    return float4(mix(charred + glow, b, burned), 1.0);
}

// Pixelate / Mosaic — cells grow to a coarse mosaic, shuffle around, then each cell
// flips to the new screen at its own moment and the mosaic resolves back to full detail.
fragment float4 pixelate_fragment(TRANSITION_ARGS) {
    float p = u.progress;
    float k = bell(p);
    float maxCell = max(u.resolution.x, u.resolution.y) / 14.0;
    float cellPx = max(1.0, floor(exp2(k * log2(maxCell))));
    float2 cell = float2(cellPx) / u.resolution;

    float2 id = floor(in.uv / cell);
    float2 jitter = (float2(hash12(id + cellPx * 0.731), hash12(id + 7.7 + cellPx)) - 0.5) * 3.0 * k * k;
    float2 center = (id + 0.5 + jitter) * cell;

    // 4-tap box filter inside the cell (collapses to one exact tap at 1 px).
    float2 q = cell * (cellPx > 1.5 ? 0.25 : 0.0);
    float4 a = 0.25 * (fromTex.sample(texSampler, center + float2(-q.x, -q.y)) +
                       fromTex.sample(texSampler, center + float2( q.x, -q.y)) +
                       fromTex.sample(texSampler, center + float2(-q.x,  q.y)) +
                       fromTex.sample(texSampler, center + float2( q.x,  q.y)));
    float4 b = 0.25 * (toTex.sample(texSampler, center + float2(-q.x, -q.y)) +
                       toTex.sample(texSampler, center + float2( q.x, -q.y)) +
                       toTex.sample(texSampler, center + float2(-q.x,  q.y)) +
                       toTex.sample(texSampler, center + float2( q.x,  q.y)));

    float flip = smoothstep(0.35, 0.65, p + (hash12(id * 1.37 + 11.0) - 0.5) * 0.3);
    float3 color = mix(a.rgb, b.rgb, flip);

    // Thin bevel between tiles once they're big enough to read as tiles.
    float2 f = fract(in.uv / cell);
    float bevel = smoothstep(0.0, 0.06, min(min(f.x, f.y), min(1.0 - f.x, 1.0 - f.y)));
    color *= mix(1.0, 0.85 + 0.15 * bevel, smoothstep(4.0, 12.0, cellPx));
    return float4(color, 1.0);
}

static float3 rgbSplit(texture2d<float> tex, float2 uv, float2 offset) {
    return float3(tex.sample(texSampler, uv + offset).r,
                  tex.sample(texSampler, uv).g,
                  tex.sample(texSampler, uv - offset).b);
}

// Digital Glitch & RGB Split — random horizontal slices and blocks jump sideways,
// R/G/B channels tear apart, and slices flip to the new screen at random moments.
fragment float4 glitch_fragment(TRANSITION_ARGS) {
    float p = u.progress;
    float k = pow(bell(p), 0.7);
    float tick = floor(u.time * 30.0);   // re-roll the corruption 30× per second
    float2 uv = in.uv;

    float rows = mix(8.0, 40.0, hash12(float2(tick, 1.0)));
    float row = floor(uv.y * rows);
    float sliceOn = step(1.0 - 0.6 * k, hash12(float2(row, tick)));
    float shift = (hash12(float2(row, tick + 7.0)) - 0.5) * 0.25 * k * sliceOn;

    float2 block = floor(uv * float2(6.0, 14.0));
    float blockOn = step(1.0 - 0.25 * k, hash12(block + tick * 0.37));
    float2 blockShift = (float2(hash12(block + 3.0 + tick), hash12(block + 5.0 + tick)) - 0.5) * 0.12 * k * blockOn;

    float2 guv = uv + float2(shift, 0.0) + blockShift;
    float2 split = float2(0.025 * k * (0.5 + hash12(float2(tick, 3.0))), 0.0);

    // Fixed 24-row grid decides when each slice switches screens; occasional crosstalk flips it back.
    float switchAt = 0.3 + 0.4 * hash12(float2(floor(uv.y * 24.0), 99.0));
    bool showTo = p >= switchAt;
    if (hash12(float2(row, tick + 13.0)) > 1.0 - 0.07 * k) {
        showTo = !showTo;
    }
    float3 color = showTo ? rgbSplit(toTex, guv, split) : rgbSplit(fromTex, guv, split);

    float scan = 0.92 + 0.08 * sin(uv.y * u.resolution.y * 1.5);
    color *= mix(1.0, scan, k);
    color += (hash12(uv * u.resolution + tick) - 0.5) * 0.12 * k;
    return float4(color, 1.0);
}

// =====================================================================
// MARK: - 3. Optics & Blurs
// =====================================================================

static float4 radialBlur(texture2d<float> tex, float2 uv, float2 center, float strength) {
    const int samples = 20;
    float2 dir = (center - uv) * strength;
    float4 acc = float4(0.0);
    float weightSum = 0.0;
    for (int i = 0; i < samples; ++i) {
        float t = float(i) / float(samples - 1);
        float weight = 1.0 - 0.5 * t;
        acc += tex.sample(texSampler, uv + dir * t) * weight;
        weightSum += weight;
    }
    return acc / weightSum;
}

// Zoom Lens & Radial Blur — the camera lunges into the touch point with heavy radial
// motion blur toward the edges, and the new screen settles out of the same zoom.
fragment float4 zoom_blur_fragment(TRANSITION_ARGS) {
    float p = u.progress;
    float2 c = u.touch;
    float strength = bell(p) * 0.35;

    float zoomFrom = mix(1.0, 0.12, p * p);                        // < 1 = magnified
    float zoomTo = mix(0.35, 1.0, 1.0 - pow(1.0 - p, 3.0));
    float4 a = radialBlur(fromTex, c + (in.uv - c) * zoomFrom, c, strength);
    float4 b = radialBlur(toTex,   c + (in.uv - c) * zoomTo,   c, strength);

    float3 color = mix(a.rgb, b.rgb, smoothstep(0.4, 0.6, p));
    color += exp(-pow((p - 0.5) * 7.0, 2.0)) * 0.25;               // exposure flash at the cut
    return float4(color, 1.0);
}

// Chromatic Tunnel / Portal — a circular portal opens at the touch point; the old screen
// is dragged into its rim with RGB-split refraction, and the new screen unfolds inside.
fragment float4 chromatic_portal_fragment(TRANSITION_ARGS) {
    float p = u.progress;
    float e = easeInOutCubic(p);
    float k = bell(p);
    float2 c = u.touch;
    float2 d = toAspect(in.uv, c, u.aspect);
    float r = length(d);
    float2 dir = r > 1e-5 ? d / r : float2(0.0);

    float radius = e * (maxCornerDistance(c, u.aspect) + 0.15);
    float rim = 0.004 + 0.07 * k;

    // Outside: pull content toward the rim; each channel refracts by a different amount.
    float pull = radius * 0.6 * exp(-max(r - radius, 0.0) * 7.0) * k;
    float aberr = 0.12 * k;
    float3 outer = float3(
        fromTex.sample(texSampler, fromAspect(dir * (r + pull * (1.0 + aberr)), c, u.aspect)).r,
        fromTex.sample(texSampler, fromAspect(dir * (r + pull),                 c, u.aspect)).g,
        fromTex.sample(texSampler, fromAspect(dir * (r + pull * (1.0 - aberr)), c, u.aspect)).b);
    outer *= 1.0 - 0.35 * k * exp(-max(r - radius, 0.0) * 5.0);

    // Inside: the new screen unfolds from a twisted, shrunken state; edge of the lens splits RGB.
    float back = 1.0 - e;
    float lens = smoothstep(radius - rim * 3.0, radius, r) * 0.04 * k;
    float2 td = rotate2d(d, back * 1.6) * mix(1.0, 1.4, back);
    float3 inner = float3(
        toTex.sample(texSampler, fromAspect(td * (1.0 + lens), c, u.aspect)).r,
        toTex.sample(texSampler, fromAspect(td,                c, u.aspect)).g,
        toTex.sample(texSampler, fromAspect(td * (1.0 - lens), c, u.aspect)).b);

    float aa = max(fwidth(r), 1e-4);
    float inside = (1.0 - smoothstep(radius - aa, radius + aa, r)) * step(1e-4, e);
    float3 color = mix(outer, inner, inside);

    // Iridescent ring along the rim.
    float ring = exp(-pow((r - radius) / rim, 2.0));
    float hue = atan2(d.y, d.x) / (2.0 * M_PI_F) + p * 1.5;
    float3 rainbow = 0.5 + 0.5 * cos(2.0 * M_PI_F * (hue + float3(0.0, 0.33, 0.67)));
    color += rainbow * ring * 0.9 * k;
    return float4(color, 1.0);
}
