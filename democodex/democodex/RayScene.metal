#include "ExperimentTypes.h"
#include <metal_raytracing>
using namespace raytracing;
struct SceneHit { float distance; float3 normal; uint material; };
inline float4 sphereDefinition(uint i) { return i==0?float4(-0.9,-0.22,0,0.76):(i==1?float4(0.85,-0.16,-0.3,0.82):float4(0,-0.65,1.1,0.32)); }
inline SceneHit analyticHit(float3 origin,float3 direction) {
    SceneHit hit={1000,float3(0),9};
    for(uint i=0;i<3;i++) {
        float4 sphere=sphereDefinition(i);float3 oc=origin-sphere.xyz;float b=dot(oc,direction),c=dot(oc,oc)-sphere.w*sphere.w,d=b*b-c;
        if(d<0)continue;float near=-b-sqrt(d),far=-b+sqrt(d),t=near>0.002f?near:far;
        if(t>0.002f&&t<hit.distance)hit={t,safeUnit(origin+direction*t-sphere.xyz),i+1};
    }
    if(abs(direction.y)>1e-6f){float t=(-1-origin.y)/direction.y;if(t>0.002f&&t<hit.distance)hit={t,float3(0,1,0),0};}
    if(abs(direction.z)>1e-6f){float t=(-4-origin.z)/direction.z;if(t>0.002f&&t<hit.distance)hit={t,float3(0,0,1),4};}
    return hit;
}
inline float3 sceneRay(float2 uv,constant ExperimentUniforms &u) {return safeUnit(float3((uv*2-1)*float2(u.aspect,1),-1.8f));}
inline float3 sceneLight(constant ExperimentUniforms &u) {return float3((u.touch.x-0.5f)*5,1.5f+u.touch.y*2,2+sin(u.time)*0.5f);}
inline float3 materialColor(uint material,float3 p) {
    if(material==0)return mix(float3(0.08,0.12,0.18),float3(0.7,0.78,0.85),float((int(floor(p.x*1.5f))+int(floor(p.z*1.5f)))&1));
    if(material==3)return float3(1,0.23,0.05);if(material==4)return float3(0.12,0.17,0.3);return float3(0.92,0.96,1);
}
inline void shadeBounce(SceneHit hit,float3 p,float3 light,float shadow,constant ExperimentUniforms &u,thread float3 &direction,thread float3 &origin,thread float3 &throughput,thread float3 &color) {
    float3 n=hit.normal;bool entering=dot(direction,n)<0;if(!entering)n=-n;
    float3 l=safeUnit(light-p);float diffuse=max(dot(n,l),0.0f)*shadow;float spec=pow(max(dot(reflect(-l,n),-direction),0.0f),70.0f)*shadow;
    float3 albedo=materialColor(hit.material,p);
    color+=throughput*(albedo*(0.04f+diffuse*0.7f)+spec*1.2f)*((hit.material==1||hit.material==2)?0.14f:1.0f);
    if(hit.material==0||hit.material==3||hit.material==4)throughput*=0.12f;
    else throughput*=albedo*0.88f;
    if(hit.material==2 && !(u.flags&1)) {
        float eta=entering?1.0f/1.5f:1.5f;float3 transmitted=refract(direction,n,eta);
        float fresnel=0.04f+0.96f*pow(1-max(dot(-direction,n),0.0f),5.0f);
        direction=length(transmitted)<0.01f||fresnel>0.7f?reflect(direction,n):transmitted;
        throughput*=float3(0.93,0.98,1);
    } else direction=reflect(direction,n);
    origin=p+direction*0.004f;
}
inline float3 analyticTrace(float2 uv,constant ExperimentUniforms &u) {
    float3 origin=float3(0,0.2,4),direction=sceneRay(uv,u),throughput=1,color=0,light=sceneLight(u);
    for(uint bounce=0;bounce<u.steps;bounce++) {
        SceneHit hit=analyticHit(origin,direction);
        if(hit.material==9){color+=throughput*float3(0.03,0.06,0.14);break;}
        float3 p=origin+direction*hit.distance;float3 toward=safeUnit(light-p);
        SceneHit shadow=analyticHit(p+toward*0.006f,toward);float visibility=shadow.distance<distance(light,p)?0.15f:1.0f;
        shadeBounce(hit,p,light,visibility,u,direction,origin,throughput,color);
    }
    return color;
}
kernel void traceTriangleScene(device const float4 *vertices [[buffer(0)]],primitive_acceleration_structure acceleration [[buffer(4)]],constant ExperimentUniforms &u [[buffer(8)]],texture2d<half,access::write> out [[texture(0)]],uint2 pixel [[thread_position_in_grid]]) {
    if(pixel.x>=out.get_width()||pixel.y>=out.get_height())return;
    float2 uv=(float2(pixel)+0.5f)/float2(out.get_width(),out.get_height());
    float3 origin=float3(0,0.2,4),direction=sceneRay(uv,u),throughput=1,color=0,light=sceneLight(u);
    intersector<triangle_data> intersection;
    for(uint bounce=0;bounce<u.steps;bounce++) {
        ray r(origin,direction,0.002f,1000.0f);auto hit=intersection.intersect(r,acceleration);
        if(hit.type==intersection_type::none){color+=throughput*float3(0.03,0.06,0.14);break;}
        uint base=hit.primitive_id*3;float3 a=vertices[base].xyz,b=vertices[base+1].xyz,c=vertices[base+2].xyz;uint material=uint(vertices[base].w);
        float3 p=origin+direction*hit.distance;float3 normal=safeUnit(cross(b-a,c-a));
        if(material>=1&&material<=3)normal=safeUnit(p-sphereDefinition(material-1).xyz);
        float3 toward=safeUnit(light-p);ray shadowRay(p+toward*0.006f,toward,0.002f,distance(light,p));auto shadow=intersection.intersect(shadowRay,acceleration);
        shadeBounce({hit.distance,normal,material},p,light,shadow.type==intersection_type::none?1.0f:0.15f,u,direction,origin,throughput,color);
    }
    out.write(half4(half3(color),1),pixel);
}
fragment float4 raySceneFragment(ExperimentRaster in [[stage_in]],constant ExperimentUniforms &u [[buffer(8)]],texture2d<half,access::sample> traced [[texture(0)]]) {
    constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);
    float3 color=(u.flags&4)?float3(traced.sample(s,in.uv).rgb):analyticTrace(in.uv,u);
    return float4(pow(color/(1+color),float3(1/2.2f)),1);
}
