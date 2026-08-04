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
    
    // Bioluminescent ocean ripple rings expanding outward
    float ripple1 = sin(dist * (25.0 - uBass * 10.0) - uTime * 4.0);
    float ripple2 = cos(dist * (40.0 - uMid * 15.0) + uTime * 6.0);
    
    float wavePattern = smoothstep(0.1, 0.9, abs(ripple1 * ripple2));
    
    vec3 bioColor = mix(vec3(0.0, 0.85, 0.9), uPrimaryColor, sin(dist * 5.0 + uTime) * 0.5 + 0.5);
    vec3 col = bioColor * wavePattern * (0.8 + uBass * 2.5 + uEnergy * 1.5);
    
    // Bioluminescent sparkling plankton dots
    vec2 sparkSt = st * 35.0;
    vec2 sparkGrid = fract(sparkSt) - 0.5;
    float sparkDist = length(sparkGrid);
    float sparkGlow = smoothstep(0.18 + uTreble * 0.15, 0.0, sparkDist);
    col += vec3(0.4, 0.95, 1.0) * sparkGlow * (1.0 + uTreble * 4.0);
    
    col *= smoothstep(1.3, 0.1, dist);
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
