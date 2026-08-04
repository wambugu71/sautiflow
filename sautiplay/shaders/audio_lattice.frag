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
    
    // Rotate coordinate system with mid frequencies
    float rotAngle = uTime * 0.5 + uMid * 1.5;
    mat2 rot = mat2(cos(rotAngle), -sin(rotAngle), sin(rotAngle), cos(rotAngle));
    vec2 rotSt = rot * st;
    
    // Crystalline lattice grid
    vec2 latticeSt = rotSt * (8.0 + uBass * 6.0);
    vec2 g = abs(fract(latticeSt - 0.5) - 0.5);
    float d = min(g.x, g.y);
    
    float edgeGlow = smoothstep(0.08 + uTreble * 0.08, 0.0, d);
    
    float dist = length(st);
    vec3 col = uPrimaryColor * edgeGlow * (1.5 + uBass * 3.0 + uEnergy * 2.0);
    
    // Crystal center nodes
    float nodeDist = length(fract(latticeSt) - 0.5);
    float nodeGlow = smoothstep(0.20 + uTreble * 0.15, 0.0, nodeDist);
    col += vec3(0.9, 0.95, 1.0) * nodeGlow * (1.0 + uTreble * 4.0);
    
    col *= smoothstep(1.3, 0.1, dist);
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
