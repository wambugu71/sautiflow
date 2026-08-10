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

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

float buildingHeight(float id) {
    float h = hash(id * 17.13);
    float audioFactor = mix(uBass, mix(uMid, uTreble, hash(id * 3.1)), hash(id * 7.7));
    return 0.12 + h * 0.32 + audioFactor * 0.42;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 st = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    vec3 finalColor = vec3(0.02, 0.01, 0.05);
    
    float horizon = -0.08;
    
    // Retro Neon Sun
    vec2 sunPos = vec2(0.0, 0.18);
    float distSun = length(st - sunPos);
    float sunRadius = 0.22 + uBass * 0.06;
    
    if (distSun < sunRadius) {
        float sunY = (st.y - sunPos.y + sunRadius) / (2.0 * sunRadius);
        // Horizontal cutouts
        float stripe = sin((sunY - uTime * 0.1) * 40.0);
        if (stripe > 0.1 || sunY > 0.6) {
            vec3 sunColor = mix(vec3(1.0, 0.1, 0.5), vec3(1.0, 0.85, 0.1), sunY);
            sunColor += uPrimaryColor * 0.3;
            finalColor = sunColor * (1.2 + uBass * 1.5);
        }
    }
    
    // Sun Glow
    float sunGlow = exp(-distSun * 4.0);
    finalColor += mix(vec3(1.0, 0.2, 0.6), uPrimaryColor, 0.5) * sunGlow * (0.8 + uEnergy * 1.2);
    
    // Skyline Skyscrapers
    float numBuildings = 24.0;
    float bIdx = floor((st.x + 1.2) * 10.0);
    float bX = fract((st.x + 1.2) * 10.0);
    
    if (st.y > horizon) {
        float h = buildingHeight(bIdx);
        if (st.y < horizon + h && bX > 0.08 && bX < 0.92) {
            vec3 buildingColor = vec3(0.05, 0.04, 0.1);
            // Window lights
            vec2 winGrid = vec2(floor(bX * 8.0), floor((st.y - horizon) * 35.0));
            float winLit = hash(bIdx * 100.0 + winGrid.x * 10.0 + winGrid.y);
            if (winLit > 0.4) {
                buildingColor += mix(vec3(0.1, 0.8, 1.0), uPrimaryColor, hash(winGrid.y)) * (0.6 + uMid * 1.8);
            }
            // Neon roof outline
            if (st.y > horizon + h - 0.015) {
                buildingColor += uPrimaryColor * 2.5 * (1.0 + uTreble * 2.0);
            }
            finalColor = buildingColor;
        }
    }
    
    // 3D Perspective Synthwave Ground Grid
    if (st.y <= horizon) {
        float pDepth = 1.0 / (horizon - st.y + 0.001);
        vec2 gridUv = vec2(st.x * pDepth * 0.8, pDepth * 0.25 + uTime * (1.2 + uBass * 2.0));
        
        // Anti-aliased grid lines without fwidth (Flutter GLSL runtime safe)
        vec2 g = abs(fract(gridUv - 0.5) - 0.5);
        float line = min(g.x, g.y);
        float gridIntensity = smoothstep(0.04, 0.0, line);
        
        float fade = exp(-(horizon - st.y) * 6.0);
        vec3 gridColor = mix(uPrimaryColor, vec3(0.9, 0.1, 0.9), sin(pDepth * 0.1 + uTime) * 0.5 + 0.5);
        finalColor += gridColor * gridIntensity * fade * (1.0 + uBass * 2.5);
        
        // Wet reflections on ground
        float reflY = horizon + (horizon - st.y);
        float reflSunDist = length(vec2(st.x * 0.7, reflY) - sunPos);
        if (reflSunDist < sunRadius * 1.2) {
            float reflGlow = exp(-reflSunDist * 3.0) * (0.3 + uBass * 0.7);
            finalColor += vec3(1.0, 0.3, 0.7) * reflGlow * fade;
        }
    }
    
    // Ambient stars
    if (st.y > horizon + 0.25) {
        float starHash = hash(floor(st.x * 120.0) + floor(st.y * 120.0) * 100.0);
        if (starHash > 0.985) {
            float twinkle = sin(uTime * 5.0 + starHash * 10.0) * 0.5 + 0.5;
            finalColor += vec3(0.9, 0.95, 1.0) * twinkle * (0.5 + uTreble * 2.0);
        }
    }
    
    fragColor = vec4(clamp(finalColor, 0.0, 1.0), 1.0);
}
