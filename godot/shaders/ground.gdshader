// Natural ground: grass / gravel / dirt / sand blend with world-space noise, seasonal tint, snow
// and wetness. `kind` picks the dominant material; vertex COLOR.g can blend toward dirt (worn).
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/include/nt_noise.gdshaderinc"

global uniform float nt_wetness;
global uniform float nt_snow;
global uniform float nt_season; // 0 spring, 1 summer, 2 autumn, 3 winter

uniform int kind = 0; // 0 grass, 1 gravel, 2 dirt, 3 sand, 4 concrete
uniform float tile_scale = 1.0;
uniform bool use_vertex_color = false; // meshes without colors read COLOR as white

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 grass_color(vec2 p) {
	vec3 spring = vec3(0.20, 0.33, 0.10);
	vec3 summer = vec3(0.16, 0.27, 0.07);
	vec3 autumn = vec3(0.33, 0.27, 0.10);
	vec3 winter = vec3(0.28, 0.27, 0.19);
	float s = nt_season;
	vec3 c = s < 1.0 ? mix(spring, summer, s) : (s < 2.0 ? mix(summer, autumn, s - 1.0) : mix(autumn, winter, s - 2.0));
	float n = nt_fbm(p * 0.35, 3);
	float blades = nt_value_noise(p * 9.0);
	return c * (0.7 + n * 0.5) * (0.85 + blades * 0.3);
}

void fragment() {
	vec2 p = world_pos.xz * tile_scale;
	float n = nt_value_noise(p * 4.0);
	float n2 = nt_value_noise(p * 23.0);
	vec3 albedo;
	float rough = 0.9;
	if (kind == 0) {
		albedo = grass_color(p);
		float dirt_patch = smoothstep(0.62, 0.72, nt_fbm(p * 0.12, 3));
		albedo = mix(albedo, vec3(0.24, 0.19, 0.13) * (0.8 + n * 0.4), dirt_patch * 0.7);
	} else if (kind == 1) {
		// Loose gravel: fine stones (~2 cm) with dark gaps, only gentle large-scale variation.
		float fine = nt_value_noise(p * 55.0);
		float stone = smoothstep(0.3, 0.8, fine * 0.7 + n2 * 0.3);
		albedo = mix(vec3(0.2, 0.185, 0.165), vec3(0.42, 0.4, 0.36), stone) * (0.9 + n * 0.12);
		rough = 0.95;
	} else if (kind == 2) {
		albedo = mix(vec3(0.27, 0.2, 0.13), vec3(0.4, 0.31, 0.21), n) * (0.85 + n2 * 0.25);
	} else if (kind == 3) {
		albedo = mix(vec3(0.62, 0.55, 0.42), vec3(0.74, 0.68, 0.55), n) * (0.9 + n2 * 0.15);
	} else {
		albedo = mix(vec3(0.38, 0.38, 0.37), vec3(0.5, 0.5, 0.49), n) * (0.9 + n2 * 0.15);
		rough = 0.8;
	}
	float ao = use_vertex_color ? COLOR.r : 1.0;
	if (use_vertex_color) albedo = mix(albedo, vec3(0.26, 0.2, 0.14), COLOR.g * 0.8);
	float wet = clamp(nt_wetness * 1.1, 0.0, 1.0);
	albedo *= mix(1.0, 0.6, wet);
	rough = mix(rough, 0.45, wet * (kind == 0 ? 0.4 : 0.8));
	float snow = clamp(nt_snow * 1.3 - n * 0.3, 0.0, 1.0);
	albedo = mix(albedo, vec3(0.88, 0.9, 0.93), snow);
	ALBEDO = albedo;
	ROUGHNESS = mix(rough, 0.75, snow);
	NORMAL_MAP = normalize(vec3((n2 - 0.5) * 0.4, (n - 0.5) * 0.4, 1.0)) * 0.5 + 0.5;
	AO = ao;
}
