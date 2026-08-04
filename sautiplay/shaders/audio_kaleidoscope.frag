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
    
    float r = length(st);
    float a = atan(st.y, st.x);
    
    // 8-fold rotational symmetry kaleidoscope
    float N = 8.0;
    a = mod(a, 6.28318 / N);
    a = abs(a - 3.14159 / N);
    
    vec2 kSt = vec2(cos(a), sin(a)) * r;
    
    // Geometry warping driven by audio
    float pattern1 = sin(kSt.x * (15.0 + uMid * 10.0) + uTime * 2.0);
    float pattern2 = cos(kSt.y * (15.0 + uTreble * 15.0) - uTime * 3.0);
    float grid = abs(pattern1 * pattern2);
    
    float pulseRadius = 0.35 + uBass * 0.25;
    float ringGlow = exp(-abs(r - pulseRadius) * (15.0 - uBass * 8.0));
    
    vec3 baseColor = mix(uPrimaryColor, vec3(0.9, 0.1, 0.7), sin(r * 10.0 + uTime) * 0.5 + 0.5);
    vec3 col = baseColor * grid * (1.2 + uBass * 2.5 + uEnergy * 1.5);
    col += vec3(0.2, 0.95, 1.0) * ringGlow * (1.5 + uBass * 3.0);
    
    col *= smoothstep(1.3, 0.1, r);
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
