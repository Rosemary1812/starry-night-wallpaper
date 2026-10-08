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
float ellipseInfluence(float2 uv, float2 center, float2 radius) {
    float2 p = (uv-center)/radius;
    return exp(-dot(p,p));
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
        } else if (u.artwork < 4.5) {
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
        } else if (u.artwork < 5.5) {
            // BEGIN motion: impression-sunrise
            // Impression, Sunrise: layered, mostly horizontal water strokes.
            // The quiet halos keep the small boats from pulling the surrounding paint.
            float water = smoothstep(.555,.690,p.y) * (1.0-smoothstep(.970,.998,p.y));
            float nearWater = smoothstep(.680,.935,p.y);
            float boatQuiet = 1.0;
            boatQuiet *= 1.0 - .58*ellipseInfluence(p,float2(.474,.713),float2(.105,.080));
            boatQuiet *= 1.0 - .42*ellipseInfluence(p,float2(.294,.628),float2(.120,.074));
            boatQuiet *= 1.0 - .30*ellipseInfluence(p,float2(.175,.575),float2(.105,.058));
            boatQuiet = clamp(boatQuiet,.18,1.0);
            float brushBands = pow(.5+.5*sin(p.y*128.0 + .55*sin(p.x*10.0)),2.2);
            float broadSlip = .00020*sin(p.y*38.0 + angle*.70 + p.x*2.0);
            float smallRipples = (.00030+.00026*nearWater)*brushBands
                * sin(p.y*154.0 + angle*1.45 + p.x*5.5);
            float foregroundTexture = .00022*nearWater*sin(p.y*248.0 - angle*2.25 + p.x*9.0);
            float reflectionX = (p.x-.600)/.052;
            float reflection = exp(-reflectionX*reflectionX)
                * smoothstep(.555,.630,p.y) * (1.0-smoothstep(.870,.950,p.y));
            float reflectionSlip = reflection*(.00034*sin(p.y*185.0 + angle*1.85)
                + .00014*sin(p.y*315.0 - angle*2.65 + p.x*4.0));
            float vertical = water*boatQuiet*(.000075*nearWater*cos(p.x*17.0+p.y*55.0-angle*1.1)
                + .000095*reflection*sin(p.y*122.0-angle*.9));
            offset = float2(water*boatQuiet*(broadSlip+smallRipples+foregroundTexture+reflectionSlip), vertical);
            light = 1.0;
            // END motion: impression-sunrise
        } else if (u.artwork < 6.5) {
            // BEGIN motion: waterloo-bridge
            // Waterloo Bridge: near water has fine shimmer; far water barely slips
            // below the bridge so the arches do not look rubbery.
            float water = smoothstep(.615,.735,p.y) * (1.0-smoothstep(.975,.998,p.y));
            float nearWater = smoothstep(.705,.955,p.y);
            float edgeSafe = smoothstep(.24,.88,m);
            float archPhase = .52*sin(p.x*9.5) + .21*sin(p.x*21.0);
            float longRipple = sin(p.y*82.0 + angle*.82 + archPhase);
            float shortRipple = sin(p.y*176.0 - angle*1.65 + p.x*12.0);
            float foregroundRipple = sin(p.y*265.0 + angle*2.25 + p.x*5.0);
            float horizontal = water*edgeSafe*((.00018+.00018*nearWater)*longRipple
                + .00024*nearWater*shortRipple + .000105*nearWater*foregroundRipple);
            float vertical = water*edgeSafe*.000065*nearWater
                * cos(p.x*17.0 + p.y*31.0 - angle*.8);
            offset = float2(horizontal, vertical);
            light = 1.0;
            // END motion: waterloo-bridge
        } else if (u.artwork < 7.5) {
            // BEGIN motion: nocturne-bognor
            // Nocturne: the sea moves as a heavy, quiet horizontal swell.
            // Sailboats, beach silhouettes and the horizon stay visually anchored.
            float sea = smoothstep(.392,.505,p.y) * (1.0-smoothstep(.745,.835,p.y));
            float nearSea = smoothstep(.585,.735,p.y);
            float boatQuiet = 1.0;
            boatQuiet *= 1.0 - .55*ellipseInfluence(p,float2(.165,.535),float2(.080,.115));
            boatQuiet *= 1.0 - .48*ellipseInfluence(p,float2(.325,.555),float2(.070,.120));
            boatQuiet *= 1.0 - .36*ellipseInfluence(p,float2(.804,.420),float2(.070,.085));
            boatQuiet = clamp(boatQuiet,.20,1.0);
            float horizonEase = smoothstep(.405,.485,p.y);
            float swell = sin(p.y*54.0 - angle*.72 + .18*sin(p.x*5.0));
            float lowRipple = sin(p.y*116.0 + angle*1.30 + p.x*3.5);
            float silverY = (p.y-.655)/.080;
            float silverBand = exp(-silverY*silverY);
            float glints = pow(.5+.5*sin(p.y*170.0 - angle*1.8 + p.x*7.0),2.6);
            float horizontal = sea*boatQuiet*(.00034*horizonEase*swell
                + .00022*nearSea*lowRipple + .00020*silverBand*glints*sin(angle+p.x*2.0));
            float vertical = sea*boatQuiet*.000055*nearSea*sin(p.x*15.0+p.y*20.0-angle*.65);
            offset = float2(horizontal, vertical);
            light = 1.0;
            // END motion: nocturne-bognor
        } else if (u.artwork < 8.5) {
            // BEGIN motion: approach-venice
            // Turner: a broad lagoon shimmer with quieter water around each boat.
            // The bright sky and city haze stay still, preserving the atmospheric veil.
            float water = smoothstep(.670,.760,p.y) * (1.0-smoothstep(.965,.998,p.y));
            float nearWater = smoothstep(.735,.955,p.y);
            float boatQuiet = 1.0;
            boatQuiet *= 1.0 - .66*ellipseInfluence(p,float2(.210,.855),float2(.155,.125));
            boatQuiet *= 1.0 - .50*ellipseInfluence(p,float2(.510,.742),float2(.120,.070));
            boatQuiet *= 1.0 - .42*ellipseInfluence(p,float2(.625,.760),float2(.115,.070));
            boatQuiet *= 1.0 - .35*ellipseInfluence(p,float2(.785,.735),float2(.120,.065));
            boatQuiet = clamp(boatQuiet,.18,1.0);
            float leftGlow = ellipseInfluence(p,float2(.095,.675),float2(.070,.120));
            float lagoonBands = pow(.5+.5*sin(p.y*122.0 + .45*sin(p.x*8.0)),2.0);
            float broad = .00018*sin(p.y*45.0 + angle*.62 + p.x*1.5);
            float fine = (.00028+.00028*nearWater)*lagoonBands*sin(p.y*160.0 + angle*1.55 + p.x*5.0);
            float foreground = .00020*nearWater*sin(p.y*250.0 - angle*2.15 + p.x*8.5);
            float glowSlip = .00022*leftGlow*sin(p.y*115.0-angle*.9);
            float horizontal = water*boatQuiet*(broad+fine+foreground+glowSlip);
            float vertical = water*boatQuiet*(.000060*nearWater*cos(p.y*88.0 + p.x*13.0 - angle*.85)
                + .000050*leftGlow*sin(p.x*8.0+angle));
            offset = float2(horizontal,vertical);
            // Let the original pigments create the shimmer. No illumination modulation.
            light = 1.0;
            // END motion: approach-venice
        } else if (u.artwork < 9.5) {
            // BEGIN motion: cliff-walk
            // Monet: clouds drift gently, sea runs in low horizontal bands, and
            // grass trembles locally away from the two figures and cliff silhouette.
            float sky = 1.0-smoothstep(.225,.345,p.y);
            float cloudField = .45*ellipseInfluence(p,float2(.235,.085),float2(.145,.075))
                + .55*ellipseInfluence(p,float2(.500,.145),float2(.175,.090))
                + .35*ellipseInfluence(p,float2(.735,.105),float2(.150,.080));
            float skyX = sky*cloudField*(.00023*sin(angle*.42) + .00010*sin(angle*.83+p.y*4.0));
            float skyY = sky*cloudField*.000035*sin(angle*.65+p.x*3.0);
            float sea = smoothstep(.446,.510,p.y)*(1.0-smoothstep(.715,.790,p.y));
            sea *= 1.0-smoothstep(.375,.445,p.x);
            float nearSea = smoothstep(.515,.705,p.y);
            float whitecaps = pow(.5+.5*sin(p.y*150.0 + p.x*9.0),2.8);
            float seaX = sea*((.00028+.00028*nearSea)*sin(p.y*116.0-angle*1.25+p.x*2.0)
                + .00018*whitecaps*sin(p.y*215.0+angle*2.1+p.x*7.0));
            float seaY = sea*.000055*nearSea*cos(p.y*86.0+p.x*15.0-angle);
            float rightGrass = ellipseInfluence(p,float2(.825,.750),float2(.185,.205))*smoothstep(.555,.660,p.y);
            float lowGrass = ellipseInfluence(p,float2(.205,.890),float2(.235,.115))*smoothstep(.765,.845,p.y);
            float figureQuiet = 1.0 - .60*ellipseInfluence(p,float2(.650,.500),float2(.080,.155));
            figureQuiet *= 1.0 - .42*ellipseInfluence(p,float2(.940,.360),float2(.095,.150));
            figureQuiet = clamp(figureQuiet,.24,1.0);
            float grass = (rightGrass + .60*lowGrass)*figureQuiet;
            float grassX = .00034*grass*sin(angle*.92+p.x*7.5+p.y*3.0);
            float grassY = .000055*grass*sin(angle*1.7+p.x*5.0);
            offset = float2(skyX+seaX+grassX,skyY+seaY+grassY);
            light = 1.0;
            // END motion: cliff-walk
        } else if (u.artwork < 10.5) {
            // BEGIN motion: bridge-villeneuve
            // Villeneuve: faster foreground current, slower water under the bridge,
            // with quiet margins around the pier reflection and moored boats.
            float river = smoothstep(.700,.795,p.y) * (1.0-smoothstep(.975,.998,p.y));
            float nearWater = smoothstep(.760,.955,p.y);
            float channelX = (p.x-.68)/.58;
            float channel = .44+.56*exp(-channelX*channelX);
            float quiet = 1.0;
            quiet *= 1.0 - .52*ellipseInfluence(p,float2(.140,.795),float2(.105,.145));
            quiet *= 1.0 - .45*ellipseInfluence(p,float2(.255,.720),float2(.135,.070));
            quiet *= 1.0 - .30*ellipseInfluence(p,float2(.610,.690),float2(.120,.060));
            quiet = clamp(quiet,.20,1.0);
            float farCurrent = .00018*sin(p.y*72.0 + angle*.70 + p.x*2.0);
            float midRipples = .00032*sin(p.y*142.0 + angle*1.45 + .34*sin(p.x*6.0));
            float foreground = .00030*nearWater*sin(p.y*235.0 - angle*2.05 + p.x*9.0);
            float horizontal = river*channel*quiet*(farCurrent + midRipples + foreground);
            float vertical = river*channel*quiet*.000070*nearWater*sin(p.y*152.0 + angle*1.1 + p.x*8.0);
            offset = float2(horizontal, vertical);
            light = 1.0;
            // END motion: bridge-villeneuve
        } else if (u.artwork < 11.5) {
            // BEGIN motion: parliament-sunset
            // Parliament: preserve the skyline silhouette; animate warm reflected
            // bands differently from the cooler foreground water.
            float bank = .650+.105*smoothstep(.090,.180,p.x);
            float river = smoothstep(bank+.035,bank+.125,p.y) * (1.0-smoothstep(.970,.998,p.y));
            float nearWater = smoothstep(.765,.965,p.y);
            float silhouetteSafe = smoothstep(.36,.94,m);
            float warmLeft = ellipseInfluence(p,float2(.130,.785),float2(.185,.260));
            float centerBoatQuiet = 1.0 - .48*ellipseInfluence(p,float2(.590,.735),float2(.110,.080));
            float rightBoatQuiet = 1.0 - .40*ellipseInfluence(p,float2(.900,.765),float2(.145,.085));
            float quiet = clamp(centerBoatQuiet*rightBoatQuiet,.24,1.0);
            float warmFlicker = warmLeft*(.00034*sin(p.y*156.0 + angle*1.42)
                + .00018*sin(p.y*264.0 - angle*2.10 + p.x*6.0));
            float coolRipple = (.00020+.00026*nearWater)
                * sin(p.y*118.0 + angle*.95 + .33*sin(p.x*9.0));
            float foreground = .00028*nearWater*sin(p.y*226.0 - angle*1.85 + p.x*10.0);
            float horizontal = river*silhouetteSafe*quiet*(warmFlicker+coolRipple+foreground);
            float vertical = river*silhouetteSafe*quiet*.000075*nearWater
                * sin(p.y*144.0-angle*.95+p.x*7.0);
            offset = float2(horizontal, vertical);
            light = 1.0;
            // END motion: parliament-sunset
        }
        if (u.artwork < 4.5) {
        // BEGIN sampling: refined-four
        float2 displacement = offset*u.strength*m;
        float pathMask = min(maskAt(mask,p+displacement*.5),maskAt(mask,p+displacement));
        float pathSafety = smoothstep(0.0,.20,pathMask);
        float2 samplePoint = clamp(p+displacement*pathSafety,0.0,1.0);
        return float4(painting.sample(s,samplePoint).rgb*light,1);
        // END sampling: refined-four
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
