#include <metal_stdlib>
using namespace metal;

struct Parameters {
    float time;
    float strength;
    float aspect;
    float showMask;
};
struct VertexOut { float4 position [[position]]; float2 uv; };

vertex VertexOut vertexMain(uint id [[vertex_id]]) {
    float2 points[] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    float2 p = points[id];
    return {float4(p,0,1), float2((p.x+1)*0.5, (1-p.y)*0.5)};
}

// Elliptical vortices follow the two large painted curls, with smaller star halos.
float2 vortex(float2 uv, float2 center, float2 radius, float amount) {
    float2 p = (uv-center)/radius;
    float falloff = exp(-dot(p,p)*2.0);
    return float2(-p.y*radius.x, p.x*radius.y)*falloff*amount;
}
float2 flow(float2 p) {
    float2 v = vortex(p, float2(.499,.345), float2(.295,.239), .41);
    v += vortex(p, float2(.718,.477), float2(.160,.145), -.38);
    v += vortex(p, float2(.902,.173), float2(.126,.150), .19);
    v += vortex(p, float2(.11,.045), float2(.080,.100), .18);
    v += vortex(p, float2(.241,.177), float2(.075,.085), .16);
    v += vortex(p, float2(.357,.524), float2(.085,.102), .19);
    v += vortex(p, float2(.611,.079), float2(.085,.093), .19);
    v += vortex(p, float2(.348,.041), float2(.070,.080), .16);
    // A small drift keeps the quieter sky connected to the curls.
    v += float2(.0035*cos(p.y*10.0), .0013*sin(p.x*12.0));
    return v;
}
float maskAt(texture2d<float> mask, float2 p) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float edge = smoothstep(0.0,.02,min(min(p.x,1-p.x),min(p.y,1-p.y)));
    return smoothstep(.04,.96,mask.sample(s,p).r)*edge;
}
float2 trace(float2 p, float duration, float strength, texture2d<float> mask) {
    // Integrating the mask at every step prevents a trajectory crossing the tree.
    float dt = duration/6.0;
    for (int i=0;i<6;i++) {
        float2 v = flow(p)*strength*maskAt(mask,p);
        float2 middle = p-v*dt*.5;
        p -= flow(middle)*strength*maskAt(mask,middle)*dt;
    }
    return clamp(p,0.0,1.0);
}
fragment float4 fragmentMain(VertexOut in [[stage_in]],
    texture2d<float> painting [[texture(0)]], texture2d<float> mask [[texture(1)]],
    constant Parameters &u [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 p = in.uv;
    const float imageAspect = 4096.0/3243.0;
    // Aspect fill is identical in preview, export and desktop windows.
    if(u.aspect>imageAspect) p.y=(p.y-.5)*imageAspect/u.aspect+.5;
    else p.x=(p.x-.5)*u.aspect/imageAspect+.5;
    float4 original = painting.sample(s,p);
    float m = maskAt(mask,p);
    if(u.showMask>.5) return float4(mix(original.rgb, float3(.23,.80,.96),m*.65),1);
    if(m<.001 || u.strength==0.0) return original;
    // Two half-cycle-offset advections dissolve only when their reset is invisible.
    // Both the image and its temporal derivative match after one full cycle.
    float phase = fract(u.time/24.0);
    float a = phase-.5;
    float b = fract(phase+.5)-.5;
    float weight = .5-.5*cos(phase*2.0*M_PI_F);
    float4 ca = painting.sample(s,trace(p,a,u.strength,mask));
    float4 cb = painting.sample(s,trace(p,b,u.strength,mask));
    return mix(original,mix(cb,ca,weight),m);
}
