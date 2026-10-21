#include "ExperimentTypes.h"
constexpr sampler volumeSampler(coord::normalized, address::clamp_to_edge, filter::linear);
inline uint3 volumeCell(int3 p,uint n){return uint3(clamp(p,int3(0),int3(n-1)));}
kernel void volumeClear(texture3d<half,access::write> velocity [[texture(0)]],texture3d<half,access::write> dye [[texture(1)]],texture3d<half,access::write> pressure [[texture(2)]],constant ExperimentUniforms &u [[buffer(8)]],uint3 p [[thread_position_in_grid]]) {
    if(any(p>=u.side))return;velocity.write(half4(0),p);dye.write(half4(0),p);pressure.write(half4(0),p);
}
kernel void volumeAdvect(texture3d<half,access::sample> velocity [[texture(0)]],texture3d<half,access::sample> dye [[texture(1)]],texture3d<half,access::write> outVelocity [[texture(2)]],texture3d<half,access::write> outDye [[texture(3)]],constant ExperimentUniforms &u [[buffer(8)]],uint3 p [[thread_position_in_grid]]) {
    if(any(p>=u.side))return;float3 uv=(float3(p)+0.5f)/float(u.side);
    float3 previous=uv-float3(velocity.sample(volumeSampler,uv).xyz)*u.dt;
    float4 color=float4(dye.sample(volumeSampler,previous))*exp(-u.dt*0.35f);
    float3 v=float3(velocity.sample(volumeSampler,previous).xyz)*0.995f;
    float3 emitter=(u.flags&2)?float3(u.touch,0.5):float3(0.5,0.12,0.5);
    float3 d=uv-emitter;float injection=exp(-dot(d,d)*500)*u.dt*12;
    float3 tint=0.5f+0.5f*cos(u.time*0.5f+float3(0,2,4));
    color.rgb+=tint*injection;color.a+=injection;
    v.y+=(color.a*0.35f-0.02f)*u.dt;
    v+=float3(-d.z,0,d.x)*exp(-dot(d,d)*30)*u.dt*1.6f;
    for(uint a=0;a<3;a++)if(p[a]==0||p[a]==u.side-1)v[a]=0;
    outVelocity.write(half4(half3(clamp(v,-1.0f,1.0f)),0),p);outDye.write(half4(clamp(color,0.0f,5.0f)),p);
}
kernel void volumeDivergence(texture3d<half,access::read> v [[texture(0)]],texture3d<half,access::write> out [[texture(1)]],constant ExperimentUniforms &u [[buffer(8)]],uint3 p [[thread_position_in_grid]]) {
    if(any(p>=u.side))return;int3 q=int3(p);
    float div=float(v.read(volumeCell(q+int3(1,0,0),u.side)).x-v.read(volumeCell(q-int3(1,0,0),u.side)).x)+float(v.read(volumeCell(q+int3(0,1,0),u.side)).y-v.read(volumeCell(q-int3(0,1,0),u.side)).y)+float(v.read(volumeCell(q+int3(0,0,1),u.side)).z-v.read(volumeCell(q-int3(0,0,1),u.side)).z);
    out.write(half4(half(div*0.5f/float(u.side))),p);
}
kernel void volumeJacobi(texture3d<half,access::read> pressure [[texture(0)]],texture3d<half,access::read> div [[texture(1)]],texture3d<half,access::write> out [[texture(2)]],constant ExperimentUniforms &u [[buffer(8)]],uint3 p [[thread_position_in_grid]]) {
    if(any(p>=u.side))return;int3 q=int3(p);float sum=0;
    for(int a=0;a<3;a++){int3 d=0;d[a]=1;sum+=float(pressure.read(volumeCell(q+d,u.side)).x)+float(pressure.read(volumeCell(q-d,u.side)).x);}
    out.write(half4(half((sum-float(div.read(p).x))/6.0f)),p);
}
kernel void volumeProject(texture3d<half,access::read> v [[texture(0)]],texture3d<half,access::read> pressure [[texture(1)]],texture3d<half,access::write> out [[texture(2)]],constant ExperimentUniforms &u [[buffer(8)]],uint3 p [[thread_position_in_grid]]) {
    if(any(p>=u.side))return;int3 q=int3(p);float3 gradient;
    for(int a=0;a<3;a++){int3 d=0;d[a]=1;gradient[a]=float(pressure.read(volumeCell(q+d,u.side)).x-pressure.read(volumeCell(q-d,u.side)).x)*0.5f*float(u.side);}
    float3 value=float3(v.read(p).xyz)-gradient;
    for(uint a=0;a<3;a++)if(p[a]==0||p[a]==u.side-1)value[a]=0;
    out.write(half4(half3(value),0),p);
}
fragment float4 volumeSmokeFragment(ExperimentRaster in [[stage_in]],texture3d<half,access::sample> density [[texture(0)]],constant ExperimentUniforms &u [[buffer(8)]]) {
    float angle=(u.flags&1)?u.time*0.2f:0.35f;float3 camera=float3(sin(angle)*2.2f,0.6,cos(angle)*2.2f);
    float3 forward=safeUnit(-camera),right=safeUnit(cross(forward,float3(0,1,0))),up=cross(right,forward);
    float2 screen=(in.uv*2-1)*float2(u.aspect,1);float3 ray=safeUnit(forward*1.8f+right*screen.x+up*screen.y);
    float3 inverse=1.0f/(ray+1e-7f);float3 a=(-0.5f-camera)*inverse,b=(0.5f-camera)*inverse;
    float near=max(max(min(a,b).x,min(a,b).y),min(a,b).z),far=min(min(max(a,b).x,max(a,b).y),max(a,b).z);
    float3 background=float3(0.015,0.02,0.045)+in.uv.y*0.025f;
    if(far<=max(near,0.0f))return float4(background,1);
    float3 color=0;float alpha=0;float step=(far-max(near,0.0f))/96;
    for(uint i=0;i<96;i++) {
        float3 p=camera+ray*(max(near,0.0f)+(float(i)+0.5f)*step)+0.5f;
        float4 d=float4(density.sample(volumeSampler,p));float opacity=1-exp(-d.a*step*9);
        float shade=exp(-float(density.sample(volumeSampler,p+float3(-0.06,0.08,0.04)).a)*0.7f);
        color+=(1-alpha)*opacity*(d.rgb/max(d.a,0.01f))*(0.3f+shade*0.9f);alpha+=(1-alpha)*opacity;
        if(alpha>0.985f)break;
    }
    return float4(color+background*(1-alpha),1);
}
