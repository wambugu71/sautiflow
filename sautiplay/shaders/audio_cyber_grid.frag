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
    vec2 uv = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    // Horizon line
    float horizonY = -0.1 + uBass * 0.1;
    
    vec3 col = vec3(0.0);
    
    if (uv.y < horizonY) {
        // 3D Perspective grid projection
        float z = 0.4 / (horizonY - uv.y);
        vec2 gridUv = vec2(uv.x * z, z + uTime * (1.0 + uBass * 2.0));
        
        // Grid line calculation
        vec2 gridLines = abs(fract(gridUv - 0.5) - 0.5) / fwidth(gridUv);
        float line = min(gridLines.x, gridLines.y);
        float gridIntensity = 1.0 - min(line, 1.0);
        
        // Grid elevation wave pulsing with bass & mid
        float gridWave = sin(gridUv.x * 4.0 + uTime * 3.0) * uBass * 0.5;
        
        vec3 gridColor = mix(uPrimaryColor, vec3(1.0, 0.2, 0.8), sin(z * 0.2) * 0.5 + 0.5);
        col = gridColor * gridIntensity * (1.0 + uBass * 2.0) * exp(-z * 0.15);
    } else {
        // Retro neon sky with pulsing ambient glow
        float skyDist = uv.y - horizonY;
        col = uPrimaryColor * (0.3 / (skyDist + 0.2)) * (0.8 + uMid * 1.5);
        
        // Sun outline on horizon
        vec2 sunPos = vec2(0.0, horizonY + 0.2);
        float sunDist = length(uv - sunPos);
        if (sunDist < 0.25 + uBass * 0.08) {
            vec3 sunCol = mix(vec3(1.0, 0.8, 0.1), vec3(1.0, 0.1, 0.6), (uv.y - horizonY) / 0.3);
            col = mix(col, sunCol * (1.2 + uBass * 1.5), 0.85);
        }
    }
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
