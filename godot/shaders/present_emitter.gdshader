// Visible emissive panel / tube (softbox, strip light, neon) matching a present_sky.gdshader panel.
// Unshaded HDR colour with the same soft edge and hot spot so reflections and geometry agree.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color = vec4(3.0, 3.0, 3.0, 0.08); // rgb * energy, a = edge softness
uniform bool tube = false; // round cross-section falloff across v (neon tubes)

void fragment() {
	vec2 q = abs(UV * 2.0 - 1.0);
	float s = max(color.a, 1e-3);
	float m = (1.0 - smoothstep(1.0 - s, 1.0, q.x)) * (1.0 - smoothstep(1.0 - s, 1.0, q.y));
	float hot = 1.0 + 0.25 * (1.0 - q.x * q.x) * (1.0 - q.y * q.y);
	if (tube) {
		hot = mix(0.55, 1.25, sqrt(max(0.0, 1.0 - q.y * q.y)));
	}
	ALBEDO = color.rgb * hot * m;
}
