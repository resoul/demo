#ifndef EmojiParticleTypes_h
#define EmojiParticleTypes_h
#include <metal_stdlib>
using namespace metal;

struct EmojiParticleState {
    float2 position;
    float2 velocity;
    float angle;
    float angularVelocity;
    float age;
    float lifetime;
    uint emojiIndex;
    uint burstID;
    float size;
    float padding;
}; // 48 bytes

struct EmojiPhysicsUniforms {
    float2 emitter;
    float2 touch;
    float deltaTime;
    float time;
    float aspect;
    float interaction;
    uint count;
    uint mode;
    uint burstID;
    uint atlasCount;
    float2 viewportSize;
    float gravity;
    float repulsion;
    float spriteSize;
    float padding0;
    float padding1;
    float padding2;
}; // 80 bytes

struct EmojiRenderUniforms {
    float2 resolution;
    float spriteSize;
    uint atlasCount;
    uint count;
    uint padding0;
    uint padding1;
    uint padding2;
}; // 32 bytes

namespace emoji {
inline uint hash(uint x) {
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    return x ^ (x >> 16);
}
inline float random(uint x) { return float(hash(x) & 0x00ffffffu) / 16777216.0; }
inline uint symbol(uint id, uint mode, uint count) {
    if (mode == 0) return 0; // fire
    if (mode == 1) return min(2u, count - 1); // rocket
    if (mode == 2) return min(1u, count - 1); // heart
    return hash(id) % max(count, 1u);
}
}
#endif
