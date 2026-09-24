// Road verges and pavements. UV2.x = surface id (native SurfaceId): 2 concrete sidewalk
// pavers, 5 gravel, 6 dirt, 7 grass, 8 sand; UV in meters-ish along/across.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/include/nt_noise.gdshaderinc"

global uniform float nt_wetness;
global uniform float nt_snow;
global uniform float nt_season;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	int surf = int(round(UV2.x));
	vec2 p = world_pos.xz;
	float n = nt_value_noise(p * 4.0);
	float n2 = nt_value_noise(p * 23.0);
	vec3 albedo;
	float rough = 0.9;
	if (surf == 2) {
		// Interlocking pavers, 0.3 x 0.6 m, with a tactile yellow guide strip.
		vec2 t = p / vec2(0.6, 0.3);
		t.x += step(1.0, mod(floor(t.y), 2.0)) * 0.5;
		vec2 f = fract(t);
		float joint = step(f.x, 0.04) + step(f.y, 0.07);
		albedo = mix(vec3(0.52, 0.5, 0.47), vec3(0.62, 0.6, 0.56), nt_hash(floor(t))) * (0.9 + n2 * 0.15);
		albedo = mix(albedo, vec3(0.25, 0.24, 0.22), clamp(joint, 0.0, 1.0) * 0.7);
		rough = 0.8;
	} else if (surf == 5) {
		float fine = nt_value_noise(p * 55.0);
		float stone = smoothstep(0.3, 0.8, fine * 0.7 + n2 * 0.3);
		albedo = mix(vec3(0.2, 0.185, 0.165), vec3(0.42, 0.4, 0.36), stone) * (0.9 + n * 0.12);
		rough = 0.95;
	} else if (surf == 6) {
		albedo = mix(vec3(0.27, 0.2, 0.13), vec3(0.4, 0.31, 0.21), n) * (0.85 + n2 * 0.25);
	} else if (surf == 12) {
		// Dock yard concrete slabs with expansion joints and oil stains.
		vec2 f = fract(p / 6.0);
		float joint = step(f.x, 0.01) + step(f.y, 0.01);
		albedo = mix(vec3(0.42, 0.42, 0.4), vec3(0.5, 0.5, 0.48), n) * (0.92 + n2 * 0.1);
		albedo *= 1.0 - 0.35 * smoothstep(0.7, 0.85, nt_fbm(p * 0.2, 2));
		albedo = mix(albedo, vec3(0.2), clamp(joint, 0.0, 1.0) * 0.6);
		rough = 0.85;
	} else if (surf == 8) {
		albedo = mix(vec3(0.62, 0.55, 0.42), vec3(0.74, 0.68, 0.55), n);
	} else {
		float s = nt_season;
		vec3 g = s < 1.0 ? mix(vec3(0.22, 0.34, 0.11), vec3(0.15, 0.26, 0.07), s) : (s < 2.0 ? mix(vec3(0.15, 0.26, 0.07), vec3(0.36, 0.28, 0.1), s - 1.0) : vec3(0.3, 0.28, 0.2));
		albedo = g * (0.75 + n * 0.4) * (0.85 + n2 * 0.3);
	}
	float wet = clamp(nt_wetness * 1.1, 0.0, 1.0);
	albedo *= mix(1.0, 0.6, wet);
	rough = mix(rough, 0.35, wet * (surf == 2 ? 1.0 : 0.6));
	albedo = mix(albedo, vec3(0.88, 0.9, 0.93), clamp(nt_snow * 1.3 - n * 0.3, 0.0, 1.0));
	ALBEDO = albedo;
	ROUGHNESS = rough;
	NORMAL_MAP = normalize(vec3((n2 - 0.5) * 0.4, (n - 0.5) * 0.4, 1.0)) * 0.5 + 0.5;
	AO = COLOR.r;
}
