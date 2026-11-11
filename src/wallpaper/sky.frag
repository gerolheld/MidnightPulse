#version 440
// Midnight Pulse sky: layered twinkling stars, aurora curtains, nebula and horizon glow.
// bass/energy/beat come from the live Spotify spectrum.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float bass;
    float energy;
    float beat;
    float aspect;
    float intensity;
    float themeH;      // live theme: hue the Midnight accent (197°) maps to
    float themeO;      //             hue offset of the partner colour (29° originally)
    float themeS;      //             saturation multiplier
};

float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
    return v;
}

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y), e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
// Same transform as Palette.qml: rotate the blue family onto the active theme hue.
vec3 themed(vec3 c) {
    vec3 h = rgb2hsv(c);
    float rel = mod(h.x * 360.0 - 197.0 + 540.0, 360.0) - 180.0;
    float w = 1.0 - smoothstep(70.0, 90.0, abs(rel));      // soft cut instead of a hard edge
    float nh = mod(themeH + rel * themeO / 29.0, 360.0) / 360.0;
    vec3 t = hsv2rgb(vec3(nh, clamp(h.y * themeS, 0.0, 1.0), h.z));
    return mix(c, t, w);
}

vec3 starLayer(vec2 uv, float scale, float speed, float seed, float boost) {
    vec2 p = uv * scale + vec2(time * speed, 0.0);
    vec2 id = floor(p), f = fract(p) - 0.5;
    float h = hash(id + seed);
    if (h < 0.72) return vec3(0.0);
    vec2 off = vec2(hash(id + seed + 3.1), hash(id + seed + 7.7)) - 0.5;
    float d = length(f - off * 0.7);
    float tw = 0.55 + 0.45 * sin(time * (1.2 + h * 3.0) + h * 40.0);
    float size = 0.025 + 0.05 * (h - 0.72) * 3.5;
    float core = smoothstep(size * (1.0 + boost * 1.6), 0.0, d);
    float glow = 0.012 / (d * d * 40.0 + 0.02) * (h - 0.72);
    vec3 tint = mix(vec3(0.62, 0.78, 1.0), vec3(0.85, 0.95, 1.0), hash(id + 1.3));
    return tint * (core + glow) * tw * (1.0 + boost * 1.8);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = vec2(uv.x * aspect, uv.y);
    float t = time;
    float e = clamp(energy * intensity, 0.0, 1.5);
    float b = clamp(bass * intensity, 0.0, 1.5);

    // Base: deep night gradient.
    vec3 col = mix(vec3(0.012, 0.020, 0.055), vec3(0.027, 0.043, 0.094), smoothstep(0.0, 0.75, uv.y));
    col = mix(col, vec3(0.035, 0.070, 0.180), smoothstep(0.6, 1.0, uv.y) * 0.75);

    // Nebula clouds drifting slowly.
    float n = fbm(p * 1.6 + vec2(t * 0.012, -t * 0.006));
    float n2 = fbm(p * 3.1 - vec2(t * 0.02, 0.0) + n);
    col += vec3(0.05, 0.09, 0.28) * smoothstep(0.45, 0.95, n2) * (0.55 + 0.6 * e);
    col += vec3(0.08, 0.04, 0.22) * smoothstep(0.55, 1.0, n) * 0.35;

    // Stars: three depth layers; only a faint twinkle on the beat (no flashes).
    col += starLayer(p, 46.0, 0.0018, 1.0, beat * 0.05) * 0.55;
    col += starLayer(p, 24.0, 0.0040, 5.0, beat * 0.10) * 0.80;
    col += starLayer(p, 11.0, 0.0085, 9.0, beat * 0.18);

    // Aurora: wavy, patchy curtains with rays rising upwards; brighten with the music.
    vec3 aurCol = vec3(0.0);
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float x = p.x * (0.8 + fi * 0.3) + fi * 2.7;
        float wave = sin(x * 2.1 + t * 0.11 + fi) * 0.045 + (fbm(vec2(x * 1.2 + t * 0.035, fi * 4.0)) - 0.5) * 0.16;
        float yc = 0.34 + fi * 0.07 + wave;
        float mask = smoothstep(0.22, 0.62, fbm(vec2(x * 0.9 - t * 0.02, fi * 7.0 + 1.0)));
        float rays = 0.35 + 0.65 * fbm(vec2(x * 22.0 + t * 0.3 + fi * 11.0, uv.y * 2.0 - t * 0.15));
        float d = uv.y - yc;                        // >0 below the curtain edge
        float edge = exp(-pow(d / (0.028 + b * 0.02), 2.0));
        // rays fading upwards; the lower edge fades out softly instead of a hard (aliased) cut
        float up = exp(min(d, 0.0) / (0.17 + 0.05 * fi + b * 0.10)) * (1.0 - smoothstep(-0.004, 0.022, d));
        float curtain = (edge * 1.1 + up * 1.05) * rays * mask;
        vec3 c = mix(vec3(0.10, 0.72, 0.95), vec3(0.28, 0.32, 1.0), fi * 0.5);
        c = mix(c, vec3(0.62, 0.92, 1.0), edge * 0.35 + b * 0.08);
        aurCol += c * curtain;
    }
    col += aurCol * (0.45 + 0.50 * e);           // follows the overall loudness, never flashes

    // Horizon glow behind the dock, gently breathing with the bass (no beat flash, no ripple rings).
    float hz = exp(-pow((1.0 - uv.y) * (3.4 - b * 0.4), 2.0));
    float hx = exp(-pow((uv.x - 0.5) * 1.6, 2.0));
    col += vec3(0.08, 0.40, 0.75) * hz * hx * (0.25 + 0.25 * b);

    // Vignette.
    vec2 v = uv - 0.5;
    col *= 1.0 - dot(v, v) * 0.55;

    fragColor = vec4(themed(max(col, vec3(0.0))), 1.0) * qt_Opacity;
}
