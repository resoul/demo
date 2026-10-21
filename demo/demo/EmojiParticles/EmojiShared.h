//
//  EmojiShared.h
//  demo
//
//  Types shared by EmojiPhysics.metal and EmojiRender.metal.
//

#pragma once

#include <metal_stdlib>
using namespace metal;

// 48 bytes; `MetalEmojiParticlesView.particleStride` must match.
struct EmojiParticle {
    float2 position;    // pixels
    float2 velocity;    // pixels per second
    float angle;        // radians
    float spin;         // radians per second
    float life;         // seconds left; while lifetime == 0 this counts down to the first spawn
    float lifetime;     // total seconds; 0 = not spawned yet (invisible)
    float size;         // pixels
    uint emoji;         // atlas cell
    uint seed;          // per-particle random state
    float padding;
};

// Mirrored by `EmojiUniforms` in MetalEmojiParticlesView.swift (64 bytes).
struct EmojiUniforms {
    float2 resolution;
    float2 emitter;         // fountain origin, pixels
    float2 touch;           // finger, pixels
    float touchStrength;    // > 0 while touching: pushes nearby emoji away
    float time;
    float deltaTime;
    float gravity;          // pixels per second squared, downwards
    float baseSize;         // pixels
    uint count;             // particles to simulate and draw
    uint emojiFirst;        // atlas cells a new particle can pick from
    uint emojiCount;
    uint atlasColumns;
    uint frame;
};
