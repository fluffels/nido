#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding=1) uniform sampler2D colorMap;

layout(location=0) in vec2 inUV;

layout(location=0) out vec4 outColor;

void main() {
    outColor = texture(colorMap, inUV);
}
