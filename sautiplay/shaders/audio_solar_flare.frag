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
    
    float sunRadius = 0.28 + uBass * 0.15;
    
    // Coronal solar prominence rays
    float rays = sin(angle * 16.0 + uTime * 3.0) * cos(angle * 8.0 - uTime * 2.0);
    float rayLength = sunRadius + (0.10 + uMid * 0.25 + rays * 0.08);
    
    float coronaGlow = exp(-abs(dist - rayLength) * (18.0 - uBass * 10.0));
    
    vec3 sunColor = vec3(1.0, 0.4 + uMid * 0.5, 0.1);
    vec3 coronaColor = mix(uPrimaryColor, vec3(1.0, 0.8, 0.2), sin(angle * 4.0 + uTime) * 0.5 + 0.5);
    
    vec3 col = vec3(0.0);
    if (dist < sunRadius) {
        // Eclipse dark core with inner corona glow
        col = uPrimaryColor * 0.2 * (dist / sunRadius);
    }
    
    col += coronaColor * coronaGlow * (1.5 + uBass * 3.0 + uTreble * 2.0);
    
    // Solar flare arcs
    float flareArc = pow(abs(sin(angle * 6.0 + uTime * 4.0)), 12.0) * uTreble;
    col += vec3(1.0, 0.9, 0.5) * flareArc * smoothstep(sunRadius, sunRadius + 0.3, dist);
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
