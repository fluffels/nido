#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding=0) uniform Uniform {
    mat4x4 ortho;
} uniforms;

layout(location=0) in vec3 inXYZ;
layout(location=1) in vec2 inUV;

layout(location=0) out vec2 outUV;

void main() {
    gl_Position = uniforms.ortho * vec4(inXYZ, 1.f);
    outUV = inUV;
}
