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

float hash12(vec2 p) {
    p = fract(p * vec2(5.3983, 5.4427));
    p += dot(p.yx, p.xy + vec2(21.5351, 14.3137));
    return fract(p.x * p.y);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 st = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    float dist = length(st);
    float angle = atan(st.y, st.x);
    
    vec3 col = vec3(0.01, 0.01, 0.04);
    
    // Pulsar Magnetic Beams (2 opposite rotating polar beams)
    float beamAngle = angle + uTime * (2.0 + uEnergy * 2.0);
    float beam = exp(-pow(sin(beamAngle), 2.0) * 150.0);
    vec3 beamColor = mix(vec3(0.2, 0.9, 1.0), uPrimaryColor, 0.5);
    col += beamColor * beam * (1.5 + uBass * 3.0);
    
    // Core Pulsar Radius pulsing with bass
    float coreRadius = 0.08 + uBass * 0.06;
    
    // Coronal Plasma Noise Surface
    float coronaNoise = hash12(vec2(floor(angle * 16.0), floor(dist * 20.0 - uTime * 3.0)));
    float corona = exp(-abs(dist - coreRadius) * (20.0 - uBass * 8.0)) * (0.8 + coronaNoise * 0.5);
    
    vec3 coreColor = mix(vec3(1.0, 0.9, 0.5), uPrimaryColor, dist / 0.5);
    col += coreColor * corona * (1.5 + uEnergy * 2.0);
    
    if (dist < coreRadius) {
        col = vec3(1.0, 0.95, 0.8) * (1.8 + uBass * 2.0);
    }
    
    // Expanding Supernova Harmonic Shockwave Rings
    for (int i = 0; i < 3; i++) {
        float phase = fract(uTime * 0.8 + float(i) * 0.33);
        float ringR = coreRadius + phase * 0.6;
        float ringThickness = 0.015 + uBass * 0.02;
        
        float ring = exp(-abs(dist - ringR) / ringThickness) * (1.0 - phase);
        vec3 ringColor = mix(uPrimaryColor, vec3(0.9, 0.2, 0.8), float(i) * 0.4);
        col += ringColor * ring * (uBass * 3.0 + 0.3);
    }
    
    // Radial Starlight Flare Rays on Treble
    float rayPattern = sin(angle * 24.0 + uTime * 4.0) * 0.5 + 0.5;
    rayPattern = pow(rayPattern, 4.0);
    float rayGlow = exp(-dist * 4.0) * rayPattern * (uTreble * 3.0 + 0.1);
    col += vec3(0.9, 0.95, 1.0) * rayGlow;
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
