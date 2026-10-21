#include "ExperimentTypes.h"
inline uint cellID(float2 p, uint side) { uint2 c = uint2(clamp(p * float(side), 0.0f, float(side - 1))); return c.y * side + c.x; }
kernel void neighborSeed(device GPUNode *nodes [[buffer(0)]], constant ExperimentUniforms &u [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i >= u.count) return;
    bool flock = u.flags & 4;
    uint columns = uint(ceil(sqrt(float(u.count) * 0.5f)));
    float2 p = flock ? float2(random01(i*3+1), random01(i*3+2)) : float2(0.06f + 0.4f * float(i % columns) / float(columns), 0.08f + 0.8f * float(i / columns) / ceil(float(u.count) / float(columns)));
    float angle = random01(i+75)*6.2831853f;
    nodes[i] = {float4(p,0,1), float4(flock ? float2(cos(angle),sin(angle))*0.12f : float2(0),0,0)};
}
kernel void gridClear(device atomic_uint *counts [[buffer(0)]], device atomic_uint *cursor [[buffer(1)]], constant ExperimentUniforms &u [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i >= u.side*u.side) return;
    atomic_store_explicit(counts+i,0,memory_order_relaxed); atomic_store_explicit(cursor+i,0,memory_order_relaxed);
}
kernel void gridHistogram(device const GPUNode *nodes [[buffer(0)]], device atomic_uint *counts [[buffer(1)]], constant ExperimentUniforms &u [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i < u.count) atomic_fetch_add_explicit(counts+cellID(nodes[i].position.xy,u.side),1,memory_order_relaxed);
}
kernel void gridScan(device const uint *source [[buffer(0)]], device uint *target [[buffer(1)]], constant ExperimentUniforms &u [[buffer(8)]], constant uint &stride [[buffer(9)]], uint i [[thread_position_in_grid]]) {
    if(i < u.side*u.side) target[i] = source[i] + ((stride && i >= stride) ? source[i-stride] : 0);
}
kernel void gridScatter(device const GPUNode *nodes [[buffer(0)]], device const uint *counts [[buffer(1)]], device const uint *prefix [[buffer(2)]], device atomic_uint *cursor [[buffer(3)]], device uint *sorted [[buffer(4)]], constant ExperimentUniforms &u [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i >= u.count) return;
    uint cell = cellID(nodes[i].position.xy,u.side);
    uint slot = prefix[cell]-counts[cell]+atomic_fetch_add_explicit(cursor+cell,1,memory_order_relaxed);
    sorted[slot] = i;
}
kernel void sphDensity(device const GPUNode *nodes [[buffer(0)]], device const uint *counts [[buffer(1)]], device const uint *prefix [[buffer(2)]], device const uint *sorted [[buffer(3)]], device float2 *density [[buffer(4)]], constant ExperimentUniforms &u [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i >= u.count) return;
    float2 p = nodes[i].position.xy; int2 cell = int2(p*float(u.side));
    float h = 1.0f/float(u.side), rho = 0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        int2 c = cell+int2(x,y); if(any(c<0)||any(c>=int(u.side))) continue;
        uint key=c.y*u.side+c.x;
        for(uint j=prefix[key]-counts[key];j<prefix[key];j++) { float w=max(0.0f,1.0f-distance(p,nodes[sorted[j]].position.xy)/h); rho+=w*w*w; }
    }
    float rest = max(1.2f, float(u.count)/0.32f * 3.14159f*h*h/10.0f);
    density[i]=float2(max(rho,1.0f), max(rho-rest,0.0f)*4.0f);
}
kernel void sphIntegrate(device const GPUNode *nodes [[buffer(0)]], device const uint *counts [[buffer(1)]], device const uint *prefix [[buffer(2)]], device const uint *sorted [[buffer(3)]], device const float2 *density [[buffer(4)]], device GPUNode *output [[buffer(5)]], constant ExperimentUniforms &u [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i>=u.count) return;
    GPUNode node=nodes[i]; float2 p=node.position.xy,v=node.velocity.xy;
    int2 cell=int2(p*float(u.side)); float h=1.0f/u.side; float2 force=u.gravity*0.42f;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        int2 c=cell+int2(x,y); if(any(c<0)||any(c>=int(u.side))) continue;
        uint key=c.y*u.side+c.x;
        for(uint j=prefix[key]-counts[key];j<prefix[key];j++) {
            uint k=sorted[j]; if(k==i) continue;
            float2 d=p-nodes[k].position.xy; float r=length(d); if(r>=h || r<1e-6f) continue;
            float w=1.0f-r/h;
            force += d/r * (density[i].y+density[k].y) / (density[i].x*density[k].x) * w*w * 5.0f;
            force += (nodes[k].velocity.xy-v) * w * 0.8f / density[k].x;
        }
    }
    if(u.flags&2) { float2 d=p-u.touch; force += safeUnit(d)*exp(-dot(d,d)*180.0f)*4.0f; }
    v=(v+clamp(force,-30.0f,30.0f)*u.dt)*0.998f; v=clamp(v,-1.8f,1.8f); float2 next=p+v*u.dt;
    if(!(u.flags&1) && next.y<0.66f && abs(next.x-0.53f)<0.015f) { next.x=p.x<0.53f?0.514f:0.546f; v.x*=-0.4f; }
    for(uint a=0;a<2;a++) { if(next[a]<0.025f){next[a]=0.025f;v[a]=abs(v[a])*0.4f;} if(next[a]>0.975f){next[a]=0.975f;v[a]=-abs(v[a])*0.4f;} }
    output[i]={float4(next,0,1),float4(v,density[i].x,0)};
}
kernel void boidsIntegrate(device const GPUNode *nodes [[buffer(0)]], device const uint *counts [[buffer(1)]], device const uint *prefix [[buffer(2)]], device const uint *sorted [[buffer(3)]], device const float2 *unused [[buffer(4)]], device GPUNode *output [[buffer(5)]], constant ExperimentUniforms &u [[buffer(8)]], uint i [[thread_position_in_grid]]) {
    if(i>=u.count) return;
    float2 p=nodes[i].position.xy,v=nodes[i].velocity.xy,align=0,center=0,separate=0; float neighbors=0;
    int2 cell=int2(p*float(u.side));
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        int2 c=(cell+int2(x,y)+int(u.side))%int(u.side); uint key=c.y*u.side+c.x;
        for(uint j=prefix[key]-counts[key];j<prefix[key];j++) {
            uint k=sorted[j]; if(k==i) continue;
            float2 d=nodes[k].position.xy-p; d-=round(d); float r2=dot(d,d);
            if(r2>0.001f) continue;
            align+=nodes[k].velocity.xy; center+=d; separate-=d/max(r2,1e-5f); neighbors++;
        }
    }
    float2 force=0;
    if(neighbors>0) force=(align/neighbors-v)*3.0f+center/neighbors*6.0f+separate/neighbors*0.018f;
    if(u.flags&2) { float2 d=u.touch-p; force+=safeUnit(d)*exp(-dot(d,d)*18.0f)*((u.flags&1)?-2.0f:1.0f); }
    v+=force*u.dt; float speed=clamp(length(v),0.07f,0.24f); v=safeUnit(v+float2(1e-5f,0))*speed;
    output[i]={float4(fract(p+v*u.dt+1.0f),0,1),float4(v,neighbors,0)};
}
struct NeighborRaster { float4 position [[position]]; float2 uv; float speed; uint flock [[flat]]; float2 world; };
vertex NeighborRaster neighborVertex(device const GPUNode *nodes [[buffer(0)]], constant ExperimentUniforms &u [[buffer(8)]], uint vertexID [[vertex_id]], uint instance [[instance_id]]) {
    const float2 corners[6]={float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,-1),float2(1,1),float2(-1,1)};
    if(instance==u.count) { float2 q=corners[vertexID];float2 p=float2(0.53f+q.x*0.015f,(q.y+1)*0.33f);return {float4(p*2-1,0,1),q,0,2,p}; }
    GPUNode n=nodes[instance]; float2 q=corners[vertexID]; bool flock=u.flags&4;
    float radius=flock?0.0045f:max(0.0015f,0.38f/sqrt(float(u.count)));
    float2 delta=q*float2(radius,radius*u.aspect);
    if(flock) { float a=atan2(n.velocity.y,n.velocity.x); delta=float2(cos(a)*delta.x-sin(a)*delta.y,sin(a)*delta.x+cos(a)*delta.y)*float2(1.7f,1); }
    return {float4((n.position.xy+delta)*2-1,0,1),q,length(n.velocity.xy),uint(flock),n.position.xy};
}
fragment float4 neighborFragment(NeighborRaster in [[stage_in]], constant ExperimentUniforms &u [[buffer(8)]]) {
    if(in.flock==2)return float4(0.25,0.38,0.47,1);
    float r=length(in.uv); if(r>1) discard_fragment();
    float3 color=in.flock?mix(float3(0.04,0.65,0.5),float3(0.7,1,0.18),clamp(in.speed*3,0.0f,1.0f)):mix(float3(0.01,0.23,0.6),float3(0.3,0.95,1),clamp(in.speed*1.5f+in.world.y*0.3f,0.0f,1.0f));
    return float4(color+(1-r)*0.15f,smoothstep(1.0f,0.7f,r));
}
