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
    
    float radius = length(st);
    float angle = atan(st.y, st.x);
    
    // Hyper-reactive tunnel speed & bass shockwave zoom
    float speed = uTime * (0.8 + uBass * 3.0 + uEnergy * 2.0);
    float tunnelZ = 1.0 / (radius + 0.02 + uBass * 0.05) + speed;
    
    // Audio-reactive ring distortion & spoke twist
    float rings = sin(tunnelZ * (10.0 + uMid * 15.0));
    float spokes = cos(angle * (6.0 + floor(uTreble * 6.0)) + sin(tunnelZ * 3.0 + uTime * 2.0));
    
    float pattern = smoothstep(0.05, 0.95, abs(rings * spokes));
    
    // Vibrant audio color blend
    vec3 baseColor = uPrimaryColor;
    vec3 accentColor = vec3(1.0 - baseColor.r, 0.3 + uTreble * 0.7, 0.2 + uBass * 0.8);
    
    vec3 col = mix(baseColor, accentColor, sin(tunnelZ * 0.8 + uTime) * 0.5 + 0.5);
    col *= pattern * (0.8 + uBass * 2.5 + uEnergy * 1.5);
    
    // Explosive core energy glow on bass drops
    float coreGlow = exp(-radius * (5.0 - uBass * 3.5));
    vec3 coreColor = mix(vec3(0.1, 0.9, 1.0), vec3(1.0, 0.2, 0.8), uBass);
    col += coreColor * coreGlow * (1.5 + uBass * 4.0 + uMid * 2.0);
    
    // High-frequency treble sparkles radiating outward
    float sparkles = pow(abs(sin(angle * 32.0 + uTime * 15.0)), 12.0) * uTreble;
    col += vec3(1.0, 0.95, 0.6) * sparkles * step(0.15, radius) * (1.0 + uTreble * 3.0);
    
    // Vignette
    col *= smoothstep(1.3, 0.2, radius);
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
