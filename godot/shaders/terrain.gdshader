// Open-world terrain. Material weights from the generator: COLOR.r rock, .g sand, .b urban,
// .a paddy; UV2.x dirt (road cuttings/shoulders), UV2.y height. Grass is the default layer and
// follows the season; paddies flood (spring) and turn gold (autumn).
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/include/nt_noise.gdshaderinc"

global uniform float nt_wetness;
global uniform float nt_snow;
global uniform float nt_season;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 season_grass(vec2 p) {
	vec3 spring = vec3(0.28, 0.40, 0.14);
	vec3 summer = vec3(0.25, 0.35, 0.12);
	vec3 autumn = vec3(0.44, 0.35, 0.16);
	vec3 winter = vec3(0.35, 0.32, 0.22);
	float s = nt_season;
	vec3 c = s < 1.0 ? mix(spring, summer, s) : (s < 2.0 ? mix(summer, autumn, s - 1.0) : mix(autumn, winter, s - 2.0));
	float n = nt_fbm(p * 0.02, 3);
	float fine = nt_value_noise(p * 1.7);
	return c * (0.75 + n * 0.50) * (0.88 + fine * 0.24);
}

void fragment() {
	vec2 p = world_pos.xz;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(60.0, 400.0, dist); // fine noise fades with distance
	vec4 w = COLOR;
	float dirt = UV2.x;
	vec3 grass = season_grass(p);
	// Warm Mediterranean limestone / sandstone strata
	vec3 rock = mix(vec3(0.38, 0.36, 0.32), vec3(0.56, 0.52, 0.46), nt_fbm(p * vec2(0.08, 0.02) + world_pos.y * 0.05, 3));
	rock *= 0.85 + 0.3 * nt_value_noise(p * 0.9) * detail;
	vec3 sand = mix(vec3(0.72, 0.65, 0.50), vec3(0.82, 0.75, 0.60), nt_value_noise(p * 0.4));
	vec3 urban = mix(vec3(0.35, 0.35, 0.36), vec3(0.46, 0.46, 0.47), nt_value_noise(p * 0.3));
	vec3 dirt_c = mix(vec3(0.32, 0.26, 0.18), vec3(0.42, 0.34, 0.24), nt_value_noise(p * 0.6));
	// Paddies: flooded mirror in spring, green in summer, gold in autumn, stubble in winter.
	float s = nt_season;
	vec3 paddy = s < 0.7 ? vec3(0.08, 0.1, 0.1) : (s < 1.6 ? vec3(0.2, 0.36, 0.08) : (s < 2.6 ? vec3(0.62, 0.5, 0.18) : vec3(0.35, 0.3, 0.2)));
	float paddy_rough = s < 0.7 ? 0.05 : 0.8;

	vec3 albedo = grass;
	float rough = 0.92;
	albedo = mix(albedo, dirt_c, clamp(dirt, 0.0, 1.0));
	albedo = mix(albedo, paddy, w.a);
	rough = mix(rough, paddy_rough, w.a);
	albedo = mix(albedo, sand, w.g);
	albedo = mix(albedo, urban, w.b);
	rough = mix(rough, 0.85, w.b);
	// Rock on steep faces, with a sharpened blend so cliffs read clearly.
	float rk = smoothstep(0.25, 0.6, w.r + (nt_value_noise(p * 0.15) - 0.5) * 0.35);
	albedo = mix(albedo, rock, rk);

	float wet = clamp(nt_wetness * 1.1, 0.0, 1.0);
	albedo *= mix(1.0, 0.62, wet);
	rough = mix(rough, 0.4, wet * 0.7);
	// Snow settles on flat ground first.
	float snow = clamp(nt_snow * 1.4 - (1.0 - world_nrm.y) * 2.5 - nt_value_noise(p * 0.2) * 0.3, 0.0, 1.0);
	albedo = mix(albedo, vec3(0.86, 0.88, 0.92), snow);
	rough = mix(rough, 0.7, snow);

	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	float n1 = nt_value_noise(p * 2.3) - 0.5;
	float n2 = nt_value_noise(p * 2.3 + 17.0) - 0.5;
	NORMAL_MAP = normalize(vec3(n1 * 0.5 * detail, n2 * 0.5 * detail, 1.0)) * 0.5 + 0.5;
}
