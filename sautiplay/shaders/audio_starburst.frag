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
    
    float dist = length(st);
    float angle = atan(st.y, st.x);
    
    // Rotating starburst beams
    float rayCount = 12.0 + floor(uMid * 12.0);
    float beams = pow(abs(cos(angle * rayCount + uTime * 2.0)), 6.0);
    
    float burstRadius = 0.15 + uBass * 0.35;
    
    vec3 beamColor = mix(uPrimaryColor, vec3(1.0, 0.85, 0.2), sin(angle * 3.0 + uTime) * 0.5 + 0.5);
    vec3 col = beamColor * beams * (1.5 + uBass * 3.5 + uEnergy * 2.0) / (dist + 0.1);
    
    // Central core explosion
    float coreGlow = exp(-dist * (6.0 - uBass * 4.0));
    col += vec3(1.0, 0.95, 0.7) * coreGlow * (2.0 + uBass * 4.0);
    
    // Outer shockwave ring
    float shockwave = exp(-abs(dist - burstRadius) * (20.0 - uBass * 10.0));
    col += vec3(0.9, 0.2, 0.8) * shockwave * (1.5 + uTreble * 3.0);
    
    col *= smoothstep(1.3, 0.1, dist);
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
