// Brushed / machined metal (no tangents needed): fine brushing streaks along a chosen local axis
// drive roughness and albedo; a stretched highlight is faked by widening roughness across the
// brush direction. Fades to the mean at distance.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/car_common.gdshaderinc"

uniform vec3 color : source_color = vec3(0.62, 0.63, 0.65);
uniform float rough : hint_range(0.0, 1.0) = 0.3;
uniform vec3 brush_axis = vec3(1.0, 0.0, 0.0);
uniform float streak_scale = 0.00035; // metres between streaks

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 nl = normalize(local_normal);
	vec3 ax = normalize(brush_axis - nl * dot(brush_axis, nl) + 1e-4);
	vec3 across = normalize(cross(nl, ax));
	float fp = car_footprint(local_pos);
	float vis = 1.0 - smoothstep(streak_scale * 2.0, streak_scale * 8.0, fp);
	float a = dot(local_pos, across) / streak_scale;
	float b = dot(local_pos, ax) / (streak_scale * 60.0);
	float s = car_vnoise(vec2(a, b)) * 0.6 + car_vnoise(vec2(a * 3.1, b * 0.5 + 7.0)) * 0.4;
	float streak = mix(0.5, s, vis);
	// Brushing scatters light across the brush direction: tilt normal across it a little.
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * across * ((s - 0.5) * 0.25 * vis));
	ALBEDO = color * (0.9 + 0.2 * streak);
	METALLIC = 1.0;
	ROUGHNESS = car_spec_aa(NORMAL, rough + (streak - 0.5) * 0.12);
}
