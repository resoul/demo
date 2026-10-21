//
//  EmojiPhysics.metal
//  demo
//
//  Emoji fountain simulation, one thread per particle: spawning at the emitter, gravity,
//  repulsion from the finger, spin, floor and wall bounces, and counting visible particles.
//

#include "EmojiShared.h"

// PCG hash (Jarzynski & Olano, "Hash Functions for GPU Rendering").
static uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

static float random01(thread uint &state) {
    state = pcgHash(state);
    return float(state) * (1.0 / 4294967296.0);
}

kernel void emoji_init(device EmojiParticle *particles [[buffer(0)]],
                       constant EmojiUniforms &u [[buffer(1)]],
                       uint id [[thread_position_in_grid]]) {
    if (id >= u.count) return;
    uint rng = pcgHash(id + 1u);
    EmojiParticle p;
    p.position = float2(-10000.0);
    p.velocity = float2(0.0);
    p.angle = 0.0;
    p.spin = 0.0;
    p.life = random01(rng) * 3.0;     // staggered first spawn, so the fountain starts smoothly
    p.lifetime = 0.0;
    p.size = 0.0;
    p.emoji = 0;
    p.seed = rng;
    p.padding = 0.0;
    particles[id] = p;
}

kernel void emoji_update(device EmojiParticle *particles [[buffer(0)]],
                         constant EmojiUniforms &u [[buffer(1)]],
                         device atomic_uint *visibleCount [[buffer(2)]],
                         uint id [[thread_position_in_grid]]) {
    if (id >= u.count) return;
    EmojiParticle p = particles[id];
    float dt = u.deltaTime;
    p.life -= dt;

    if (p.life <= 0.0) {
        // (Re)spawn at the emitter with an upward kick inside a cone.
        uint rng = pcgHash(p.seed ^ pcgHash(u.frame + id * 7919u));
        float angle = -M_PI_F * 0.5 + (random01(rng) - 0.5) * 0.4;
        float height = u.resolution.y * (0.35 + 0.45 * random01(rng));
        float speed = sqrt(2.0 * u.gravity * height);
        p.position = u.emitter + (float2(random01(rng), random01(rng)) - 0.5) * u.baseSize * 0.5;
        p.velocity = float2(cos(angle), sin(angle)) * speed;
        p.angle = random01(rng) * 2.0 * M_PI_F;
        p.spin = (random01(rng) - 0.5) * 8.0;
        p.lifetime = 2.5 + random01(rng) * 1.5;
        p.life = p.lifetime;
        p.size = u.baseSize * (0.6 + 0.8 * random01(rng));
        p.emoji = u.emojiFirst + min(uint(random01(rng) * float(u.emojiCount)), u.emojiCount - 1);
        p.seed = rng;
    } else if (p.lifetime > 0.0) {
        float2 force = float2(0.0, u.gravity);

        // While touching, the finger pushes nearby emoji away.
        float2 away = p.position - u.touch;
        float distance = length(away) + 1.0;
        float radius = min(u.resolution.x, u.resolution.y) * 0.3;
        float push = u.touchStrength * saturate(1.0 - distance / radius);
        force += away / distance * push * push * u.gravity * 6.0;

        p.velocity += force * dt;
        p.velocity *= exp(-dt * 0.3);
        p.position += p.velocity * dt;
        p.angle += p.spin * dt;

        // Bounce off the floor and the side walls.
        float halfSize = p.size * 0.5;
        if (p.position.y > u.resolution.y - halfSize && p.velocity.y > 0.0) {
            p.position.y = u.resolution.y - halfSize;
            p.velocity.y *= -0.45;
            p.velocity.x *= 0.8;
            p.spin *= 0.7;
            // Landed emoji fade out soon instead of carpeting the floor.
            p.life = min(p.life, 0.6);
        }
        if ((p.position.x < halfSize && p.velocity.x < 0.0) ||
            (p.position.x > u.resolution.x - halfSize && p.velocity.x > 0.0)) {
            p.velocity.x *= -0.6;
        }
    }
    particles[id] = p;

    // Count spawned particles inside the view: one atomic add per SIMD group, not per thread.
    float halfSize = p.size * 0.5;
    bool onScreen = p.lifetime > 0.0
        && all(p.position > -halfSize) && all(p.position < u.resolution + halfSize);
    uint groupVisible = simd_sum(onScreen ? 1u : 0u);
    if (simd_is_first()) {
        atomic_fetch_add_explicit(visibleCount, groupVisible, memory_order_relaxed);
    }
}
