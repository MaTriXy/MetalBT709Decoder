/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal shaders used for this sample
*/

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "AAPLShaderTypes.h"

// Vertex shader outputs and per-fragment inputs. Includes clip-space position and vertex outputs
//  interpolated by rasterizer and fed to each fragment generated by clip-space primitives.
typedef struct
{
    // The [[position]] attribute qualifier of this member indicates this value is the clip space
    //   position of the vertex wen this structure is returned from the vertex shader
    float4 clipSpacePosition [[position]];

    // Since this member does not have a special attribute qualifier, the rasterizer will
    //   interpolate its value with values of other vertices making up the triangle and
    //   pass that interpolated value to the fragment shader for each fragment in that triangle;
    float2 textureCoordinate;

} RasterizerData;

// Vertex Function that renders full screen flipped texture

vertex RasterizerData
identityVertexShader(uint vertexID [[ vertex_id ]],
             constant AAPLVertex *vertexArray [[ buffer(AAPLVertexInputIndexVertices) ]])
{
  RasterizerData out;
  
  // Index into our array of positions to get the current vertex
  //   Our positons are specified in pixel dimensions (i.e. a value of 100 is 100 pixels from
  //   the origin)
  float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
  
  // THe output position of every vertex shader is in clip space (also known as normalized device
  //   coordinate space, or NDC).   A value of (-1.0, -1.0) in clip-space represents the
  //   lower-left corner of the viewport wheras (1.0, 1.0) represents the upper-right corner of
  //   the viewport.
  
  out.clipSpacePosition.xy = pixelSpacePosition;
  
  // Set the z component of our clip space position 0 (since we're only rendering in
  //   2-Dimensions for this sample)
  out.clipSpacePosition.z = 0.0;
  
  // Set the w component to 1.0 since we don't need a perspective divide, which is also not
  //   necessary when rendering in 2-Dimensions
  out.clipSpacePosition.w = 1.0;
  
  // Pass our input textureCoordinate straight to our output RasterizerData.  This value will be
  //   interpolated with the other textureCoordinate values in the vertices that make up the
  //   triangle.
  out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
  out.textureCoordinate.y = 1.0 - out.textureCoordinate.y;
  
  return out;
}


// Fragment shader that can do simple rescale, note that the input
// and output if float here as opposed to half to support 16 bit
// float input texture.

fragment float4
samplingShader(RasterizerData in [[stage_in]],
               texture2d<float, access::sample> colorTexture [[ texture(AAPLTextureIndexBaseColor) ]])
{
  constexpr sampler textureSampler (mag_filter::linear,
                                    min_filter::linear);
  
  // Sample the texture to obtain a color
  const float4 colorSample = colorTexture.sample(textureSampler, in.textureCoordinate);
  
  // We return the color of the texture
  return colorSample;
}

// BT.709 rendering fragment shader

// FIXME: note that Metal "fast math" option would automatically
// replace pow() with exp2(y * log2(x))

static inline
float BT709_nonLinearNormToLinear(float normV) {
  
  if (normV < 0.081f) {
    normV *= (1.0f / 4.5f);
  } else {
    const float a = 0.099f;
    const float gamma = 1.0f / 0.45f; // 2.2
    normV = (normV + a) * (1.0f / (1.0f + a));
    normV = pow(normV, gamma);
  }
  
  return normV;
}

// Convert a non-linear log value to a linear value.
// Note that normV must be normalized in the range [0.0 1.0].

static inline
float sRGB_nonLinearNormToLinear(float normV)
{
  if (normV <= 0.04045f) {
    normV *= (1.0f / 12.92f);
  } else {
    const float a = 0.055f;
    const float gamma = 2.4f;
    //const float gamma = 1.0f / (1.0f / 2.4f);
    normV = (normV + a) * (1.0f / (1.0f + a));
    normV = pow(normV, gamma);
  }
  
  return normV;
}

//#define APPLE_GAMMA_ADJUST_BOOST_LINEAR (1.0f / 0.8782f) // aka 1.1386
//
//static inline
//float AppleGamma196_unboost_linearNorm(float normV) {
//  const float gamma = APPLE_GAMMA_ADJUST_BOOST_LINEAR;
//  normV = pow(normV, gamma);
//  return normV;
//}

/*

#define BT709_G22_GAMMA 2.2177f

static inline
float BT709_G22_nonLinearNormToLinear(float normV) {
  const float gamma = BT709_G22_GAMMA;
  normV = pow(normV, gamma);
  return normV;
}

*/

/*

// Undo a boost to sRGB values by applying a 2.2 like gamma.
// This should return a sRGB boosted value to linear when
// a 2.2 monitor gamma is applied.
//
// Note that converting from non-linear to linear
// with a form like pow(x, Gamma) will reduce the signal strength.

#define BT709_B22_GAMMA 2.233f
#define BT709_B22_MULT (1.0f / 0.08365f) // about 11.95

static inline
float BT709_B22_nonLinearNormToLinear(float normV) {
  const float xCrossing = 0.13369f;
  
  if (normV < xCrossing) {
    normV *= (1.0f / BT709_B22_MULT);
  } else {
    const float gamma = BT709_B22_GAMMA;
    normV = pow(normV, gamma);
  }
  
  return normV;
}

*/

/*

#define BT709_B22_GAMMA 2.233f
#define BT709_B22_MULT 9.05f

// f1 = x / BT709_B22_MULT
// f2 = pow(x, 2.233)
// intercept = ( 0.16754, 0.01851 )

static inline
float BT709_B22_nonLinearNormToLinear(float normV) {
  const float xCrossing = 0.16754f;
  
  if (normV < xCrossing) {
    normV *= (1.0f / BT709_B22_MULT);
  } else {
    const float gamma = BT709_B22_GAMMA;
    normV = pow(normV, gamma);
  }
  
  return normV;
}

*/
 
// Extract common BT.709 decode logic from the 2 implementations

static inline
float4 BT709_decode(const float Y, const float Cb, const float Cr) {
  const bool applyGammaMap = true;
  
  // Y already normalized to range [0 255]
  //
  // Note that the matrix multiply will adjust
  // this byte normalized range to account for
  // the limited range [16 235]
  //
  // Note that while a half float can be read from
  // the input textures, the values need to be full float
  // from this point forward since the bias values
  // need to be precise to avoid togggling blue and green
  // values depending on rounding.
  
  float Yn = (Y - (16.0f/255.0f));
  
  // Normalize Cb and CR with zero at 128 and range [0 255]
  // Note that matrix will adjust to limited range [16 240]
  
  float Cbn = (Cb - (128.0f/255.0f));
  float Crn = (Cr - (128.0f/255.0f));
  
  // Zero out the UV colors
  //Cbn = 0.0h;
  //Crn = 0.0h;
  
  // Represent half values as full precision float
  float3 YCbCr = float3(Yn, Cbn, Crn);
  
  // BT.709 (HDTV)
  // (col0) (col1) (col2)
  //
  // 1.1644  0.0000  1.7927
  // 1.1644 -0.2132 -0.5329
  // 1.1644  2.1124  0.0000
  
  // precise to 4 decimal places
  
  const float3x3 kColorConversion709 = float3x3(
                                                // column 0
                                                float3(1.1644f, 1.1644f, 1.1644f),
                                                // column 1
                                                float3(0.0f, -0.2132f, 2.1124f),
                                                // column 2
                                                float3(1.7927f, -0.5329f, 0.0f));
  
  // matrix to vector mult
  float3 rgb = kColorConversion709 * YCbCr;
  
  //  float Rn = (Yn * BT709Mat[0]) + (Cbn * BT709Mat[1]) + (Crn * BT709Mat[2]);
  //  float Gn = (Yn * BT709Mat[3]) + (Cbn * BT709Mat[4]) + (Crn * BT709Mat[5]);
  //  float Bn = (Yn * BT709Mat[6]) + (Cbn * BT709Mat[7]) + (Crn * BT709Mat[8]);
  
  //  float3 rgb;
  //  rgb.r = (YCbCr[0] * kColorConversion709[0][0]) + (YCbCr[1] * kColorConversion709[1][0]) + (YCbCr[2] * kColorConversion709[2][0]);
  //  rgb.g = (YCbCr[0] * kColorConversion709[0][1]) + (YCbCr[1] * kColorConversion709[1][1]) + (YCbCr[2] * kColorConversion709[2][1]);
  //  rgb.b = (YCbCr[0] * kColorConversion709[0][2]) + (YCbCr[1] * kColorConversion709[1][2]) + (YCbCr[2] * kColorConversion709[2][2]);
  
  rgb = saturate(rgb);
  
  // Note that application of this call to pow() and the if branch
  // has very little performance impact on iOS with an A9 chip.
  // The whole process seems to be IO bound and the resize render
  // takes just as much time as the original calculation, so optimization
  // that would only do 1 step in the exact render size would be the
  // most useful optimization.
  
  if (applyGammaMap) {
    // Convert sRGB to linear
    
//    rgb.r = sRGB_nonLinearNormToLinear(rgb.r);
//    rgb.g = sRGB_nonLinearNormToLinear(rgb.g);
//    rgb.b = sRGB_nonLinearNormToLinear(rgb.b);
    
    // Convert BT.709 to linear
    
    rgb.r = BT709_nonLinearNormToLinear(rgb.r);
    rgb.g = BT709_nonLinearNormToLinear(rgb.g);
    rgb.b = BT709_nonLinearNormToLinear(rgb.b);
  }
  
  float4 pixel = float4(rgb.r, rgb.g, rgb.b, 1.0);
  return pixel;
}

fragment float4
BT709ToLinearSRGBFragment(RasterizerData in [[stage_in]],
                          texture2d<half, access::sample>  inYTexture  [[texture(AAPLTextureIndexYPlane)]],
                          texture2d<half, access::sample>  inUVTexture [[texture(AAPLTextureIndexCbCrPlane)]]
                          )
{
  constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
  
  float Y = float(inYTexture.sample(textureSampler, in.textureCoordinate).r);
  half2 uvSamples = inUVTexture.sample(textureSampler, in.textureCoordinate).rg;
  
  float Cb = float(uvSamples[0]);
  float Cr = float(uvSamples[1]);
  
  return BT709_decode(Y, Cb, Cr);
}

// Colorspace conversion compute kernel. Note that inTexture and outTexture
// must be the same dimensions.

kernel void
BT709ToLinearSRGBKernel(texture2d<half, access::read>  inYTexture  [[texture(0)]],
                        texture2d<half, access::read>  inUVTexture [[texture(1)]],
                        texture2d<float, access::write> outTexture  [[texture(2)]],
                        ushort2                         gid         [[thread_position_in_grid]])
{
  // Check if the pixel is within the bounds of the output texture
  if((gid.x >= outTexture.get_width()) || (gid.y >= outTexture.get_height()))
  {
    // Return early if the pixel is out of bounds
    return;
  }
  
  float Y = float(inYTexture.read(gid).r);
  half2 uvSamples = inUVTexture.read(gid/2).rg;
  float Cb = float(uvSamples[0]);
  float Cr = float(uvSamples[1]);
  
  float4 pixel = BT709_decode(Y, Cb, Cr);
  outTexture.write(pixel, gid);
}

