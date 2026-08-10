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

float hash12(vec2 p) {
    p = fract(p * vec2(5.3983, 5.4427));
    p += dot(p.yx, p.xy + vec2(21.5351, 14.3137));
    return fract(p.x * p.y);
}

float swirlNoise(vec2 st, float spin) {
    float r = length(st);
    float a = atan(st.y, st.x) + spin;
    vec2 p = vec2(r * 10.0, a * 4.0);
    return hash12(floor(p)) * 0.5 + hash12(floor(p * 2.0)) * 0.5;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 st = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    vec3 col = vec3(0.0);
    
    // Tilted coordinate system for 3D accretion disk perspective
    vec2 diskSt = vec2(st.x, st.y * 2.8);
    float diskR = length(diskSt);
    float diskAngle = atan(diskSt.y, diskSt.x);
    
    // Event horizon radius
    float eventHorizon = 0.12 + uBass * 0.04;
    
    // 1. Accretion Disk Plasma Swirl
    if (diskR > eventHorizon * 0.8 && diskR < 0.65) {
        float spinSpeed = uTime * (1.5 + uEnergy * 2.5) + (1.0 / (diskR + 0.05)) * 0.5;
        float noisePattern = swirlNoise(diskSt, spinSpeed);
        
        float diskIntensity = exp(-abs(diskR - 0.28) * 8.0) * (0.5 + noisePattern * 0.8);
        
        // Temperature color gradient (white hot core to primary/amber edge)
        float temp = clamp((0.5 - diskR) * 3.0, 0.0, 1.0);
        vec3 diskColor = mix(uPrimaryColor, vec3(1.0, 0.75, 0.2), temp);
        diskColor = mix(diskColor, vec3(1.0, 0.95, 0.8), pow(temp, 3.0));
        
        col += diskColor * diskIntensity * (1.2 + uBass * 2.0 + uMid * 1.5);
    }
    
    // 2. Gravitational Lensing Photon Ring
    float lensingRing = exp(-abs(diskR - eventHorizon) * 35.0);
    vec3 lensColor = mix(vec3(0.3, 0.8, 1.0), uPrimaryColor, 0.5) * (2.0 + uTreble * 3.0);
    col += lensColor * lensingRing;
    
    // 3. Polar Relativistic Jets (Vertical Audio Beams on Bass)
    float jetWidth = 0.03 + uBass * 0.05;
    float jetDist = abs(st.x);
    if (jetDist < jetWidth * 2.5 && abs(st.y) > eventHorizon) {
        float jetIntensity = exp(-jetDist / jetWidth) * exp(-abs(st.y) * 1.5) * uBass * 2.5;
        vec3 jetColor = mix(vec3(0.2, 0.9, 1.0), uPrimaryColor, abs(st.y));
        // Jet pulse nodes
        float jetPulse = sin(abs(st.y) * 30.0 - uTime * 15.0) * 0.5 + 0.5;
        col += jetColor * jetIntensity * (0.8 + jetPulse * 0.8);
    }
    
    // 4. Black Hole Singularity Core (Absolute Darkness shadow)
    if (length(st) < eventHorizon) {
        col = vec3(0.0);
    }
    
    // Background star distortion
    float bgDist = length(st);
    if (bgDist > eventHorizon * 1.5) {
        float star = hash12(floor(st * 80.0));
        if (star > 0.98) {
            col += vec3(0.8, 0.9, 1.0) * (0.3 + uTreble * 1.5);
        }
    }
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
