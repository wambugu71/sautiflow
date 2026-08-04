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
    vec2 uv = fragCoord / uSize;
    vec2 st = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    // Wave 1: Bass heavy displacement
    float wave1 = sin(uv.x * 12.0 + uTime * 4.0) * (0.12 + uBass * 0.35);
    // Wave 2: Mid-range frequency modulation
    float wave2 = cos(uv.x * 28.0 - uTime * 6.0) * (0.06 + uMid * 0.20);
    // Wave 3: Treble ripple frequency
    float wave3 = sin(uv.x * 60.0 + uTime * 12.0) * (0.03 + uTreble * 0.12);
    
    float waveCenter = 0.5 + wave1 + wave2 + wave3;
    float distToWave = abs(uv.y - waveCenter);
    
    // Intense glowing neon wave stroke
    float waveGlow = exp(-distToWave * (40.0 - uBass * 25.0));
    vec3 waveColor = mix(uPrimaryColor, vec3(0.1, 0.95, 1.0), sin(uv.x * 6.28 + uTime * 2.0) * 0.5 + 0.5);
    
    vec3 col = waveColor * waveGlow * (1.8 + uBass * 3.5 + uEnergy * 2.0);
    
    // Liquid fill glow below the wave line
    if (uv.y < waveCenter) {
        float depth = (waveCenter - uv.y) / waveCenter;
        vec3 fillColor = mix(uPrimaryColor * 0.8, vec3(0.9, 0.2, 0.8), depth);
        col += fillColor * (0.6 + uMid * 1.5 + uBass * 1.0) * (1.0 - depth * 0.8);
    }
    
    // Floating audio-reactive spectrum particles
    vec2 gridSt = uv * vec2(40.0, 20.0);
    vec2 gridCell = fract(gridSt) - 0.5;
    float dotDist = length(gridCell);
    float dotGlow = smoothstep(0.20 + uTreble * 0.2, 0.0, dotDist);
    
    col += vec3(0.9, 0.95, 1.0) * dotGlow * 0.4 * (1.0 + uTreble * 4.0 + uEnergy * 2.0);
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
