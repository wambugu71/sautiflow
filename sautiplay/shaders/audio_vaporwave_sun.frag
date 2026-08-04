#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uBass;
uniform float uMid;
uniform float uTreble;
uniform float uEnergy;
uniform vec3 uPrimaryColor;

out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 st = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    // Vaporwave sun center
    vec2 sunCenter = vec2(0.0, 0.05);
    float distToSun = length(st - sunCenter);
    
    float sunRadius = 0.30 + uBass * 0.12;
    vec3 col = vec3(0.0);
    
    if (distToSun < sunRadius) {
        // Gradient sun fill (yellow to magenta)
        float sunY = (st.y - sunCenter.y + sunRadius) / (sunRadius * 2.0);
        vec3 sunCol = mix(vec3(1.0, 0.9, 0.1), vec3(1.0, 0.1, 0.6), sunY);
        
        // Horizontal cut lines (vaporwave stripes) pulsing with mid & treble
        float stripePattern = sin((st.y - uTime * 0.1) * (40.0 + uMid * 20.0));
        if (st.y < sunCenter.y && stripePattern > 0.3) {
            col = vec3(0.05, 0.02, 0.1);
        } else {
            col = sunCol * (1.2 + uBass * 1.5);
        }
    }
    
    // Outer atmospheric glow
    float sunGlow = exp(-abs(distToSun - sunRadius) * (15.0 - uBass * 8.0));
    col += mix(vec3(1.0, 0.2, 0.7), uPrimaryColor, 0.5) * sunGlow * (1.2 + uBass * 2.0 + uTreble * 1.5);
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
