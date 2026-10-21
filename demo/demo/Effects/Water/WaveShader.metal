//
//  WaveShader.metal
//  demo
//
//  Liquid wave progress: the surface is a sum of four sines plus a ripple around the finger,
//  with depth shading, caustics and procedural foam on the crest.
//

#include "../Core/ShaderCommon.h"

// Water surface height above the bottom edge, in pixels. Mirrored by `WaveShape` in Swift.
static float waveSurface(float x, constant EffectUniforms &u, float phase) {
    float unit = min(u.resolution.x, u.resolution.y);
    float t = u.time;
    float p = u.progress;
    // Flat when empty or full, so 0 and 1 read as exact values.
    float calm = smoothstep(0.0, 0.06, p) * (1.0 - smoothstep(0.94, 1.0, p));
    float xn = x / unit;
    float h = 0.045 * sin(xn * 4.1 + t * 1.6 + phase)
            + 0.030 * sin(xn * 7.3 - t * 2.3 + phase * 1.7)
            + 0.018 * sin(xn * 12.9 + t * 3.1 + phase * 0.6)
            + 0.010 * sin(xn * 21.7 - t * 4.2 + phase * 2.3);
    // Dragging raises a travelling ripple around the finger.
    float dx = (x - u.touch.x) / unit;
    h += u.touchStrength * 0.12 * exp(-dx * dx * 18.0) * cos(dx * 22.0 - t * 9.0);
    return p * u.resolution.y + h * unit * calm;
}

fragment float4 wave_fragment(FullscreenVertexOut in [[stage_in]],
                              constant EffectUniforms &u [[buffer(0)]]) {
    float2 px = in.uv * u.resolution;
    float y = u.resolution.y - px.y;                 // height above the bottom edge
    float unit = min(u.resolution.x, u.resolution.y);
    float t = u.time;
    float calm = smoothstep(0.0, 0.06, u.progress);

    float front = waveSurface(px.x, u, 0.0);
    float back = waveSurface(px.x, u, 2.1) + 0.02 * unit * calm;
    float dFront = front - y;                        // > 0 under water
    float dBack = back - y;

    // Air, then a translucent back wave for depth.
    float3 color = mix(float3(0.02, 0.04, 0.08), float3(0.04, 0.07, 0.13), in.uv.y);
    color = mix(color, float3(0.10, 0.45, 0.62), smoothstep(-1.0, 1.0, dBack) * 0.55);

    // Water body: turquoise under the surface fading to deep blue.
    float depth = saturate(dFront / (unit * 0.9));
    float3 water = mix(float3(0.10, 0.78, 0.80), float3(0.02, 0.10, 0.35), sqrt(depth));
    float2 q = px / unit * 6.0;
    float caustic = pow(1.0 - abs(fbm(q + float2(t * 0.3, -t * 0.2)) * 2.0 - 1.0), 6.0);
    water += caustic * 0.12 * (1.0 - depth);
    float inWater = smoothstep(-1.0, 1.0, dFront);
    color = mix(color, water, inWater);

    // Foam: a noisy white band under the surface, thicker on the crests, plus fine specks.
    float crest = saturate((front - u.progress * u.resolution.y) / (0.06 * unit));
    float foamNoise = fbm(float2(px.x / unit * 9.0 - t * 0.8, t * 0.5));
    float foamWidth = unit * (0.012 + 0.03 * foamNoise) * (0.6 + crest);
    float foam = (1.0 - smoothstep(0.0, foamWidth, dFront)) * (0.55 + 0.45 * foamNoise);
    float speck = step(0.72, valueNoise(px / unit * 40.0 + float2(-t * 2.0, 0.0)))
                * (1.0 - smoothstep(0.0, foamWidth * 2.5, dFront));
    color = mix(color, float3(0.92, 0.98, 1.0), saturate(foam * 0.85 + speck * 0.6) * inWater * calm);

    return float4(color, 1.0);
}
