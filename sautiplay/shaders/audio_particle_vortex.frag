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

const float PI = 3.14159265359;

float hash12(vec2 p) {
    p = fract(p * vec2(5.3983, 5.4427));
    p += dot(p.yx, p.xy + vec2(21.5351, 14.3137));
    return fract(p.x * p.y);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 st = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    float r = length(st);
    float a = atan(st.y, st.x);
    
    vec3 col = vec3(0.01, 0.01, 0.03);
    
    // 3D Perspective Tunnel Warp UV
    float z = 1.0 / (r + 0.04);
    
    // Spiral twisting angle driven by uMid
    float spiralA = a + z * 0.1 * sin(uTime * 0.5);
    
    // High-speed forward movement accelerating with uBass
    float forwardSpeed = uTime * (2.5 + uBass * 7.0);
    vec2 tunnelUv = vec2((spiralA / (2.0 * PI)) * 16.0, z * 0.4 - forwardSpeed);
    
    // Tunnel Energy Filaments
    vec2 cell = floor(tunnelUv);
    vec2 fSub = fract(tunnelUv) - 0.5;
    
    float cellHash = hash12(cell);
    if (cellHash > 0.45) {
        float filamentWidth = 0.08 + cellHash * 0.1;
        float lineDist = abs(fSub.x);
        float lineGlow = exp(-lineDist / filamentWidth);
        
        vec3 filamentColor = mix(
            uPrimaryColor,
            vec3(0.1, 0.9, 1.0),
            sin(cellHash * 10.0 + uTime * 2.0) * 0.5 + 0.5
        );
        
        // Intensity falloff with depth z
        float depthFade = min(1.0, r * 2.5);
        col += filamentColor * lineGlow * depthFade * (0.8 + uMid * 1.5);
    }
    
    // Stargate Spark Particles on Treble
    if (cellHash > 0.88) {
        float pDist = length(fSub);
        float pSparkle = sin(uTime * 10.0 + cellHash * 50.0) * 0.5 + 0.5;
        float particleGlow = exp(-pDist * 10.0) * pSparkle * (0.4 + uTreble * 4.0);
        col += vec3(1.0, 0.95, 0.8) * particleGlow;
    }
    
    // Stargate Horizon Central Glow (Vanishing Point Bloom)
    float centerGlow = exp(-r * (6.0 - uBass * 3.0));
    vec3 coreColor = mix(vec3(1.0, 0.8, 0.3), uPrimaryColor, 0.4);
    col += coreColor * centerGlow * (1.5 + uBass * 3.5);
    
    // Chromatic ring shockwave on heavy bass drops
    float shockRing = exp(-abs(r - (fract(uTime * 1.5) * 0.6)) * 25.0) * uBass;
    col += vec3(0.9, 0.2, 1.0) * shockRing * 0.8;
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
