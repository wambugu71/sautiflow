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

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float perlinNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
                   dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
               mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
                   dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 st = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    vec3 col = vec3(0.01, 0.02, 0.06);
    
    // Aurora Curtains Layering (3 organic plasma waves)
    for (int i = 1; i <= 4; i++) {
        float fi = float(i);
        
        float speed = uTime * (0.3 + fi * 0.15) * (1.0 + uBass * 0.8);
        float noiseVal = perlinNoise(vec2(st.x * (1.5 + fi * 0.5) + speed, st.y * 2.0 - speed * 0.5));
        
        // Dynamic wave baseline moving with audio
        float waveY = sin(st.x * (2.0 + fi * 0.8) + speed) * (0.15 + uBass * 0.25) 
                    + noiseVal * (0.1 + uMid * 0.2) 
                    + (fi - 2.5) * 0.18;
                    
        float distToWave = abs(st.y - waveY);
        
        // Vertical Ray/Curtain Texture
        float rayTexture = sin((st.x + noiseVal * 0.2) * (30.0 + fi * 10.0) + speed * 2.0) * 0.5 + 0.5;
        rayTexture = pow(rayTexture, 2.0);
        
        // Ribbon Falloff
        float intensity = exp(-distToWave * (8.0 - uBass * 4.0)) * (0.6 + rayTexture * 0.8);
        
        // Color gradient per layer
        vec3 auroraColor = mix(
            uPrimaryColor,
            vec3(0.1 + fi * 0.2, 0.95 - fi * 0.15, 0.85),
            sin(fi * 1.5 + uTime * 0.5) * 0.5 + 0.5
        );
        
        col += auroraColor * intensity * (1.0 + uEnergy * 1.5);
    }
    
    // Sparkling Cosmic Dust Particles on Treble
    float particleGrid = 40.0;
    vec2 pCell = floor(st * particleGrid);
    vec2 pSub = fract(st * particleGrid) - 0.5;
    float pHash = fract(sin(dot(pCell, vec2(12.9898, 78.233))) * 43758.5453);
    
    if (pHash > 0.92) {
        float pDist = length(pSub);
        float pSparkle = sin(uTime * 8.0 + pHash * 20.0) * 0.5 + 0.5;
        float particleGlow = exp(-pDist * 12.0) * pSparkle * (uTreble * 3.5 + 0.2);
        vec3 pColor = mix(vec3(1.0), uPrimaryColor, pHash);
        col += pColor * particleGlow;
    }
    
    // Ambient horizon glow
    col += uPrimaryColor * 0.06 * (1.0 - length(st));
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
