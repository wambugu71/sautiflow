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
    
    // Hyperwarp speed acceleration on bass drops
    float warpSpeed = uTime * (1.5 + uBass * 5.0 + uEnergy * 3.0);
    float z = 1.0 / (r + 0.01) + warpSpeed;
    
    // Spiral warp lines
    float spiral = sin(a * 10.0 + z * 2.0 + uMid * 5.0);
    float starStreaks = pow(abs(cos(a * 20.0 + sin(z * 4.0))), 8.0);
    
    vec3 col = uPrimaryColor * (spiral * 0.5 + 0.5) * (1.0 + uBass * 3.0);
    col += vec3(0.2, 0.85, 1.0) * starStreaks * (1.5 + uTreble * 4.0) / (r + 0.1);
    
    // Radial flash on bass drop
    col += vec3(1.0, 0.3, 0.7) * exp(-r * (4.0 - uBass * 3.0)) * uBass * 2.5;
    
    col *= smoothstep(1.4, 0.1, r);
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
