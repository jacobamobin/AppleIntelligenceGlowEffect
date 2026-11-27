#include <metal_stdlib>
using namespace metal;

struct Vertex { float4 position [[position]]; float2 uv; };
// 56 float4s, shared with GlowRenderer. Audio controls the glow; cursor adds a small local bend.
struct Uniforms {
    float4 info;       // elapsed, opacity, logical width, logical height
    float4 response;   // loudness, bass onset, sensitivity, reserved
    float4 meters;     // bass, mids, treble, RMS
    float4 colors[4];
    float4 spectrum[16];
    float4 peaks[16];
    float4 waveform[16];
    float4 pointer;    // normalized x, proximity, smoothed speed, normalized height
};

vertex Vertex glowVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return {float4(p * 2.0 - 1.0, 0, 1), p};
}

float sampleValue(constant float4 *data, int index) {
    index = clamp(index, 0, 63);
    return data[index / 4][index % 4];
}

// Catmull-Rom sampling adapted from Nowsee (MIT).
// Copyright (c) 2026 Sergey (Sergio-prog). See ThirdParty/Nowsee.
float curveSample(constant float4 *data, float u) {
    float x = u * 64.0 - 0.5;
    int base = int(floor(x));
    float t = fract(x);
    float p0 = sampleValue(data, base-1), p1 = sampleValue(data, base);
    float p2 = sampleValue(data, base+1), p3 = sampleValue(data, base+2);
    return 0.5 * ((2*p1) + (-p0+p2)*t + (2*p0-5*p1+4*p2-p3)*t*t
                  + (-p0+3*p1-3*p2+p3)*t*t*t);
}

float smoothSpectrum(constant float4 *data, float x) {
    return max(0.0, curveSample(data,x)*0.28
         + (curveSample(data,x-0.028)+curveSample(data,x+0.028))*0.22
         + (curveSample(data,x-0.060)+curveSample(data,x+0.060))*0.14);
}

// Continuous moving color fields, informed by Aurora's anchored color blending.
// Independent implementation; no vendor binary or SwiftUI render dependency.
float3 lightColor(constant Uniforms &u, float2 p) {
    float drift = 0.15*sin(u.info.x*0.14)+0.045*sin(u.info.x*0.063);
    float3 color = 0;
    float total = 0;
    for (int i=0; i<8; ++i) {
        float centre = float(i)*0.32-0.58+drift;
        float sway = 0.045*sin(u.info.x*0.10+float(i)*1.7);
        float2 delta = float2((p.x-centre)*5.2,(p.y*0.18-sway)*2.2);
        float weight = exp(-dot(delta,delta));
        color += u.colors[i%4].rgb*weight;
        total += weight;
    }
    color /= max(total,0.0001);
    // Artwork supplies the hue; emission lifts dark pigment into luminous light.
    color /= max(0.30,max(color.r,max(color.g,color.b)));
    float luma = dot(color,float3(0.213,0.716,0.072));
    return saturate(mix(float3(luma),color,1.18));
}

fragment float4 glowFragment(Vertex in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float x = in.uv.x, y = in.uv.y;
    float gain = u.response.z;
    float loudness = saturate(u.response.x);
    float onset = saturate(u.response.y);
    float3 meters = saturate(u.meters.xyz*gain);
    float local = saturate(smoothSpectrum(u.spectrum,x)*gain);
    float echo = saturate(smoothSpectrum(u.spectrum,1-x)*gain);
    float held = saturate(smoothSpectrum(u.peaks,x)*gain);
    float side = smoothstep(0.08,0.94,abs(x*2.0-1.0));

    // Broad audio clouds vary across the whole strip. Their centres drift with
    // the balance of real frequency energy; no clock manufactures a beat.
    float left = 0.12+0.11*(meters.y-meters.z);
    float middle = 0.50+0.14*(meters.x-meters.z);
    float right = 0.88+0.11*(meters.x-meters.y);
    float clouds = meters.x*exp(-pow((x-left)/0.25,2.0))
                 + meters.y*exp(-pow((x-middle)/0.26,2.0))
                 + meters.z*exp(-pow((x-right)/0.25,2.0));
    float wingEnergy = side*saturate(meters.x*0.5+meters.y*0.2);
    float rawDrive = local*0.58+echo*0.18+clouds*0.36
                    +loudness*0.30+onset*0.25+wingEnergy*0.60;
    // A soft knee leaves headroom instead of flat-topping on bass-heavy tracks.
    float drive = 1-exp(-rawDrive*0.95);
    float active = smoothstep(0.0,0.035,drive);
    float envelope = mix(0.55,0.96,side);
    float waveform = clamp(curveSample(u.waveform,x)*0.5
                         + (curveSample(u.waveform,x-0.018)+curveSample(u.waveform,x+0.018))*0.25,-1.0,1.0);
    float cursor = exp(-pow((x-u.pointer.x)/0.075,2.0))*u.pointer.y;
    // Lower everyday diffusion; only strong smoothed transients open taller blooms.
    float reach = max(0.06,0.045+envelope*(0.46*pow(drive,1.1)+held*0.06+waveform*0.08
                      +0.42*pow(onset,3.0))+cursor*(0.020+0.010*u.pointer.z)*active);

    // The light source sits BELOW the physical screen. We crop an extended
    // field at left/right; neither edge participates in the distance function.
    // There is no vertical side stroke, lateral fade, or separate hard core.
    float distance = y+0.045;
    float nearGlow = exp(-pow(distance/(reach*0.72+0.045),2.0));
    float broadGlow = exp(-pow(distance/(reach*1.00+0.060),2.0));
    float strength = 0.60+0.24*loudness+0.18*onset;
    float glow = (nearGlow*0.43+broadGlow*0.29)*strength*active;
    float idle = exp(-pow((y+0.05)/0.14,2.0))*0.08;
    // The Gaussian tail is already faint here; the final 90–100% disappears
    // completely with zero slope/curvature at both ends of the feather.
    float feather = saturate((y-0.90)/0.10);
    float topFade = 1-feather*feather*feather*(feather*(feather*6-15)+10);
    float alpha = min(0.72,idle+glow)*topFade*u.info.y;
    float3 color = lightColor(u,float2(x-cursor*u.pointer.z*0.008,y));
    return float4(color*alpha,alpha);
}
