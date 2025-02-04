#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding = 0) uniform sampler2D colorMap;
struct BokehSettings {
    float radius;
    float blurScale;
    float threshold;
    int samples;
} settings;

layout(location = 0) in vec2 inUV;
layout(location = 0) out vec4 outColor;

const float PI = 3.14159265359;
// NOTE(jan): PI * (3.0 - sqrt(5.0))
const float GOLDEN_ANGLE = 2.39996323; 

// Helper function to get sample position in a spiral pattern
vec2 getSamplePosition(float index, float total) {
    float r = sqrt(index / total);
    float theta = index * GOLDEN_ANGLE;
    
    return vec2(
        r * cos(theta),
        r * sin(theta)
    );
}

// Helper function to calculate sample weight based on brightness
float getBokehWeight(vec4 color) {
    float brightness = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    return max(0.0, brightness - settings.threshold);
}

void main() {
    vec4 totalColor = vec4(0.0);
    float totalWeight = 0.0;

    // settings.radius = 0.5;
    // settings.samples = 128;
    // settings.blurScale = 5.0;
    // settings.threshold = 100.0;
    
    // Sample in a spiral pattern
    for(int i = 0; i < settings.samples; i++) {
        vec2 offset = getSamplePosition(float(i), float(settings.samples));
        vec2 sampleUV = inUV + (offset * settings.radius / textureSize(colorMap, 0));
        
        vec4 sampleColor = texture(colorMap, sampleUV);
        float weight = 1.0;
        
        // Apply bokeh weighting based on brightness
        if (settings.blurScale > 0.0) {
            weight += getBokehWeight(sampleColor) * settings.blurScale;
        }
        
        totalColor += sampleColor * weight;
        totalWeight += weight;
    }
    
    // Normalize the result
    outColor = totalColor / totalWeight;
    
    // Apply gamma correction to maintain proper brightness
    outColor.rgb = pow(outColor.rgb, vec3(1.0 / 2.2));
}
