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

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 st = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    vec3 col = vec3(0.01, 0.02, 0.04);
    
    // Rotate coordinate system slightly
    float angle = 0.2;
    mat2 rotMat = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
    st = rotMat * st;
    
    float helixSpeed = uTime * (1.2 + uEnergy * 1.5);
    float freq = 8.0;
    float radius = 0.25 + uBass * 0.12;
    
    // Strand 1 and Strand 2 3D X positions along vertical Y axis
    float phase1 = st.y * freq + helixSpeed;
    float phase2 = phase1 + PI;
    
    float x1 = sin(phase1) * radius;
    float z1 = cos(phase1);
    
    float x2 = sin(phase2) * radius;
    float z2 = cos(phase2);
    
    // Strand glow lines
    float distStrand1 = abs(st.x - x1);
    float distStrand2 = abs(st.x - x2);
    
    // 3D Depth shading (closer strand is brighter)
    float depth1 = 0.5 + z1 * 0.5;
    float depth2 = 0.5 + z2 * 0.5;
    
    float glow1 = exp(-distStrand1 * (40.0 - uBass * 15.0)) * depth1;
    float glow2 = exp(-distStrand2 * (40.0 - uBass * 15.0)) * depth2;
    
    vec3 strandColor1 = mix(uPrimaryColor, vec3(0.1, 0.95, 0.7), depth1);
    vec3 strandColor2 = mix(uPrimaryColor, vec3(0.9, 0.2, 0.8), depth2);
    
    col += strandColor1 * glow1 * (1.2 + uBass * 2.0);
    col += strandColor2 * glow2 * (1.2 + uBass * 2.0);
    
    // Base Pair Rungs (Horizontal nucleotide cross-links)
    float rungInterval = 0.08;
    float rungIdx = floor(st.y / rungInterval);
    float rungY = (rungIdx + 0.5) * rungInterval;
    
    float rungPhase = rungY * freq + helixSpeed;
    float rungX1 = sin(rungPhase) * radius;
    float rungX2 = sin(rungPhase + PI) * radius;
    float minX = min(rungX1, rungX2);
    float maxX = max(rungX1, rungX2);
    
    if (abs(st.y - rungY) < 0.008 && st.x > minX && st.x < maxX) {
        float rungNoise = hash(rungIdx * 13.5);
        float rungGlow = (0.6 + rungNoise * 0.4) * (0.8 + uMid * 2.0);
        vec3 rungColor = mix(vec3(0.2, 0.85, 1.0), vec3(1.0, 0.8, 0.2), rungNoise);
        col += rungColor * rungGlow;
    }
    
    // Bioluminescent particles in background on Treble
    vec2 pGrid = floor(st * 30.0);
    float pHash = hash(pGrid.x * 50.0 + pGrid.y);
    if (pHash > 0.94) {
        vec2 pSub = fract(st * 30.0) - 0.5;
        float pDist = length(pSub);
        float pSparkle = sin(uTime * 6.0 + pHash * 30.0) * 0.5 + 0.5;
        float particleGlow = exp(-pDist * 14.0) * pSparkle * (0.2 + uTreble * 3.0);
        col += vec3(0.8, 1.0, 0.9) * particleGlow;
    }
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
