#include "ExperimentTypes.h"
struct CityArguments { uint vertexCount; atomic_uint instanceCount; uint vertexStart, baseInstance; };
inline float3 cityCenter(uint id) { return float3((float(id%512)-256)*1.5f,0,(float(id/512)-256)*1.5f); }
inline float3 cityCamera(constant ExperimentUniforms &u) { return float3(sin(u.time*0.04f)*35,7,sin(u.time*0.015f)*70-40); }
inline float4 cityProject(float3 p,constant ExperimentUniforms &u) {
    float3 camera=cityCamera(u); float yaw=(u.touch.x-0.5f)*2.2f;
    float3 forward=safeUnit(float3(sin(yaw),-0.18f,cos(yaw))),right=safeUnit(cross(float3(0,1,0),forward)),up=cross(forward,right);
    float3 d=p-camera;float z=dot(d,forward);
    return float4(dot(d,right)*1.6f/max(u.aspect,0.6f),dot(d,up)*1.6f,z-0.15f,z);
}
kernel void cityReset(device CityArguments *a [[buffer(0)]],uint i [[thread_position_in_grid]]) {
    if(i)return;a[0].vertexCount=36;a[1].vertexCount=6;
    for(uint j=0;j<2;j++){atomic_store_explicit(&a[j].instanceCount,0,memory_order_relaxed);a[j].vertexStart=0;a[j].baseInstance=0;}
}
kernel void cityCull(device uint *ids [[buffer(0)]],device CityArguments *a [[buffer(1)]],constant ExperimentUniforms &u [[buffer(8)]],uint i [[thread_position_in_grid]]) {
    if(i>=u.count)return;
    // Spread every workload over the complete city, rather than filling rows behind the camera first.
    uint id=(i*40503u+731u)&262143u; // Odd multiplier gives unique IDs in a power-of-two domain.
    float3 p=cityCenter(id);float height=1+random01(id)*6; p.y=height*0.5f;
    float4 clip=cityProject(p,u);float radius=height*1.8f+2;
    bool visible=clip.w>0.1f && clip.w<130 && abs(clip.x)<clip.w+radius && abs(clip.y)<clip.w+radius;
    if(visible||(u.flags&1)) {uint level=distance(p,cityCamera(u))>30?1:0;uint slot=atomic_fetch_add_explicit(&a[level].instanceCount,1,memory_order_relaxed);ids[level*262144+slot]=id;}
}
struct CityRaster {float4 position [[position]];float3 color;float2 windows;float distance;};
vertex CityRaster cityVertex(device const uint *ids [[buffer(0)]],constant ExperimentUniforms &u [[buffer(8)]],constant uint &lod [[buffer(9)]],uint v [[vertex_id]],uint instance [[instance_id]]) {
    const uint corners[36]={0,2,1,1,2,3,4,5,6,5,7,6,0,1,4,1,5,4,2,6,3,3,6,7,0,4,2,2,4,6,1,3,5,3,7,5};
    uint id=ids[lod*262144+instance]; float height=1+random01(id)*6;
    uint corner=corners[v];float3 local=float3((corner&1)?0.55f:-0.55f,(corner&2)?height:0,(corner&4)?0.55f:-0.55f);
    if(lod) {const float2 quad[6]={float2(-1,0),float2(1,0),float2(-1,1),float2(1,0),float2(1,1),float2(-1,1)};local=float3(quad[v].x*0.55f,quad[v].y*height,0);}
    float3 world=cityCenter(id)+local;float3 color=mix(float3(0.03,0.12,0.25),float3(0.1,0.65,0.75),random01(id+11));
    return {cityProject(world,u),color,float2(local.x+local.z,local.y),distance(world,cityCamera(u))};
}
fragment float4 cityFragment(CityRaster in [[stage_in]]) {
    float windows=step(0.35f,fract(in.windows.x*4))*step(0.3f,fract(in.windows.y*3));
    float3 color=in.color*(0.45f+windows*1.0f)+windows*float3(0.15,0.22,0.08);
    return float4(mix(color,float3(0.02,0.04,0.09),1-exp(-in.distance*0.012f)),1);
}
