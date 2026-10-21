//
//  City.metal
//  demo
//
//  GPU-driven rendering of a city of buildings and trees. `city_cull` tests every instance against
//  the camera frustum, picks a level of detail by distance and appends it to one of four visible
//  lists (building/tree × LOD0/LOD1). `city_encode_draws` then writes four instanced draw commands
//  into an indirect command buffer with the instance counts the culling produced — the CPU never
//  learns what is visible.
//

#include "../../Effects/Core/ShaderCommon.h"

struct CityInstance {
    float4 placement;   // x, z, width, height (metres)
    float4 style;       // rgb tint, kind (0 building, 1 tree)
};

// Mirrored by `CityParams` in CityView.swift (240 bytes).
struct CityParams {
    float4x4 viewProjection;
    float4 planes[6];
    float4 cameraPosition;
    float4 sunDirection;
    float4 fogColor;        // rgb, w = density
    uint instanceCount;
    uint listCapacity;
    float lodDistance;
    float farDistance;
    float time;
    float padding0;
    float padding1;
    float padding2;
};

struct DrawRange {
    uint indexStart;
    uint indexCount;
    uint baseVertex;
    uint padding;
};

struct ICBContainer {
    command_buffer commands [[id(0)]];
};

kernel void city_cull(device const CityInstance *instances [[buffer(0)]],
                      constant CityParams &p [[buffer(1)]],
                      device atomic_uint *listCounts [[buffer(2)]],
                      device uint *visible [[buffer(3)]],
                      uint id [[thread_position_in_grid]]) {
    if (id >= p.instanceCount) return;
    CityInstance instance = instances[id];
    float width = instance.placement.z, height = instance.placement.w;
    float3 center = float3(instance.placement.x, height * 0.5, instance.placement.y);
    float radius = length(float3(width, height, width)) * 0.5;
    for (int i = 0; i < 6; i++) {
        if (dot(p.planes[i].xyz, center) + p.planes[i].w < -radius) return;
    }
    float distance = length(center - p.cameraPosition.xyz);
    if (distance > p.farDistance) return;

    uint list = uint(instance.style.w) * 2 + (distance < p.lodDistance ? 0 : 1);
    uint slot = atomic_fetch_add_explicit(&listCounts[list], 1u, memory_order_relaxed);
    visible[list * p.listCapacity + slot] = id;
}

kernel void city_encode_draws(device ICBContainer &icb [[buffer(0)]],
                              device const uint *listCounts [[buffer(1)]],
                              constant DrawRange *ranges [[buffer(2)]],
                              device const ushort *indices [[buffer(3)]],
                              constant CityParams &p [[buffer(4)]],
                              uint id [[thread_position_in_grid]]) {
    if (id >= 4) return;
    render_command command(icb.commands, id);
    uint count = listCounts[id];
    if (count == 0) {
        command.reset();
        return;
    }
    command.draw_indexed_primitives(primitive_type::triangle,
                                    ranges[id].indexCount,
                                    indices + ranges[id].indexStart,
                                    count,
                                    ranges[id].baseVertex,
                                    id * p.listCapacity);
}

// Layout of MTLDrawIndexedPrimitivesIndirectArguments.
struct IndexedIndirectArguments {
    uint indexCount;
    uint instanceCount;
    uint indexStart;
    int baseVertex;
    uint baseInstance;
};

// Fallback where indirect command buffers are unavailable (the Simulator): the GPU still decides
// what is drawn, by writing the arguments of four indirect draws.
kernel void city_write_indirect_arguments(device IndexedIndirectArguments *arguments [[buffer(0)]],
                                          device const uint *listCounts [[buffer(1)]],
                                          constant DrawRange *ranges [[buffer(2)]],
                                          constant CityParams &p [[buffer(4)]],
                                          uint id [[thread_position_in_grid]]) {
    if (id >= 4) return;
    arguments[id].indexCount = ranges[id].indexCount;
    arguments[id].instanceCount = listCounts[id];
    arguments[id].indexStart = ranges[id].indexStart;
    arguments[id].baseVertex = int(ranges[id].baseVertex);
    arguments[id].baseInstance = id * p.listCapacity;
}

// MARK: - Rendering

struct MeshVertex {
    float4 position;
    float4 normal;
};

struct CityVertexOut {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float3 tint;
    uint kind [[flat]];
    uint instance [[flat]];
};

// `instance_id` includes the draw's base instance, which selects the visible list.
vertex CityVertexOut city_vertex(device const MeshVertex *vertices [[buffer(0)]],
                                 device const CityInstance *instances [[buffer(1)]],
                                 device const uint *visible [[buffer(2)]],
                                 constant CityParams &p [[buffer(3)]],
                                 uint vid [[vertex_id]],
                                 uint iid [[instance_id]]) {
    uint index = visible[iid];
    CityInstance instance = instances[index];
    MeshVertex v = vertices[vid];
    float3 scale = float3(instance.placement.z, instance.placement.w, instance.placement.z);
    float3 world = v.position.xyz * scale + float3(instance.placement.x, 0.0, instance.placement.y);

    CityVertexOut out;
    out.position = p.viewProjection * float4(world, 1.0);
    out.world = world;
    out.normal = v.normal.xyz;
    out.tint = instance.style.rgb;
    out.kind = uint(instance.style.w);
    out.instance = index;
    return out;
}

static float3 applyFog(float3 color, float3 world, constant CityParams &p) {
    float distance = length(world - p.cameraPosition.xyz);
    return mix(color, p.fogColor.rgb, 1.0 - exp(-distance * p.fogColor.w));
}

fragment float4 city_fragment(CityVertexOut in [[stage_in]],
                              constant CityParams &p [[buffer(0)]]) {
    float3 n = normalize(in.normal);
    float diffuse = saturate(dot(n, normalize(p.sunDirection.xyz)));
    float3 albedo = in.tint;
    float3 emissive = float3(0.0);

    if (in.kind == 0) {
        if (abs(n.y) < 0.5) {
            // Facade windows, each lit at random.
            float2 facade = float2(abs(n.x) > 0.5 ? in.world.z : in.world.x, in.world.y);
            float2 size = float2(2.2, 3.2);
            float2 cell = floor(facade / size);
            float2 f = fract(facade / size);
            float window = step(0.2, f.x) * step(f.x, 0.8) * step(0.25, f.y) * step(f.y, 0.75);
            float lit = step(0.6, hash21(cell + float2(in.instance % 997, in.instance / 997)));
            albedo = mix(albedo, float3(0.06, 0.08, 0.11), window);
            emissive = window * lit * float3(1.0, 0.78, 0.45) * 0.9;
        } else {
            albedo *= 0.55;     // roofs
        }
    } else {
        albedo *= 0.8 + 0.2 * n.y;
    }

    float3 color = albedo * (0.2 + 0.8 * diffuse) + emissive;
    return float4(applyFog(color, in.world, p), 1.0);
}

vertex CityVertexOut city_ground_vertex(device const MeshVertex *vertices [[buffer(0)]],
                                        constant CityParams &p [[buffer(1)]],
                                        constant float4 &transform [[buffer(2)]],
                                        uint vid [[vertex_id]]) {
    CityVertexOut out;
    float3 world = vertices[vid].position.xyz * transform.w + transform.xyz;
    out.position = p.viewProjection * float4(world, 1.0);
    out.world = world;
    out.normal = float3(0.0, 1.0, 0.0);
    out.tint = float3(0.0);
    out.kind = 2;
    out.instance = 0;
    return out;
}

// Asphalt with a road grid every 8 lots and dashed centre lines.
fragment float4 city_ground_fragment(CityVertexOut in [[stage_in]],
                                     constant CityParams &p [[buffer(0)]]) {
    const float lot = 7.0;
    float2 block = in.world.xz / (lot * 8.0);
    float2 road = abs(fract(block) - 0.5) * lot * 8.0;      // metres from the road centre line
    float onRoad = 1.0 - smoothstep(2.8, 3.2, min(road.x, road.y));
    float3 color = mix(float3(0.10, 0.11, 0.10), float3(0.05, 0.05, 0.06), onRoad);
    float dash = step(0.5, fract((road.x < road.y ? in.world.z : in.world.x) / 4.0));
    float line = (1.0 - smoothstep(0.08, 0.15, min(road.x, road.y))) * dash;
    color += line * float3(0.5, 0.45, 0.25);
    return float4(applyFog(color, in.world, p), 1.0);
}
