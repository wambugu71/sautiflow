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
    vec2 uv = fragCoord / uSize;
    
    // Divide horizontal space into 16 equalizer bars
    float numBars = 16.0;
    float barIdx = floor(uv.x * numBars);
    float barPos = fract(uv.x * numBars);
    
    // Frequency height simulation per bar
    float freqIndex = barIdx / numBars;
    float freqHeight = 0.05;
    
    if (freqIndex < 0.25) {
        freqHeight += uBass * (0.4 + sin(barIdx * 1.5) * 0.3);
    } else if (freqIndex < 0.7) {
        freqHeight += uMid * (0.35 + cos(barIdx * 2.0) * 0.25);
    } else {
        freqHeight += uTreble * (0.3 + sin(barIdx * 3.0) * 0.2);
    }
    freqHeight *= (0.8 + uEnergy * 0.6);
    
    vec3 col = vec3(0.0);
    
    // Bar geometry with gap
    if (barPos > 0.15 && barPos < 0.85) {
        // Main equalizer bar above baseline (baseline at y = 0.2)
        float baseline = 0.2;
        if (uv.y >= baseline && uv.y <= baseline + freqHeight) {
            float barY = (uv.y - baseline) / freqHeight;
            vec3 barColor = mix(uPrimaryColor, vec3(1.0, 0.2, 0.5), barY);
            col = barColor * (1.2 + uBass * 1.5);
            // Bright top cap line
            if (barY > 0.92) col += vec3(1.0);
        } else if (uv.y < baseline) {
            // Mirror reflection below baseline
            float reflY = (baseline - uv.y) / freqHeight;
            if (reflY <= 1.0) {
                vec3 reflColor = mix(uPrimaryColor, vec3(1.0, 0.2, 0.5), reflY);
                col = reflColor * 0.25 * (1.0 - reflY);
            }
        }
    }
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
