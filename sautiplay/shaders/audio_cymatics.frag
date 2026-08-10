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

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 st = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    // Rotate plate slowly with time
    float rotAngle = uTime * 0.15;
    mat2 rotMat = mat2(cos(rotAngle), -sin(rotAngle), sin(rotAngle), cos(rotAngle));
    st = rotMat * st;
    
    // Scale coordinate space for Chladni plate [-1, 1]
    vec2 p = st * 2.2;
    
    // Chladni mode numbers dynamic driven by audio frequencies
    float n = 2.0 + floor(uBass * 5.0) + sin(uTime * 0.4) * 0.5;
    float m = 3.0 + floor(uMid * 6.0) + cos(uTime * 0.3) * 0.5;
    
    // Chladni Standing Wave Equation
    float val1 = cos(n * PI * p.x) * cos(m * PI * p.y) - cos(m * PI * p.x) * cos(n * PI * p.y);
    
    // Second harmonic mode on treble
    float n2 = n * 2.0;
    float m2 = m + 1.0;
    float val2 = cos(n2 * PI * p.x) * cos(m2 * PI * p.y) - cos(m2 * PI * p.x) * cos(n2 * PI * p.y);
    
    float val = mix(val1, val2, uTreble * 0.5);
    
    // Nodal line proximity (zero crossing glow)
    float nodalDist = abs(val);
    float nodeLine = exp(-nodalDist * (15.0 - uBass * 8.0));
    
    // Sacred geometry mandala glow
    vec3 col = vec3(0.02, 0.02, 0.05);
    
    // Color mapping along frequency nodal lines
    float distCenter = length(st);
    vec3 mandalaColor = mix(
        uPrimaryColor,
        vec3(0.1, 0.95, 0.8),
        sin(distCenter * 10.0 - uTime * 2.0) * 0.5 + 0.5
    );
    
    col += mandalaColor * nodeLine * (1.2 + uBass * 2.5 + uEnergy * 1.5);
    
    // High frequency acoustic particle glitter along nodal lines
    float particleGrid = 25.0;
    vec2 pCell = floor(p * particleGrid);
    float pHash = fract(sin(dot(pCell, vec2(127.1, 311.7))) * 43758.545);
    
    if (nodalDist < 0.15 && pHash > 0.85) {
        float sparkle = exp(-nodalDist * 30.0) * (uTreble * 3.0 + 0.2);
        col += vec3(1.0, 0.9, 0.6) * sparkle;
    }
    
    // Plate edge boundary ring
    float plateEdge = exp(-abs(distCenter - 0.45) * 40.0);
    col += uPrimaryColor * plateEdge * 1.5;
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
