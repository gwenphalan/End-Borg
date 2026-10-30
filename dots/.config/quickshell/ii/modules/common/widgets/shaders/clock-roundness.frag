#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 pixelStep;
    float radius;
    float amount;
};
layout(binding = 1) uniform sampler2D source;
// A compact Gaussian level set rounds glyph corners without changing advances.
// Radius follows stroke weight so light numerals retain their fine stems.
void main() {
    vec4 sum = vec4(0.0);
    for (int y = -2; y <= 2; ++y) {
        for (int x = -2; x <= 2; ++x) {
            vec2 uv = qt_TexCoord0 + vec2(x, y) * pixelStep * radius * 0.5;
            float wx = x == 0 ? 6.0 : ((x == -1 || x == 1) ? 4.0 : 1.0);
            float wy = y == 0 ? 6.0 : ((y == -1 || y == 1) ? 4.0 : 1.0);
            sum += texture(source, clamp(uv, vec2(0.0), vec2(1.0))) * wx * wy;
        }
    }
    sum /= 256.0;
    float edge = max(fwidth(sum.a), 0.02);
    float alpha = smoothstep(0.5 - edge, 0.5 + edge, sum.a);
    vec3 rgb = sum.a > 0.0001 ? sum.rgb / sum.a : vec3(0.0);
    fragColor = mix(texture(source, qt_TexCoord0), vec4(rgb * alpha, alpha), amount) * qt_Opacity;
}
