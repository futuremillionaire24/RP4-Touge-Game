// Kerbs. UV2.x > 0.5: city kerb stone - weathered granite blocks with real stone grain (ground
// texture array, Poly Haven CC0); otherwise a red/white circuit rumble strip with ridges.
shader_type spatial;
render_mode cull_back, diffuse_burley;

global uniform float nt_wetness;

uniform vec3 color_a : source_color = vec3(0.72, 0.06, 0.05);
uniform vec3 color_b : source_color = vec3(0.86, 0.86, 0.84);
uniform sampler2DArray ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

void fragment() {
	float stripe = step(0.5, fract(UV.y));
	vec3 c = mix(color_a, color_b, stripe);
	float rough = 0.55;
	if (UV2.x > 0.5) {
		// ~1 m granite blocks with a thin joint; grain from the pavement stone layer, desaturated.
		vec3 g = texture(ground_albedo, vec3(UV.x * 0.5, UV.y * 0.5, 8.0)).rgb;
		float lum = dot(g, vec3(0.3, 0.59, 0.11));
		float block = fract(UV.y * 0.5);
		float joint = 1.0 - smoothstep(0.0, 0.02, block) * smoothstep(1.0, 0.98, block);
		c = vec3(lum) * vec3(0.95, 0.95, 0.98) * 0.85 * (1.0 - joint * 0.5);
		rough = 0.75;
	}
	float ridge = UV2.x > 0.5 ? 0.0 : sin(UV.y * 6.2831 * 4.0);
	NORMAL_MAP = normalize(vec3(0.0, ridge * 0.35, 1.0)) * 0.5 + 0.5;
	float wet = clamp(nt_wetness * 1.2, 0.0, 1.0);
	ALBEDO = c * mix(1.0, 0.7, wet);
	ROUGHNESS = mix(rough, 0.15, wet);
	SPECULAR = 0.5;
}
