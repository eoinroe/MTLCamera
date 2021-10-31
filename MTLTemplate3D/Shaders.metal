//
//  Shaders.metal
//  TemplateTest
//
//  Created by Eoin Roe on 27/10/2021.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

enum {
    VertexAttributePosition,
    VertexAttributeTexcoord
};

enum {
    BufferIndexMeshPositions,
    BufferIndexMeshGenerics,
    BufferIndexUniforms
};

enum {
    TextureIndexColor
};

struct Uniforms {
    float4x4 projectionMatrix;
    float4x4 modelViewMatrix;
};

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]])
{
    ColorInOut out;

    float4 position = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * position;
    out.texCoord = in.texCoord;

    return out;
}

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                               texture2d<half> colorMap     [[ texture(TextureIndexColor) ]])
{
    /*
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    half4 colorSample   = colorMap.sample(colorSampler, in.texCoord.xy);
    return float4(colorSample);
     */
    
    float2 uv = in.texCoord.xy;
    
    // float r = uv.x;
    // float g = 1.0 - uv.y;
    // float b = 1.0 - uv.x;
    //
    // return float4(r*r, g*g, b*b, 1.0);
    
    float3 color = mix(mix(float3(0, 0, 1), float3(1, 0, 0), uv.x), float3(0, 1, 0), uv.y);
    return float4(color, 1.0);
}
