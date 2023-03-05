#version 450
#extension GL_ARB_separate_shader_objects : enable

#include "uniforms.glsl"

layout(location=0) in vec3 inXYZ;
layout(location=1) in vec2 inUV;
layout(location=2) in vec4 inRGBA;

layout(location=0) out vec2 outUV;
layout(location=1) out vec4 outRGBA;

void main() {
    gl_Position = uniforms.mvp * vec4(inXYZ, 1.f);
    outUV = inUV;
    outRGBA = inRGBA;
}
