#include "ExperimentTypes.h"
kernel void nbodySeed(device GPUNode *nodes [[buffer(0)]],constant ExperimentUniforms &u [[buffer(8)]],uint i [[thread_position_in_grid]]) {
    if(i>=u.count)return;float radius=0.1f+0.85f*sqrt((float(i)+0.5f)/float(u.count)),angle=float(i)*2.3999632f;
    float2 p=float2(cos(angle),sin(angle))*radius;
    nodes[i]={float4(p,0,1.0f/float(u.count)),float4(-p.y*0.2f,p.x*0.2f,0,0)};
}
kernel void nbodyStep(device const GPUNode *source [[buffer(0)]],device GPUNode *target [[buffer(1)]],constant ExperimentUniforms &u [[buffer(8)]],uint i [[thread_position_in_grid]],uint local [[thread_index_in_threadgroup]],uint groupSize [[threads_per_threadgroup]]) {
    threadgroup float4 tile[256];float3 position=i<u.count?source[i].position.xyz:float3(0),acceleration=0;
    for(uint offset=0;offset<u.count;offset+=groupSize) {
        tile[local]=offset+local<u.count?source[offset+local].position:float4(0);
        threadgroup_barrier(mem_flags::mem_threadgroup);
        uint length=min(groupSize,u.count-offset);
        for(uint j=0;j<length;j++) {float3 d=tile[j].xyz-position;float inverse=rsqrt(dot(d,d)+0.002f);acceleration+=d*(inverse*inverse*inverse*tile[j].w);}
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if(i>=u.count)return;GPUNode n=source[i];n.velocity.xyz=(n.velocity.xyz+acceleration*u.dt)*0.999f;n.position.xyz+=n.velocity.xyz*u.dt;target[i]=n;
}
struct NBodyRaster {float4 position [[position]];float size [[point_size]];float3 color;};
vertex NBodyRaster nbodyVertex(device const GPUNode *nodes [[buffer(0)]],constant ExperimentUniforms &u [[buffer(8)]],constant uint &panel [[buffer(9)]],uint i [[vertex_id]]) {
    float2 p=nodes[i].position.xy;
    p/=1.0f+length(p); // Same bounded radial projection in both panels; physics is unchanged.
    float center=panel?0.5f:-0.5f;
    float2 clip=float2(center+p.x*0.43f,p.y*0.43f*u.aspect);
    float intensity=clamp(900.0f/float(u.count),0.05f,0.8f);
    return {float4(clip,0,1),2.0f,(panel?float3(0.1,0.8,1):float3(1,0.45,0.15))*intensity};
}
fragment float4 nbodyFragment(NBodyRaster in [[stage_in]],float2 uv [[point_coord]]) {if(distance(uv,float2(0.5))>0.5f)discard_fragment();return float4(in.color,1);}
