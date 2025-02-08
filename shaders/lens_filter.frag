#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding = 0) uniform sampler2D colorMap;
layout(location = 0) in vec2 inUV;
layout(location = 0) out vec4 outColor;

const float samples = 150;
const float pi = 4.*atan(1.);
const float ang = (3.-sqrt(5.))*pi;
const float gamma = 1.8;

void main() {
    vec3 color = vec3(0.0);
    float radius = 0.011;
    
    for(int i = 0; i < samples; i++) {
        float d = float(i) / float(samples);
        vec2 offset = vec2(sin(ang * i), cos(ang * i)) * sqrt(d) * radius;
        
        vec3 col = texture(colorMap, inUV + offset).rgb;
        col = pow(col, vec3(gamma));
        
        color += col;
    }
    
    color = pow(color/float(samples), vec3(1.0/gamma));
    outColor = vec4(color, 1.0);
}
