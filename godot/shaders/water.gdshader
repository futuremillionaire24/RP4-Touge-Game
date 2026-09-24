// Sea / bay: layered animated normals, depth-free colour (mobile friendly), fresnel reflections
// of the sky and a night sheen from city lights.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/nt_noise.gdshaderinc"

global uniform float nt_night;
global uniform float nt_rain;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Gentle swell on the vertices close to the camera.
	float w = sin(world_pos.x * 0.05 + TIME * 0.6) * 0.25 + sin(world_pos.z * 0.07 - TIME * 0.45) * 0.2;
	VERTEX.y += w;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	vec2 n1 = vec2(nt_value_noise(p * 0.08 + vec2(t * 0.05, t * 0.03)), nt_value_noise(p * 0.08 - vec2(t * 0.04, -t * 0.02) + 7.0)) - 0.5;
	vec2 n2 = vec2(nt_value_noise(p * 0.35 + vec2(-t * 0.12, t * 0.1)), nt_value_noise(p * 0.35 + vec2(t * 0.09, t * 0.11) + 3.0)) - 0.5;
	vec2 rip = nt_ripples(p * 0.5, t, nt_rain) * 0.5;
	NORMAL_MAP = normalize(vec3(n1 * 0.8 + n2 * 0.5 + rip, 1.0)) * 0.5 + 0.5;
	vec3 deep = mix(vec3(0.02, 0.08, 0.12), vec3(0.005, 0.01, 0.025), nt_night);
	ALBEDO = deep;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
