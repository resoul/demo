//
//  ParticleStructures.h
//  controller
//
//  Types shared by Swift (through controller-Bridging-Header.h) and MSL (#include), so the memory
//  layout of every struct is defined once and is identical on the CPU and the GPU.
//

#ifndef ParticleStructures_h
#define ParticleStructures_h

#include <simd/simd.h>

/// One particle. Positions are in points of the engine's view, top-left origin (UIKit space).
typedef struct {
    simd_float2 currentPosition;
    simd_float2 targetPosition;
    simd_float2 startPosition;
    simd_float2 velocity;
    simd_float4 color;            // straight (not premultiplied) sRGB; .a is brightness / opacity
    float size;                   // diameter in points
    float seed;                   // 0…1, per-particle randomness
} Particle;

/// Which scenario `particleComputeKernel` runs.
typedef enum ParticleMode {
    ParticleModePaywall = 0,      // button → explosion + vortex → checkmark
    ParticleModeTabBar  = 1,      // icon A → Bézier arc → icon B
    ParticleModeVoice   = 2,      // pulsing audio sphere ↔ text
    ParticleModeThanos  = 3,      // card → dust carried by the wind, reversible
    ParticleModeBadge   = 4,      // magnetic 3D badge repelled by the finger
    ParticleModeLoader  = 5,      // "0%" → "50%" → "100%" → content card
} ParticleMode;

typedef struct {
    // --- Fields from the spec ---
    float progress;               // 0…1
    float time;                   // seconds
    simd_float2 touchPos;         // points
    float touchRadius;            // points
    float noiseStrength;          // curl-noise strength (meaning depends on the mode)

    // --- Engine extensions ---
    float deltaTime;              // seconds since the previous frame
    unsigned int mode;            // ParticleMode
    simd_float2 viewSize;         // points
    simd_float4 bounds;           // x, y, width, height of the scenario's shape (button, card, sphere…)
    simd_float4 colorA;
    simd_float4 colorB;
    float scale;                  // pixels per point
    float touchActive;            // 1 while a finger is down
    float touchPower;             // repulsion at the finger, points / s²
    float audioVolume;            // 0…1
    float arcHeight;              // tab bar: signed control-point offset, points
    float stage;                  // loader: collapse into the final card, 0…1
    float pointScale;             // multiplies Particle.size
    float intensity;              // glow brightness
    unsigned int particleCount;
} ParticleUniforms;

/// What `particleRetargetKernel` changes without touching the particles' current motion.
typedef enum ParticleRetargetFlags {
    ParticleRetargetCommitStart  = 1 << 0,   // startPosition = currentPosition
    ParticleRetargetTargets      = 1 << 1,   // targetPosition = targets[i]
    ParticleRetargetColors       = 1 << 2,   // color = colors[i]
    ParticleRetargetStopVelocity = 1 << 3,   // velocity = 0
} ParticleRetargetFlags;

typedef struct {
    unsigned int count;
    unsigned int flags;
} ParticleRetarget;

typedef enum ParticleBufferIndex {
    ParticleBufferIndexParticles = 0,
    ParticleBufferIndexUniforms  = 1,
    ParticleBufferIndexKeyframes = 2,        // loader: Buffer_0, Buffer_50, Buffer_100, card (N points each)
} ParticleBufferIndex;

#endif /* ParticleStructures_h */
