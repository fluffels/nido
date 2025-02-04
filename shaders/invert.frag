#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding = 0) uniform sampler2D colorMap;
layout(location = 0) in vec2 inUV;
layout(location = 0) out vec4 outColor;

void main() {
    vec4 color = texture(colorMap, inUV);
    vec3 inverted = vec3(1.0) - color.rgb;
    outColor = vec4(inverted, color.a);
}
