import Foundation

enum FramePipelineShaders {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct EnhanceUniforms {
    float spatial;  
    float noise;   
    float chroma;    
    float sharpen;  
    float coring;    
};

kernel void enhance(texture2d<float, access::read> input [[texture(0)]],
                    texture2d<float, access::write> output [[texture(1)]],
                    constant EnhanceUniforms &u [[buffer(0)]],
                    uint2 gid [[thread_position_in_grid]]) {
    uint w = output.get_width(), h = output.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float3 c = input.read(gid).rgb;
    float y = dot(c, kLuma);
    float2 chroma = float2(c.b - y, c.r - y);

    float sigma = 0.015 + 0.06 * u.noise;
    float gaussSum = 0.0, yGauss = 0.0, yBilateral = 0.0, bilateralSum = 0.0;
    float2 chromaGauss = float2(0.0);
    int2 maxP = int2(w - 1, h - 1);
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int2 q = clamp(int2(gid) + int2(dx, dy), int2(0), maxP);
            float3 n = input.read(uint2(q)).rgb;
            float ny = dot(n, kLuma);
            float g = exp(-float(dx * dx + dy * dy) / 2.0);                   
            float r = exp(-((ny - y) * (ny - y)) / (2.0 * sigma * sigma));  
            gaussSum += g;
            yGauss += ny * g;
            chromaGauss += float2(n.b - ny, n.r - ny) * g;
            yBilateral += ny * g * r;
            bilateralSum += g * r;
        }
    }

    float detail = y - yGauss / gaussSum;                                    
    chroma = mix(chroma, chromaGauss / gaussSum, max(u.chroma, u.spatial));  
    y = mix(y, yBilateral / bilateralSum, u.spatial * (0.25 + 0.75 * u.noise)); 
    if (u.sharpen > 0.001) {
        y += u.sharpen * sign(detail) * max(abs(detail) - u.coring, 0.0);    
    }

    float r = y + chroma.y;
    float b = y + chroma.x;
    float g = (y - 0.2126 * r - 0.0722 * b) / 0.7152;
    output.write(float4(saturate(float3(r, g, b)), 1.0), gid);
}
"""#
}
