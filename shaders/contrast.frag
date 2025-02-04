#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding = 0) uniform sampler2D colorMap;
layout(location = 0) in vec2 inUV;
layout(location = 0) out vec4 outColor;

void main() {
    vec4 color = texture(colorMap, inUV);
    
    const float contrast = 1.5;
    const float midpoint = 0.5;
    
    vec3 contrasted = (color.rgb - midpoint) * contrast + midpoint;
    outColor = vec4(clamp(contrasted, 0.0, 1.0), color.a);
}
