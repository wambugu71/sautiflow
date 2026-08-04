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

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 4; i++) {
        v += a * hash(p);
        p = rot * p * 2.0 + vec2(100.0);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 st = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    float dist = length(st);
    
    // Cosmic nebula cloud density & motion
    vec2 q = vec2(fbm(st + vec2(uTime * 0.1, uTime * 0.15)), fbm(st + vec2(uTime * 0.2)));
    vec2 r = vec2(fbm(st + 4.0 * q + vec2(uTime * 0.2)), fbm(st + 4.0 * q + vec2(uTime * 0.1)));
    
    float f = fbm(st + 4.0 * r + vec2(uBass * 0.5));
    
    vec3 col = mix(uPrimaryColor, vec3(0.9, 0.2, 0.8), clamp(f * f * 4.0, 0.0, 1.0));
    col = mix(col, vec3(0.1, 0.9, 1.0), clamp(length(q), 0.0, 1.0));
    col = mix(col, vec3(1.0, 0.9, 0.4), clamp(length(r.x), 0.0, 1.0));
    
    col *= (f * f * f + 0.6 * f * f + 0.5 * f) * (1.0 + uBass * 2.5 + uEnergy * 1.5);
    
    // Glowing stars sparkling to treble
    float star = pow(hash(st * 50.0 + floor(uTime * 10.0)), 20.0) * uTreble;
    col += vec3(1.0) * star * 3.0;
    
    col *= smoothstep(1.3, 0.2, dist);
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
