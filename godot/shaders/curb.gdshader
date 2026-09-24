// Red/white rumble strip: alternating blocks along the road with a ridged normal.
shader_type spatial;
render_mode cull_back, diffuse_burley;

global uniform float nt_wetness;

uniform vec3 color_a : source_color = vec3(0.72, 0.06, 0.05);
uniform vec3 color_b : source_color = vec3(0.86, 0.86, 0.84);

void fragment() {
	float stripe = step(0.5, fract(UV.y));
	vec3 c = mix(color_a, color_b, stripe);
	if (UV2.x > 0.5) {
		// City kerb stone: plain grey granite blocks.
		c = mix(vec3(0.55, 0.55, 0.53), vec3(0.62, 0.62, 0.6), step(0.5, fract(UV.y * 0.5)));
	}
	float ridge = UV2.x > 0.5 ? 0.0 : sin(UV.y * 6.2831 * 4.0);
	NORMAL_MAP = normalize(vec3(0.0, ridge * 0.35, 1.0)) * 0.5 + 0.5;
	float wet = clamp(nt_wetness * 1.2, 0.0, 1.0);
	ALBEDO = c * mix(1.0, 0.7, wet);
	ROUGHNESS = mix(0.55, 0.15, wet);
	SPECULAR = 0.5;
}
