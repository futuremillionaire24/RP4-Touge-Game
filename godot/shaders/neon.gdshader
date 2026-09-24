// Neon signage: procedural "kanji-like" glyph stacks for blade signs and scrolling billboards.
// UV2.x = atlas index (0-15 blades, 100+ billboards), UV2.y = hue. Flickers occasionally;
// glows much brighter at night (drives bloom).
shader_type spatial;
render_mode cull_disabled, unshaded;

#include "res://shaders/include/nt_noise.gdshaderinc"

global uniform float nt_night;

vec3 hue_color(float h) {
	vec3 k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
	vec3 p = abs(fract(vec3(h) + k) * 6.0 - 3.0);
	return clamp(p - 1.0, 0.0, 1.0);
}

// A glyph: random strokes (horizontal, vertical, box) on a 5x5 grid seeded per character.
float glyph(vec2 uv, float seed) {
	vec2 g = uv * 5.0;
	vec2 c = floor(g);
	vec2 f = fract(g);
	float strokes = 0.0;
	float h = nt_hash(c + seed * 31.0);
	float hs = step(0.55, nt_hash(vec2(c.y, seed * 7.0))) * step(0.3, f.y) * step(f.y, 0.7);
	float vs = step(0.6, nt_hash(vec2(c.x + 11.0, seed * 5.0))) * step(0.3, f.x) * step(f.x, 0.7);
	strokes = max(hs, vs) * step(0.25, h);
	// Keep a margin so glyphs don't touch.
	strokes *= step(0.5, g.x) * step(g.x, 4.5) * step(0.5, g.y) * step(g.y, 4.5);
	return strokes;
}

void fragment() {
	float idx = UV2.x;
	vec3 col = hue_color(UV2.y) * 1.2 + 0.05;
	float mask = 0.0;
	float border;
	if (idx < 99.0) {
		// Vertical blade: stack of glyphs down the sign.
		vec2 uv = UV;
		float chars = 4.0;
		float row = floor(uv.y * chars);
		vec2 cuv = vec2(uv.x, fract(uv.y * chars));
		mask = glyph(cuv, idx * 13.0 + row);
		border = step(uv.x, 0.06) + step(0.94, uv.x) + step(uv.y, 0.02) + step(0.98, uv.y);
	} else {
		// Billboard: two rows of glyphs + a slow wipe animation.
		vec2 uv = UV;
		float cols = 8.0;
		float c = floor(uv.x * cols);
		vec2 cuv = vec2(fract(uv.x * cols), fract(uv.y * 2.0));
		mask = glyph(cuv, idx * 3.0 + c + floor(uv.y * 2.0) * 17.0);
		float wipe = step(fract(TIME * 0.08 + idx * 0.13), uv.x);
		mask *= 0.6 + 0.4 * wipe;
		border = step(uv.y, 0.04) + step(0.96, uv.y);
	}
	// Occasional flicker (a few signs only).
	float fl = nt_hash(vec2(idx, floor(TIME * 12.0)));
	float flicker = mix(1.0, step(0.15, fl), step(0.93, nt_hash(vec2(idx, 3.0))));
	vec3 panel = vec3(0.02, 0.02, 0.03) + col * 0.06;
	vec3 light = col * (mask + clamp(border, 0.0, 1.0) * 0.8);
	float power = mix(1.2, 6.0, nt_night) * flicker;
	ALBEDO = panel + light * power;
}
