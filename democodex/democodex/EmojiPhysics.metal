#include "EmojiParticleTypes.h"

EmojiParticleState spawnEmoji(uint id, constant EmojiPhysicsUniforms &u, bool distributeAge) {
    uint seed = emoji::hash(id ^ (u.burstID * 747796405u) ^ uint(u.time * 1000));
    EmojiParticleState p;
    p.position = u.emitter + float2((emoji::random(seed + 1) - 0.5) * 0.015, 0);
    p.velocity = float2((emoji::random(seed + 2) - 0.5) * 0.9 / max(u.aspect, 0.1),
                         -0.7 - emoji::random(seed + 3) * 0.65);
    p.angle = emoji::random(seed + 4) * 2 * M_PI_F;
    p.angularVelocity = (emoji::random(seed + 5) - 0.5) * 9;
    p.lifetime = 1.3 + emoji::random(seed + 6) * 1.5;
    p.age = distributeAge ? emoji::random(seed + 7) * min(p.lifetime, 1.3) : 0.001;
    p.position += p.velocity * p.age + float2(0, 0.5 * u.gravity * p.age * p.age);
    p.velocity.y += u.gravity * p.age;
    p.emojiIndex = emoji::symbol(id, u.mode, u.atlasCount);
    p.burstID = u.burstID;
    p.size = 0.75 + emoji::random(seed + 8) * 0.5;
    p.padding = 0;
    return p;
}

kernel void initializeEmojiParticles(device EmojiParticleState *particles [[buffer(0)]],
                                      constant EmojiPhysicsUniforms &u [[buffer(1)]], uint id [[thread_position_in_grid]]) {
    if (id < u.count) particles[id] = spawnEmoji(id, u, true);
}

kernel void simulateEmojiParticles(device EmojiParticleState *particles [[buffer(0)]],
                                    constant EmojiPhysicsUniforms &u [[buffer(1)]],
                                    device atomic_uint &visibleCount [[buffer(2)]],
                                    uint id [[thread_position_in_grid]], uint tid [[thread_index_in_threadgroup]]) {
    // A fixed 256-thread reduction needs full groups, including the last group.
    threadgroup uint visible[256];
    uint onScreen = 0;
    if (id < u.count) {
        EmojiParticleState p = particles[id];
        bool newBurst = p.burstID != u.burstID && emoji::random(id ^ u.burstID) < 0.035;
        if (p.age >= p.lifetime || p.position.y > 1.06 || newBurst) p = spawnEmoji(id, u, false);
        p.burstID = u.burstID;
        float dt = clamp(u.deltaTime, 0.0, 1.0 / 30.0);
        float2 delta = (p.position - u.touch) * float2(u.aspect, 1);
        float2 repel = delta * (u.repulsion * u.interaction / (dot(delta, delta) + 0.006));
        p.velocity += float2(repel.x / max(u.aspect, 0.1), u.gravity + repel.y) * dt;
        p.velocity *= exp(-dt * 0.07);
        p.position += p.velocity * dt;
        if (p.position.x < 0.005 || p.position.x > 0.995) {
            p.position.x = clamp(p.position.x, 0.005, 0.995);
            p.velocity.x *= -0.65;
        }
        p.angle += p.angularVelocity * dt;
        p.age += dt;
        p.emojiIndex = emoji::symbol(id, u.mode, u.atlasCount);
        particles[id] = p;
        float extent = (abs(cos(p.angle)) + abs(sin(p.angle))) * u.spriteSize * p.size * 0.5;
        float2 halfSize = extent / max(u.viewportSize, float2(1));
        onScreen = p.age < p.lifetime && p.age > 0.01
                 && all(p.position + halfSize >= 0) && all(p.position - halfSize <= 1);
    }
    visible[tid] = onScreen;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint stride = 128; stride > 0; stride >>= 1) {
        if (tid < stride) visible[tid] += visible[tid + stride];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) atomic_fetch_add_explicit(&visibleCount, visible[0], memory_order_relaxed);
}
