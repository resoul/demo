//
//  ParticleCompute.metal
//  controller
//
//  Particle physics for ParticleMorphEngine: one kernel, one thread per particle, six scenarios.
//  Positions are in points (UIKit space, y down); every mode is frame-rate independent.
//

#include <metal_stdlib>
#include "ParticleStructures.h"
using namespace metal;

// MARK: - Noise

// 3D simplex noise (Ian McEwan, Ashima Arts / Stefan Gustavson, MIT license). Range ≈ −1…1.
static float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 permute(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }
static float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

static float snoise(float3 v) {
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);

    float3 i = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);

    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);
    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;

    i = mod289(i);
    float4 p = permute(permute(permute(i.z + float4(0.0, i1.z, i2.z, 1.0))
                                       + i.y + float4(0.0, i1.y, i2.y, 1.0))
                                       + i.x + float4(0.0, i1.x, i2.x, 1.0));

    float n_ = 0.142857142857;   // 1/7
    float3 ns = n_ * D.wyz - D.xzx;
    float4 j = p - 49.0 * floor(p * ns.z * ns.z);
    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);
    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);

    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);
    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));
    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);
    float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// Divergence-free 2D flow: the curl of a noise potential. Particles swirl in eddies instead of
// bunching up, which is what makes the "vortex" read as a fluid.
static float2 curlNoise(float2 p, float t) {
    const float e = 0.08;
    float dx = snoise(float3(p.x + e, p.y, t)) - snoise(float3(p.x - e, p.y, t));
    float dy = snoise(float3(p.x, p.y + e, t)) - snoise(float3(p.x, p.y - e, t));
    return float2(dy, -dx) / (2.0 * e);
}

static float hash11(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffff);
}

// MARK: - Helpers

/// Per-particle start offset: `spread` of the timeline is used to stagger particles by seed.
static float stagger(float progress, float seed, float spread) {
    return saturate((progress - seed * spread) / (1.0 - spread));
}

static float smootherstep01(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

/// Exact step of the critically damped spring F = −k·(pos − target) − c·v with k = ω², c = 2ω.
/// Closed form instead of Euler, so it never overshoots or explodes, even on a long frame.
static void criticalSpring(thread float2 &pos, thread float2 &vel, float2 target, float omega, float dt) {
    float2 x0 = pos - target;
    float2 j1 = vel + omega * x0;
    float e = exp(-omega * dt);
    pos = target + (x0 + j1 * dt) * e;
    vel = (vel - omega * j1 * dt) * e;
}

/// Analytic modes store the frame-to-frame motion as velocity, so it is valid for consumers
/// (and flips sign automatically when progress runs backwards).
static void moveTo(thread Particle &p, float2 position, float dt) {
    p.velocity = (position - p.currentPosition) / max(dt, 1e-4);
    p.currentPosition = position;
}

// MARK: - Module 1: paywall success morph

static void paywallStep(thread Particle &p, constant ParticleUniforms &u, uint id) {
    float dt = u.deltaTime;
    float t = u.progress;
    if (t <= 0.0) {
        p.currentPosition = p.startPosition;
        p.velocity = 0.0;
        return;
    }
    float2 center = u.bounds.xy + u.bounds.zw * 0.5;
    float2 rel = p.currentPosition - center;
    float dist = max(length(rel), 1e-3);
    float2 outward = rel / dist;
    float2 tangent = float2(-outward.y, outward.x);
    float2 swirl = curlNoise(p.currentPosition * 0.011, u.time * 0.5) * u.noiseStrength;

    if (t < 0.4) {
        // 0…0.4: a sharp outward blast that dies out within the first few hundredths,
        // then the vortex (tangential pull + curl noise) carries the cloud around.
        float burst = exp(-t * 30.0) * mix(4000.0, 9000.0, hash11(id * 3U + 1U));
        p.velocity += (outward * burst + tangent * 240.0 + swirl) * dt;
        p.velocity *= exp(-1.6 * dt);
        p.currentPosition += p.velocity * dt;
    } else {
        // 0.4…1: critically damped spring towards the checkmark. Stiffness ramps up per particle,
        // so the vortex lets go of the cloud gradually instead of all at once.
        float capture = saturate((t - 0.4 - p.seed * 0.15) / 0.45);
        p.velocity += swirl * (1.0 - capture) * dt;
        float omega = mix(2.0, 16.0, capture);
        criticalSpring(p.currentPosition, p.velocity, p.targetPosition, omega, dt);
    }
    // The button's colors give way to the success color during the flight.
    float tint = smoothstep(0.3, 0.8, t);
    p.color = mix(p.color, u.colorB, 1.0 - exp(-5.0 * dt * tint));
}

// MARK: - Module 2: tab bar icon morph

static void tabBarStep(thread Particle &p, constant ParticleUniforms &u, uint id) {
    float t = smootherstep01(stagger(u.progress, p.seed, 0.35));
    float2 a = p.startPosition;
    float2 b = p.targetPosition;
    // The control point is thrown up (or down) by ~30 pt with per-particle variance: a gravity toss.
    float2 control = (a + b) * 0.5 + float2(0.0, u.arcHeight * mix(0.6, 1.4, hash11(id)));
    float s = 1.0 - t;
    float2 position = s * s * a + 2.0 * s * t * control + t * t * b;
    // Sparks flutter only mid-flight (sin(πt) is 0 at both ends, so the icons stay crisp).
    float flight = sin(M_PI_F * t);
    position += curlNoise(a * 0.05 + p.seed, u.time * 1.5) * u.noiseStrength * flight;
    moveTo(p, position, u.deltaTime);

    float4 color = mix(u.colorA, u.colorB, t);
    color.a = 1.0 + 2.5 * flight * hash11(id * 7U + 3U);   // sparkle
    p.color = color;
}

// MARK: - Module 3: AI voice sphere ↔ text

static void voiceStep(thread Particle &p, constant ParticleUniforms &u, uint id) {
    // Fibonacci sphere: evenly spread directions from the particle index alone.
    float n = float(max(u.particleCount, 1U));
    float i = float(id) + 0.5;
    float phi = acos(1.0 - 2.0 * i / n);
    float theta = M_PI_F * (1.0 + sqrt(5.0)) * i;
    float3 dir = float3(cos(theta) * sin(phi), cos(phi), sin(theta) * sin(phi));
    // A little jitter breaks the lattice's spiral rows, which otherwise show up as moiré lines.
    float3 jitter = float3(hash11(id * 3U + 1U), hash11(id * 3U + 2U), hash11(id * 3U + 3U)) - 0.5;
    dir = normalize(dir + jitter * 0.05);

    // Slow spin around Y, fixed tilt around X.
    float spin = u.time * 0.35;
    dir = float3(dir.x * cos(spin) + dir.z * sin(spin), dir.y, -dir.x * sin(spin) + dir.z * cos(spin));
    const float tilt = 0.35;
    dir = float3(dir.x, dir.y * cos(tilt) - dir.z * sin(tilt), dir.y * sin(tilt) + dir.z * cos(tilt));

    // Oscillation amplitude follows the voice: regional bulges (noise) + per-particle sine shimmer.
    float radius = u.bounds.z * 0.5;
    float bulge = snoise(dir * 2.2 + float3(0.0, 0.0, u.time * 1.3));
    float shimmer = sin(u.time * 9.0 + p.seed * 2.0 * M_PI_F);
    float r = radius * (1.0 + 0.03 * sin(u.time * 1.7) + u.audioVolume * (0.3 * bulge + 0.08 * shimmer));
    float3 q = dir * r;
    float perspective = 1.0 / (1.0 - q.z / (radius * 5.0));
    float2 center = u.bounds.xy + u.bounds.zw * 0.5;
    float2 sphere = center + float2(q.x, -q.y) * perspective;
    float depth = saturate(dir.z * 0.5 + 0.5);   // 0 = back, 1 = front

    // Text: within the 0.3 s ramp of progress the oscillation is blended out completely.
    float t = smootherstep01(stagger(u.progress, p.seed, 0.3));
    float2 letter = p.targetPosition + curlNoise(p.targetPosition * 0.04, u.time * 0.6) * 0.35;
    moveTo(p, mix(sphere, letter, t), u.deltaTime);

    float4 sphereColor = mix(u.colorA, u.colorB, depth);
    sphereColor.a = 0.25 + 0.75 * depth * depth + u.audioVolume * 0.4;
    float4 textColor = float4(mix(u.colorB.rgb, float3(1.0), 0.35), 1.0);
    p.color = mix(sphereColor, textColor, t);
}

// MARK: - Module 4: Thanos snap (reversible)

static void thanosStep(thread Particle &p, constant ParticleUniforms &u, uint id) {
    // The front sweeps left → right over the first ~60% of progress, with a ragged noisy edge.
    float edge = (p.startPosition.x - u.bounds.x) / max(u.bounds.z, 1.0);
    float ragged = (snoise(float3(p.startPosition * 0.035, 0.0)) * 0.5 + 0.5) * 0.12 + p.seed * 0.04;
    float release = (edge + ragged) * 0.55;
    // Seconds since the front released this particle. Position is a closed-form function of it,
    // so running progress back to 0 retraces the exact same path and the velocity inverts.
    float age = max(u.progress - release, 0.0) * 2.2;

    float wind = mix(60.0, 220.0, hash11(id * 5U + 11U));                       // V_x > 0
    float2 offset;
    offset.x = wind * age + 90.0 * age * age;
    offset.y = 70.0 * age * snoise(float3(p.startPosition * 0.02, age * 0.7 + p.seed * 3.0))   // V_y = noise(x, y, t)
             - 25.0 * age * age;                                                // dust rises a little
    moveTo(p, p.startPosition + offset, u.deltaTime);
    p.color.a = 1.0 - smoothstep(0.15, 1.1, age * mix(0.7, 1.3, p.seed));
}

// MARK: - Module 5: magnetic 3D badge

static void badgeStep(thread Particle &p, constant ParticleUniforms &u) {
    float dt = u.deltaTime;
    float2 center = u.bounds.xy + u.bounds.zw * 0.5;

    // Rest pose in 3D: depth layers by seed, an idle sway, and a tilt towards the finger.
    float2 tilt = float2(sin(u.time * 0.7) * 0.22, sin(u.time * 0.53) * 0.16);
    if (u.touchActive > 0.0) {
        float2 lean = clamp((u.touchPos - center) / max(u.bounds.zw * 0.5, 1.0), -1.0, 1.0);
        tilt += float2(lean.x, -lean.y) * 0.2;
    }
    float3 v = float3(p.startPosition - center, (p.seed - 0.5) * 40.0);
    v = float3(v.x * cos(tilt.x) + v.z * sin(tilt.x), v.y, -v.x * sin(tilt.x) + v.z * cos(tilt.x));
    v = float3(v.x, v.y * cos(tilt.y) - v.z * sin(tilt.y), v.y * sin(tilt.y) + v.z * cos(tilt.y));
    float perspective = 600.0 / (600.0 - v.z);
    float2 home = center + v.xy * perspective;

    // Repulsion: F = (pos − touch) / d · (1 − d / R) · power inside the finger's radius.
    if (u.touchActive > 0.0) {
        float2 away = p.currentPosition - u.touchPos;
        float d = length(away);
        if (d < u.touchRadius && d > 1e-3) {
            p.velocity += away / d * (1.0 - d / u.touchRadius) * u.touchPower * dt;
        }
    }
    // Spring back with inertia; 0.85 is the per-frame damping at 120 Hz, made frame-rate independent.
    p.velocity += (home - p.currentPosition) * 260.0 * dt;
    p.velocity *= pow(0.85, dt * 120.0);
    p.currentPosition += p.velocity * dt;

    float speed = length(p.velocity);
    p.color.a = 0.75 + 0.25 * saturate(v.z / 40.0 + 0.5) + min(speed / 600.0, 1.0);   // flung particles flare
}

// MARK: - Module 6: morphing progress loader

static void loaderStep(thread Particle &p, constant ParticleUniforms &u, const device float2 *keyframes, uint id) {
    uint n = u.particleCount;
    float progress = saturate(u.progress);
    float2 a, b;
    float t;
    if (progress < 0.5) {            // Lerp(Buffer_0, Buffer_50, P × 2)
        a = keyframes[id];
        b = keyframes[n + id];
        t = progress * 2.0;
    } else {                         // Lerp(Buffer_50, Buffer_100, (P − 0.5) × 2)
        a = keyframes[n + id];
        b = keyframes[2U * n + id];
        t = (progress - 0.5) * 2.0;
    }
    // Eased and staggered so each number holds its shape for a while before dissolving.
    t = smootherstep01(saturate((t - 0.15 - p.seed * 0.2) / 0.6));
    float2 morph = mix(a, b, t) + curlNoise(a * 0.02, u.time * 0.7) * u.noiseStrength * sin(M_PI_F * t);

    // Final stage: everything collapses into the solid card rectangle.
    float s = smootherstep01(stagger(u.stage, p.seed, 0.3));
    float2 card = keyframes[3U * n + id];
    float2 target = mix(morph, card, s);

    // Follow smoothly, so jumps in the reported progress never teleport particles.
    float2 position = mix(p.currentPosition, target, 1.0 - exp(-18.0 * u.deltaTime));
    moveTo(p, position, u.deltaTime);

    p.color = mix(u.colorA, u.colorB, s);
    p.color.a *= 1.0 + 0.8 * sin(M_PI_F * t);
}

// MARK: - Kernels

kernel void particleComputeKernel(device Particle *particles [[buffer(ParticleBufferIndexParticles)]],
                                  constant ParticleUniforms &u [[buffer(ParticleBufferIndexUniforms)]],
                                  const device float2 *keyframes [[buffer(ParticleBufferIndexKeyframes)]],
                                  uint id [[thread_position_in_grid]]) {
    if (id >= u.particleCount) {
        return;
    }
    Particle p = particles[id];
    switch (u.mode) {
        case ParticleModePaywall: paywallStep(p, u, id); break;
        case ParticleModeTabBar:  tabBarStep(p, u, id); break;
        case ParticleModeVoice:   voiceStep(p, u, id); break;
        case ParticleModeThanos:  thanosStep(p, u, id); break;
        case ParticleModeBadge:   badgeStep(p, u); break;
        case ParticleModeLoader:  loaderStep(p, u, keyframes, id); break;
        default: break;
    }
    particles[id] = p;
}

/// Swaps in new targets / colors while particles keep flying from wherever they are now.
kernel void particleRetargetKernel(device Particle *particles [[buffer(0)]],
                                   const device float2 *targets [[buffer(1)]],
                                   const device float4 *colors [[buffer(2)]],
                                   constant ParticleRetarget &r [[buffer(3)]],
                                   uint id [[thread_position_in_grid]]) {
    if (id >= r.count) {
        return;
    }
    Particle p = particles[id];
    if (r.flags & ParticleRetargetCommitStart) {
        p.startPosition = p.currentPosition;
    }
    if (r.flags & ParticleRetargetTargets) {
        p.targetPosition = targets[id];
    }
    if (r.flags & ParticleRetargetColors) {
        p.color = colors[id];
    }
    if (r.flags & ParticleRetargetStopVelocity) {
        p.velocity = 0.0;
    }
    particles[id] = p;
}
