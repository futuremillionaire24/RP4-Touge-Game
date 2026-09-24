// Tunnel liner: tiled panels on the walls (UV.x = arc segment), grime toward the road, sodium
// wash from the lamp strips. Emissive strips use tunnel_light (unshaded) separately.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

#include "res://shaders/include/nt_noise.gdshaderinc"

void fragment() {
	float seg = UV2.x; // 0..7 arc segment
	float along = UV.y * 4.0;
	vec2 tile = vec2(fract(along / 1.2), fract(UV.x * 3.0));
	float grout = step(0.97, tile.x) + step(0.97, tile.y);
	vec3 panel = mix(vec3(0.62, 0.6, 0.55), vec3(0.72, 0.7, 0.64), nt_value_noise(vec2(floor(along / 1.2), seg)));
	float low = 1.0 - smoothstep(0.0, 2.5, min(seg, 7.0 - seg));
	panel *= mix(1.0, 0.45, low * (0.6 + 0.4 * nt_value_noise(vec2(along * 0.7, seg))));
	ALBEDO = mix(panel, vec3(0.2), clamp(grout, 0.0, 1.0) * 0.6);
	ROUGHNESS = 0.6;
	// Sodium bounce light so tunnels read warm even without real lights nearby.
	EMISSION = vec3(0.35, 0.2, 0.06) * (0.25 + 0.35 * smoothstep(3.0, 7.0, seg) * smoothstep(8.0, 4.0, seg));
}
