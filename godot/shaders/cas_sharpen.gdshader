// Contrast-Adaptive Sharpening (CAS) post-process filter.
// Derived from AMD FidelityFX CAS — a lightweight 3×3 spatial sharpening pass that dramatically
// improves perceived detail after resolution scaling. Costs ~0.1 ms on Mali-G77.
// Applied via a full-screen TextureRect sampling the 3D SubViewport texture.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float sharpness : hint_range(0.0, 1.0) = 0.6;
uniform float scale_factor : hint_range(0.5, 1.5) = 1.0; // current 3D render scale

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 ts = vec2(1.0) / vec2(textureSize(screen_tex, 0));

	// Sample 3×3 neighbourhood (cardinal + center only for mobile perf).
	vec3 c = texture(screen_tex, uv).rgb;
	vec3 n = texture(screen_tex, uv + vec2(0.0, -ts.y)).rgb;
	vec3 s = texture(screen_tex, uv + vec2(0.0,  ts.y)).rgb;
	vec3 e = texture(screen_tex, uv + vec2( ts.x, 0.0)).rgb;
	vec3 w = texture(screen_tex, uv + vec2(-ts.x, 0.0)).rgb;

	// Min/max of the neighbourhood per channel.
	vec3 mn = min(c, min(min(n, s), min(e, w)));
	vec3 mx = max(c, max(max(n, s), max(e, w)));

	// CAS weight: sharpen more where contrast is low (flat areas stay smooth).
	// The reciprocal of the max gives a natural adaptive weighting.
	vec3 d = vec3(1.0) / (mx + 0.001);
	float peak = -1.0 / mix(8.0, 5.0, clamp(sharpness, 0.0, 1.0));

	// Sharpen more when rendering at lower resolution.
	float boost = mix(1.0, 1.5, clamp(1.0 - scale_factor, 0.0, 0.5) * 2.0);
	float w_cas = clamp(min(mn.r * d.r, min(mn.g * d.g, mn.b * d.b)) * peak, peak, 0.0) * sharpness * boost;

	// Weighted blend: the center pixel gets extra weight (sharpening), neighbours get negative.
	vec3 result = (c + (n + s + e + w) * w_cas) / (1.0 + 4.0 * w_cas);

	COLOR = vec4(clamp(result, vec3(0.0), vec3(1.0)), 1.0);
}
