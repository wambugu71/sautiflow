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

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uSize;
    
    // Matrix column grid
    float numCols = 32.0;
    float colIdx = floor(uv.x * numCols);
    
    // Fall speed per column accelerated by audio
    float speed = (0.5 + hash12(vec2(colIdx, 1.0)) * 1.5) * (1.0 + uBass * 2.0);
    float yPos = fract(uv.y + uTime * speed * 0.4);
    
    // Digital glyph brightness trail
    float trail = pow(1.0 - yPos, 4.0);
    float glyph = hash12(vec2(colIdx, floor((uv.y + uTime * speed * 0.4) * 20.0)));
    
    vec3 matrixColor = mix(vec3(0.0, 0.95, 0.4), uPrimaryColor, hash12(vec2(colIdx, 2.0)));
    vec3 col = matrixColor * trail * (0.8 + glyph * 0.8) * (1.2 + uMid * 2.5 + uEnergy * 1.5);
    
    // Leader head glyph brightness on treble
    if (yPos > 0.92) {
        col += vec3(0.8, 1.0, 0.9) * (1.5 + uTreble * 4.0);
    }
    
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
