#include <metal_stdlib>
using namespace metal;

struct Parameters {
    float time;
    float strength;
    float aspect;
    float showMask;
    float artwork;
    float imageAspect;
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
    float imageAspect = u.imageAspect;
    // Aspect fill is identical in preview, export and desktop windows.
    if(u.aspect>imageAspect) p.y=(p.y-.5)*imageAspect/u.aspect+.5;
    else p.x=(p.x-.5)*u.aspect/imageAspect+.5;
    float4 original = painting.sample(s,p);
    float m = maskAt(mask,p);
    if(u.showMask>.5) return float4(mix(original.rgb, float3(.23,.80,.96),m*.65),1);
    if(m<.001 || u.strength==0.0) return original;
    float angle = fract(u.time/24.0) * (2.0 * M_PI_F);
    if (u.artwork > .5) {
        float2 offset = float2(0);
        float light = 1.0;
        if (u.artwork < 1.5) {
            // BEGIN motion: water-lilies
            // Long, predominantly horizontal ripples; depth and local phase follow the pond.
            float depth = smoothstep(.18,.92,p.y);
            float phase = p.y*58.0 + .38*sin(p.x*4.3);
            float wave = (sin(phase+angle) + .28*sin(p.y*104.0-angle*2.0+p.x*5.0+.7))/1.28;
            offset = float2((.00055+.00028*depth)*wave,
                .00010*depth*sin(p.y*37.0+angle+p.x*5.0));
            // END motion: water-lilies
        } else if (u.artwork < 2.5) {
            // BEGIN motion: wheat-stacks
            // The snow and haystacks stay still; only the existing warm sky changes subtly.
            float warmX = (p.x-.66)/.40;
            float warmY = (p.y-.105)/.13;
            float evening = exp(-warmX*warmX-warmY*warmY);
            light += .0032*sin(angle+.6*p.x)*evening*m*u.strength;
            // END motion: wheat-stacks
        } else if (u.artwork < 3.5) {
            // BEGIN motion: rhone
            // Far ripples are smaller/denser; horizontal phase varies gently across the river.
            float shoreX = (p.x-.02)/.23;
            float shoreY = .49+.095*exp(-shoreX*shoreX);
            float shore = smoothstep(shoreY,shoreY+.10,p.y);
            float depth = smoothstep(.50,.83,p.y);
            float phase = p.y*100.0-p.y*p.y*30.0+.40*sin(p.x*9.0);
            float wave = (sin(phase-angle)+.22*sin(phase*1.75-angle*2.0+p.x*11.0+.8))/1.22;
            offset = float2(.00085*(.25+.75*depth)*shore*wave,
                .00008*depth*shore*cos(phase*.61-angle+p.x*6.0));
            // END motion: rhone
        } else {
            // BEGIN motion: cypresses
            // Small tangential fields follow the painted cloud curls rather than sliding rows.
            float c1x = (p.x-.235)/.26;
            float c1y = (p.y-.28)/.20;
            float c2x = (p.x-.57)/.25;
            float c2y = (p.y-.22)/.19;
            float c3x = (p.x-.64)/.20;
            float c3y = (p.y-.43)/.15;
            float curl1 = exp(-(c1x*c1x+c1y*c1y)*1.5)*.00068*sin(angle+.35);
            float curl2 = exp(-(c2x*c2x+c2y*c2y)*1.5)*.00062*sin(angle+1.10);
            float curl3 = exp(-(c3x*c3x+c3y*c3y)*1.5)*.00054*sin(angle-.60);
            float cloudX = -c1y*curl1-c2y*curl2+c3y*curl3+.00022*sin(p.y*16.0+angle+p.x*.8);
            float cloudY = (c1x*curl1+c2x*curl2-c3x*curl3)*.58;
            // Approximate the sloped mountain/bush skyline; the exact subject mask is authoritative.
            float hillX = (p.x-.58)/.24;
            float bushX = (p.x-.22)/.12;
            float skyline = .64-.12*exp(-hillX*hillX)-.09*exp(-bushX*bushX);
            float sky = 1.0-smoothstep(skyline-.03,skyline+.015,p.y);
            // Coherent wind with gentle phase lag between wheat clusters; lower roots stay quiet.
            float tips = smoothstep(.68,.81,p.y)*(1.0-smoothstep(.90,.97,p.y));
            float wind = (sin(p.x*12.0-p.y*5.0-angle)+.25*sin(p.x*21.0+p.y*9.0-angle*2.0+.5))/1.25;
            offset = float2(mix(.00055*tips*wind,cloudX,sky), mix(.00018*tips*wind,cloudY,sky));
            // END motion: cypresses
        }
        // BEGIN sampling: refined-four
        float2 displacement = offset*u.strength*m;
        float pathMask = min(maskAt(mask,p+displacement*.5),maskAt(mask,p+displacement));
        float pathSafety = smoothstep(0.0,.20,pathMask);
        float2 samplePoint = clamp(p+displacement*pathSafety,0.0,1.0);
        return float4(painting.sample(s,samplePoint).rgb*light,1);
        // END sampling: refined-four
    }
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
