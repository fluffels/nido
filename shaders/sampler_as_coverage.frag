#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding=1) uniform sampler2D colorMap;

layout(location=0) in vec2 inUV;
layout(location=1) in vec3 inRGB;

layout(location=0) out vec4 outColor;

void main() {
    float alpha = texture(colorMap, inUV).r;
    outColor = vec4(inRGB, alpha);
}
