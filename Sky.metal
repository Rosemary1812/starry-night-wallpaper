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
            offset = float2(.0025*sin(p.y*45.0+angle), .0012*cos(p.x*28.0-angle));
        } else if (u.artwork < 2.5) {
            offset = float2(.0008*sin(p.y*18.0+angle), .0005*cos(p.x*15.0-angle));
            light += .025*sin(angle)*m*u.strength;
        } else if (u.artwork < 3.5) {
            offset = float2(.003*sin(p.y*80.0+angle*2.0), .0008*cos(p.x*24.0-angle));
        } else if (u.artwork < 4.5) {
            float sky = 1.0-smoothstep(.40,.65,p.y);
            offset = mix(float2(.003*sin(p.x*30.0+angle), .001*sin(p.x*30.0+angle)),
                float2(.004*sin(p.y*18.0+angle), .0015*cos(p.x*15.0-angle)),sky);
        } else if (u.artwork < 5.5) {
            // BEGIN motion: impression-sunrise
            // Impression, Sunrise: small horizontal ripples follow the painted water.
            // The subject mask holds the sun, harbor, boats and people completely still.
            float water = smoothstep(.55,.92,p.y);
            offset = float2(smoothstep(.55,.64,p.y)*(.0012+.0014*water)*sin(p.y*95.0+angle*2.0),
                .00065*water*cos(p.x*32.0-angle));
            // Warm reflections breathe locally, without tinting the rest of the canvas.
            float reflectionX = (p.x-.605)/.065;
            float reflection = exp(-reflectionX*reflectionX)
                * smoothstep(.46,.55,p.y) * (1.0-smoothstep(.83,.96,p.y));
            light += .012*sin(angle)*reflection*m*u.strength;
            // END motion: impression-sunrise
        } else if (u.artwork < 6.5) {
            // BEGIN motion: waterloo-bridge
            // Only the open Thames moves; masonry, haze, skyline and signature are masked.
            float depth = smoothstep(.60,.94,p.y);
            float ripple = sin(p.y*108.0 + angle*2.0 + .35*sin(p.x*7.0));
            float undertone = sin(p.y*181.0 - angle + p.x*3.0);
            float horizontal = (.00048 + .00102*depth)*(ripple + .18*undertone);
            float vertical = .00022*depth*sin(p.x*22.0 + p.y*29.0 - angle);
            offset = float2(horizontal, vertical);
            light = 1.0;
            // END motion: waterloo-bridge
        } else if (u.artwork < 7.5) {
            // BEGIN motion: nocturne-bognor
            // A slow sea-swell remains between the fixed horizon, boats and beach.
            float depth = smoothstep(.365,.69,p.y);
            float shoreEase = 1.0 - smoothstep(.73,.855,p.y);
            float sea = depth*shoreEase;
            float swell = sin(p.y*79.0 - angle + .28*sin(p.x*6.0));
            float ripple = sin(p.y*137.0 + angle*2.0 + p.x*4.0);
            float horizontal = sea*(.00118*swell + .00023*ripple);
            float silverY = (p.y-.672)/.075;
            float silverBand = exp(-silverY*silverY);
            float vertical = sea*(.00010 + .00016*silverBand)*sin(p.x*18.0 + p.y*26.0 - angle);
            offset = float2(horizontal, vertical);
            light = 1.0;
            // END motion: nocturne-bognor
        } else if (u.artwork < 8.5) {
            // BEGIN motion: approach-venice
            // Turner: preserve the entire sky and city; ripple only unobstructed lagoon water.
            float water = smoothstep(.663,.742,p.y);
            float nearWater = smoothstep(.72,.97,p.y);
            float ripples = sin(p.y*143.0 + angle*2.0 + .34*sin(p.x*7.0));
            float fineRipples = sin(p.y*231.0 - angle*3.0 + p.x*5.0);
            float horizontal = water*((.00070+.00070*nearWater)*ripples + .00022*nearWater*fineRipples);
            float vertical = water*.00019*nearWater*cos(p.y*88.0 + p.x*13.0 - angle*2.0);
            offset = float2(horizontal,vertical);
            // Let the original pigments create the shimmer. No illumination modulation.
            light = 1.0;
            // END motion: approach-venice
        } else if (u.artwork < 9.5) {
            // BEGIN motion: cliff-walk
            // Monet: separate sky, open sea, and two small grass patches; solid subjects stay masked.
            float sky = 1.0-smoothstep(.265,.350,p.y);
            float cloudDrift = .00090*sin(angle) + .00022*sin(angle*2.0+p.y*3.0);
            float skyX = sky*cloudDrift;
            float skyY = sky*.00013*sin(angle*2.0+.8);
            float sea = smoothstep(.458,.500,p.y)*(1.0-smoothstep(.715,.780,p.y));
            sea *= 1.0-smoothstep(.385,.435,p.x);
            float nearSea = smoothstep(.48,.72,p.y);
            float seaX = sea*((.00066+.00040*nearSea)*sin(p.y*145.0-angle*2.0) + .00018*sin(p.y*231.0+angle*3.0+p.x*6.0));
            float seaY = sea*.00019*nearSea*cos(p.y*93.0+p.x*17.0-angle*2.0);
            float rx = (p.x-.825)/.185;
            float ry = (p.y-.745)/.225;
            float rightGrass = exp(-rx*rx-ry*ry)*smoothstep(.52,.63,p.y);
            float lx = (p.x-.205)/.235;
            float ly = (p.y-.895)/.120;
            float lowGrass = exp(-lx*lx-ly*ly)*smoothstep(.760,.835,p.y);
            float grass = rightGrass + .70*lowGrass;
            float grassX = .00070*grass*sin(angle+p.x*8.0+p.y*2.0);
            float grassY = .00016*grass*sin(angle*2.0+p.x*6.0);
            offset = float2(skyX+seaX+grassX,skyY+seaY+grassY);
            light = 1.0;
            // END motion: cliff-walk
        } else if (u.artwork < 10.5) {
            // BEGIN motion: bridge-villeneuve
            float river = smoothstep(.696,.779,p.y);
            float nearWater = smoothstep(.725,.985,p.y);
            float channelX = (p.x-.72)/.55;
            float channel = .50+.50*exp(-channelX*channelX);
            float ripples = .78*sin(p.y*148.0+angle*2.0+.40*sin(p.x*7.0))+.22*sin(p.y*236.0-angle*3.0+p.x*8.0);
            offset = float2(river*channel*(.00055+.00110*nearWater)*ripples, river*channel*.00016*nearWater*sin(p.y*182.0+angle*2.0+p.x*9.0));
            light = 1.0;
            // END motion: bridge-villeneuve
        } else if (u.artwork < 11.5) {
            // BEGIN motion: parliament-sunset
            float bank = .650+.105*smoothstep(.090,.180,p.x);
            float river = smoothstep(bank,bank+.075,p.y);
            float nearWater = smoothstep(.760,.980,p.y);
            float reflectionX = (p.x-.28)/.42;
            float reflectionChannel = .72+.28*exp(-reflectionX*reflectionX);
            float ripples = .80*sin(p.y*138.0+angle*2.0+.38*sin(p.x*9.0))+.20*sin(p.y*237.0-angle*3.0+p.x*12.0);
            offset = float2(river*reflectionChannel*(.00045+.00135*nearWater)*ripples, river*reflectionChannel*.00019*nearWater*sin(p.y*154.0-angle*2.0+p.x*8.0));
            light = 1.0;
            // END motion: parliament-sunset
        }
        float2 samplePoint = clamp(p+offset*u.strength*m,0.0,1.0);
        return float4(mix(original.rgb,painting.sample(s,samplePoint).rgb,m)*light,1);
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
