#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding = 0) uniform sampler2D colorMap;
layout(location = 0) in vec2 inUV;
layout(location = 0) out vec4 outColor;

void main() {
    vec4 color = texture(colorMap, inUV);
    
    // NOTE(jan): Convert to grayscale using luminance weights.
    float gray = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    
    outColor = vec4(gray, gray, gray, color.a);
}
