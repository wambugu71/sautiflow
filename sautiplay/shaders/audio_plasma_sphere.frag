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

vec2 hash(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
                   dot(hash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
               mix(dot(hash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
                   dot(hash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 st = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    float dist = length(st);
    float angle = atan(st.y, st.x);
    
    // Explosive radius pulsing with bass & overall audio energy
    float baseRadius = 0.30 + uBass * 0.35 + uEnergy * 0.15;
    
    // Dynamic turbulence surface noise morphing with mid & treble
    float surfaceNoise = noise(st * (5.0 + uMid * 5.0) + vec2(uTime * 1.5, uTime * 1.0)) * (0.08 + uMid * 0.25);
    float waveDistort = sin(angle * 12.0 + uTime * 6.0) * (0.03 + uTreble * 0.12);
    
    float sphereEdge = baseRadius + surfaceNoise + waveDistort;
    
    vec3 col = vec3(0.0);
    
    if (dist < sphereEdge) {
        float innerDist = dist / sphereEdge;
        float plasmaPattern = noise(st * 15.0 + vec2(uTime * 2.5));
        vec3 coreColor = mix(uPrimaryColor, vec3(1.0, 0.1 + uMid * 0.9, 0.8), innerDist);
        col = coreColor * (0.9 + plasmaPattern * 0.8) * (1.2 + uBass * 2.0);
    }
    
    // Intense audio-reactive glowing halo
    float halo = exp(-abs(dist - sphereEdge) * (20.0 - uBass * 12.0));
    vec3 haloColor = mix(uPrimaryColor, vec3(0.2, 0.95, 1.0), 0.5 + uTreble * 0.5);
    col += haloColor * halo * (1.2 + uBass * 3.0 + uTreble * 2.0);
    
    // Shockwave radial pulse on bass peaks
    float shockwave = exp(-abs(dist - (uTime * 2.0 - floor(uTime * 2.0))) * 10.0) * uBass;
    col += vec3(0.9, 0.4, 1.0) * shockwave * 0.5;
    
    col += uPrimaryColor * 0.08 * (1.0 - dist);
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
