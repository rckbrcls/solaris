#include <metal_stdlib>
using namespace metal;

struct LumaGrainUniforms {
    float strength;
    float size;
    float seed;
    float pad; // 16-byte alignment for constant buffer safety
};

// sRGB <-> Linear helpers using half where possible for performance
static inline float3 srgbToLinearH(half3 c) {
    half3 low  = c / 12.92h;
    half3 high = 1.055h * pow(max((c + 0.055h) / 1.055h, half3(0.0h)), half3(2.4h));
    half3 cond = step(half3(0.04045h), c);
    return (float3)mix(low, high, cond);
}

static inline half3 linearToSrgbH(float3 c) {
    half3 ch = (half3)c;
    half3 low  = 12.92h * ch;
    half3 high = 1.055h * pow(max(ch, half3(0.0h)), half3(1.0h/2.4h)) - half3(0.055h);
    half3 cond = step(half3(0.0031308h), ch);
    return mix(low, high, cond);
}

// Fast integer hash -> [0,1)
static inline float hash_uint(uint2 p) {
    uint n = p.x * 1103515245u ^ p.y * 12345u;
    n ^= (n >> 16);
    n *= 2246822519u;
    n ^= (n >> 13);
    n *= 3266489917u;
    n ^= (n >> 16);
    return (float)(n & 0x00FFFFFFu) * (1.0 / 16777216.0);
}

// Light domain warp to break patterns
static inline float2 warpCoord(float2 p, uint seed) {
    uint2 pu = uint2((int)p.x, (int)p.y) ^ uint2(seed * 374761393u, seed * 668265263u);
    float jx = hash_uint(pu) - 0.5;
    float jy = hash_uint(pu ^ uint2(0x9E3779B9u, 0x85EBCA6Bu)) - 0.5;
    return p + float2(jx, jy) * 0.7;
}

// Per-pixel noise, 3 octaves, zero-mean; sized by base frequency
static inline float grainNoiseFast(float2 p, float baseFreq, float seedF) {
    uint seed = (uint)(seedF * 65535.0) ^ 0x9E3779B9u;
    float2 pf1 = floor(warpCoord(p * baseFreq, seed));
    float2 pf2 = floor(warpCoord(p * baseFreq * 1.97, seed ^ 0x85EBCA6Bu));
    float2 pf3 = floor(warpCoord(p * baseFreq * 2.53, seed ^ 0xC2B2AE35u));
    float n1 = hash_uint(uint2((int)pf1.x, (int)pf1.y));
    float n2 = hash_uint(uint2((int)pf2.x, (int)pf2.y));
    float n3 = hash_uint(uint2((int)pf3.x, (int)pf3.y));
    return (n1*0.62 + n2*0.28 + n3*0.10) - 0.5;
}

struct LumaGrainVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex LumaGrainVertexOut lumaGrainVertex(uint vid [[vertex_id]]) {
    constexpr float2 pos[4] = { float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0), float2( 1.0,  1.0) };
    constexpr float2 uv[4]  = { float2( 0.0,  1.0), float2( 1.0,  1.0), float2( 0.0,  0.0), float2( 1.0,  0.0) };
    LumaGrainVertexOut o; o.position = float4(pos[vid], 0.0, 1.0); o.texCoord = uv[vid]; return o;
}

fragment float4 lumaGrainFragment(
    LumaGrainVertexOut inV                      [[ stage_in ]],
    texture2d<half, access::sample> inputImage  [[ texture(0) ]],
    constant LumaGrainUniforms &u               [[ buffer(0) ]]
) {
    constexpr sampler inputSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 coord = inV.texCoord;
    half4 hs = inputImage.sample(inputSampler, coord);

    // Image size and pixel coordinates for noise
    float2 texSize = float2(inputImage.get_width(), inputImage.get_height());
    float2 p = coord * texSize;

    float baseFreq = mix(2.4, 0.7, clamp(u.size, 0.0, 1.0));
    float n = grainNoiseFast(p, baseFreq, u.seed);

    const float3 w = float3(0.2126, 0.7152, 0.0722);
    float3 lin = srgbToLinearH(hs.rgb);
    float Y  = dot(lin, w);
    float Yp = clamp(Y + u.strength * n, 0.0, 1.0);
    float3 linOut = clamp(lin + (Yp - Y) * w, 0.0, 1.0);
    half3 srgbOut = linearToSrgbH(linOut);
    return float4((float3)srgbOut, (float)hs.a);
}

// ------------------------
// Vignette (Metal) Shader
// ------------------------
struct VignetteUniforms {
    float intensity; // 0..1
    float pad0;
    float pad1;
    float pad2; // 16-byte alignment
};

// Compute smooth cubic step from 0..1 (t*t*(3-2*t))
static inline float smoothCubic(float t) {
    t = clamp(t, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// ------------------------
// Duotone (Metal) Shader
// ------------------------
// Use only scalar floats to guarantee a tightly packed 48-byte layout (12 floats)
// to match the Swift-side Uniforms packing in DuotoneFilter.swift
struct DuotoneUniforms {
    float shadow_r; float shadow_g; float shadow_b; float intensity; // 16 bytes
    float highlight_r; float highlight_g; float highlight_b; float factor; // 16 bytes
    float gamma; float pad0; float pad1; float pad2; // 16 bytes
};

fragment float4 duotoneFragment(
    LumaGrainVertexOut inV                      [[ stage_in ]],
    texture2d<half, access::sample> inputImage  [[ texture(0) ]],
    constant DuotoneUniforms &u                 [[ buffer(0) ]]
) {
    constexpr sampler inputSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    half4 hs = inputImage.sample(inputSampler, inV.texCoord);

    // Work in linear
    float3 lin = srgbToLinearH(hs.rgb);
    float3 shadowLin    = srgbToLinearH(half3(u.shadow_r, u.shadow_g, u.shadow_b));
    float3 highlightLin = srgbToLinearH(half3(u.highlight_r, u.highlight_g, u.highlight_b));

    // Perceptual luminance
    const float3 w = float3(0.2126, 0.7152, 0.0722);
    float Y = clamp(dot(lin, w), 0.0, 1.0);
    float g = max(u.gamma, 0.01);
    float t = pow(Y, g);

    // Map luminance to gradient between shadow/highlight colors
    float3 dtLin = mix(shadowLin, highlightLin, t);
    float blend = clamp(u.intensity * u.factor, 0.0, 1.0);
    float3 outLin = mix(lin, dtLin, blend);

    half3 outSRGB = linearToSrgbH(outLin);
    return float4((float3)outSRGB, (float)hs.a);
}

// ------------------------
// Skin Tone Adjust (Metal) Shader
// Positive amount warms, negative cools, selectively on skin-like pixels.
// ------------------------
struct SkinToneUniforms {
    float amount;              // -1..1
    float softness;            // 0..1, edge softness around mask
    float highlightProtect;    // 0..1, reduce effect near highlights
    float saturationThreshold; // 0..1, ignore very desaturated
};

static inline float3 rgbToYCbCr601(float3 rgb) {
    // Assumes rgb is linear 0..1
    float Y  = dot(rgb, float3(0.299, 0.587, 0.114));
    float Cb = (rgb.b - Y) * 0.564 + 0.5;
    float Cr = (rgb.r - Y) * 0.713 + 0.5;
    return float3(Y, Cb, Cr);
}

fragment float4 skinToneFragment(
    LumaGrainVertexOut inV                      [[ stage_in ]],
    texture2d<half, access::sample> inputImage  [[ texture(0) ]],
    constant SkinToneUniforms &u                [[ buffer(0) ]]
) {
    constexpr sampler inputSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    half4 hs = inputImage.sample(inputSampler, inV.texCoord);
    float3 lin = srgbToLinearH(hs.rgb);

    // YCbCr mask for skin-like region (loose ellipse in CbCr space)
    float3 ycbcr = rgbToYCbCr601(lin);
    float Cb = ycbcr.y; float Cr = ycbcr.z;
    // Ellipse centered roughly at typical skin chroma (Cb~0.45, Cr~0.55)
    float2 d = float2((Cb - 0.45) / 0.18, (Cr - 0.55) / 0.12);
    float dist2 = dot(d, d);
    float maskEllipse = 1.0 - smoothstep(1.0 - 0.25 * u.softness, 1.0 + 0.25 * u.softness, dist2);

    // Gate by luminance and saturation to avoid highlights and grays
    const float3 w = float3(0.2126, 0.7152, 0.0722);
    float Y = clamp(dot(lin, w), 0.0, 1.0);
    float maxc = max(lin.r, max(lin.g, lin.b));
    float minc = min(lin.r, min(lin.g, lin.b));
    float sat = (maxc > 0.0) ? (maxc - minc) / maxc : 0.0;

    float maskSat = smoothstep(u.saturationThreshold, u.saturationThreshold + 0.15, sat);
    float highlightMask = 1.0 - smoothstep(0.8 - 0.2 * u.highlightProtect, 1.0, Y);

    float mask = clamp(maskEllipse * maskSat * highlightMask, 0.0, 1.0);

    // Temperature-like bias in linear space
    float amt = clamp(u.amount, -1.0, 1.0);
    float k = pow(abs(amt), 0.85);
    float3 biasWarm  = float3( 0.050,  0.020, -0.035) * k; // +R +G -B
    float3 biasCool  = float3(-0.030, -0.010,  0.045) * k; // -R -G +B
    float3 bias = (amt >= 0.0) ? biasWarm : biasCool;

    float3 outLin = clamp(lin + bias * mask, 0.0, 1.0);
    half3 outSRGB = linearToSrgbH(outLin);
    return float4((float3)outSRGB, (float)hs.a);
}

fragment float4 vignetteFragment(
    LumaGrainVertexOut inV                      [[ stage_in ]],
    texture2d<half, access::sample> inputImage  [[ texture(0) ]],
    constant VignetteUniforms &uv               [[ buffer(0) ]]
) {
    constexpr sampler inputSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 coord = inV.texCoord;
    half4 hs = inputImage.sample(inputSampler, coord);

    // Get image geometry
    float w = float(inputImage.get_width());
    float h = float(inputImage.get_height());
    float2 p = float2(coord.x * w, coord.y * h);
    float2 center = float2(w * 0.5, h * 0.5);

    // Intensity mapping matches previous CI implementation
    float v = clamp(uv.intensity, 0.0, 1.0);
    float outer = 0.5 * max(w, h);
    float innerRatio = 0.85 - 0.30 * v; // shrink inner as intensity grows
    float inner = max(1.0, outer * innerRatio);

    float d = length(p - center);
    float t = (d - inner) / max(outer - inner, 1.0);
    float a = smoothCubic(t); // 3t^2 - 2t^3

    // Global alpha scaling
    float edgeAlpha = 0.6 * pow(v, 0.88);
    float alpha = clamp(a * edgeAlpha, 0.0, 1.0);

    // Blend black overlay via source-over == multiply by (1 - alpha)
    half factor = half(1.0 - alpha);
    half3 rgb = hs.rgb * factor;
    return float4((float3)rgb, (float)hs.a);
}
