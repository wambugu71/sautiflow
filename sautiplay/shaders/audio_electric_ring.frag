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

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 st = (fragCoord - 0.5 * uSize) / min(uSize.x, uSize.y);
    
    float r = length(st);
    float a = atan(st.y, st.x);
    
    float ringRadius = 0.32 + uBass * 0.12;
    
    // High frequency electric arc jittering
    float electricJitter = (hash11(a * 50.0 + uTime * 20.0) - 0.5) * (0.04 + uTreble * 0.10);
    float ringEdge = ringRadius + electricJitter;
    
    float arcDist = abs(r - ringEdge);
    float arcIntensity = exp(-arcDist * (40.0 - uBass * 20.0));
    
    vec3 arcColor = mix(vec3(0.2, 0.8, 1.0), vec3(1.0, 0.3, 0.9), sin(a * 4.0 + uTime * 5.0) * 0.5 + 0.5);
    
    vec3 col = arcColor * arcIntensity * (1.5 + uBass * 3.5 + uTreble * 2.0);
    
    // Lightning plasma sparks along the arc ring
    float spark = pow(hash11(a * 100.0 + floor(uTime * 30.0)), 15.0) * uTreble;
    col += vec3(1.0, 0.95, 0.8) * spark * 4.0 * step(0.02, arcDist);
    
    col *= smoothstep(1.2, 0.1, r);
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
