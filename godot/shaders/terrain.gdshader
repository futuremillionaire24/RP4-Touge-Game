// Open-world terrain with real surfaces (Poly Haven CC0 texture array "ground", layer order in
// tools/carbake/envtex.json). Land-cover weights from the generator: COLOR.r rock, .g sand,
// .b urban, .a farm; UV2.x forest, UV2.y park. The rest is Mediterranean scrub (garrigue: dry
// grass, stones and bare soil). Layers are height-blended; rock is tri-planar on cliffs.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/include/nt_noise.gdshaderinc"
#include "res://shaders/include/env_layers.gdshaderinc"

global uniform float nt_wetness;
global uniform float nt_snow;
global uniform float nt_season;

uniform sampler2DArray ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_normal : filter_linear_mipmap_anisotropic, repeat_enable;

// Layer ids in the ground array and their tile sizes (m).
const int L_SCRUB = 0;
const int L_PARK = 1;
const int L_FOREST = 2;
const int L_ROCK = 3;
const int L_SAND = 4;
const int L_URBAN = 5;
const int L_FARM = 6;
const int L_DIRT = 7;
const float TILE[9] = float[](7.0, 2.4, 2.3, 6.5, 6.0, 2.0, 3.0, 4.0, 2.12);

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 N = normalize(world_nrm);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	// Macro variation (breaks tiling at distance) and a patch mask.
	float macro = nt_fbm(p * 0.012, 3);
	float patches = nt_fbm(p * 0.045 + 7.0, 3);

	float w[8];
	w[L_ROCK] = smoothstep(0.2, 0.6, COLOR.r + (nt_value_noise(p * 0.15) - 0.5) * 0.3);
	w[L_SAND] = COLOR.g;
	w[L_URBAN] = COLOR.b;
	w[L_FARM] = COLOR.a;
	w[L_FOREST] = UV2.x;
	w[L_PARK] = UV2.y;
	float other = w[L_SAND] + w[L_URBAN] + w[L_FARM] + w[L_FOREST] + w[L_PARK];
	float scrub = clamp(1.0 - other, 0.0, 1.0);
	// Scrub alternates between dry grass/stone and bare stony soil.
	float bare = smoothstep(0.45, 0.7, patches);
	w[L_SCRUB] = scrub * (1.0 - bare);
	w[L_DIRT] = scrub * bare;
	// Rock overrides everything on cliffs.
	for (int i = 0; i < 8; i++) {
		if (i != L_ROCK) w[i] *= 1.0 - w[L_ROCK];
	}

	vec3 alb = vec3(0.0);
	vec4 nrm = vec4(0.0);
	float wsum = 0.0;
	for (int i = 0; i < 8; i++) {
		if (w[i] < 0.02) continue;
		vec4 a;
		vec4 n;
		if (i == L_ROCK) {
			// Tri-planar: steep faces take the side projections.
			vec3 bw = pow(abs(N), vec3(4.0));
			bw /= bw.x + bw.y + bw.z;
			float t = 1.0 / TILE[i];
			a = texture(ground_albedo, vec3(world_pos.zy * t, float(i))) * bw.x
				+ texture(ground_albedo, vec3(world_pos.xz * t, float(i))) * bw.y
				+ texture(ground_albedo, vec3(world_pos.xy * t, float(i))) * bw.z;
			n = texture(ground_normal, vec3(world_pos.zy * t, float(i))) * bw.x
				+ texture(ground_normal, vec3(world_pos.xz * t, float(i))) * bw.y
				+ texture(ground_normal, vec3(world_pos.xy * t, float(i))) * bw.z;
		} else {
			vec2 uv = p / TILE[i];
			a = texture(ground_albedo, vec3(uv, float(i)));
			n = texture(ground_normal, vec3(uv, float(i)));
			// Second rotated sample blended by the macro mask hides repetition on big areas.
			if (i == L_SCRUB || i == L_SAND || i == L_DIRT) {
				vec2 uv2 = env_rot(p, 1.1) / (TILE[i] * 2.3);
				float m = smoothstep(0.35, 0.65, macro);
				a = mix(a, texture(ground_albedo, vec3(uv2, float(i))), m);
				n = mix(n, texture(ground_normal, vec3(uv2, float(i))), m);
			}
		}
		float hw = env_hweight(w[i], a.a);
		alb += a.rgb * hw;
		nrm += n * hw;
		wsum += hw;
	}
	alb /= max(wsum, 1e-4);
	nrm /= max(wsum, 1e-4);

	// Seasons: greener spring, drier summer, warm autumn, dull winter (vegetated layers only).
	float veg = (w[L_SCRUB] + w[L_PARK] + w[L_FOREST] + w[L_FARM] * 0.5);
	float s = nt_season;
	vec3 tint = s < 1.0 ? mix(vec3(0.92, 1.06, 0.9), vec3(1.05, 1.0, 0.9), s)
		: (s < 2.0 ? mix(vec3(1.05, 1.0, 0.9), vec3(1.12, 0.95, 0.8), s - 1.0) : mix(vec3(1.12, 0.95, 0.8), vec3(0.95, 0.95, 0.92), s - 2.0));
	alb *= mix(vec3(1.0), tint, clamp(veg, 0.0, 1.0));
	alb *= 0.86 + 0.28 * macro;

	float rough = nrm.b;
	float ao = nrm.a;
	float wet = clamp(nt_wetness * 1.1, 0.0, 1.0);
	alb *= mix(1.0, 0.62, wet);
	rough = mix(rough, 0.4, wet * 0.7);
	// Snow settles on flat ground first.
	float snow = clamp(nt_snow * 1.4 - (1.0 - N.y) * 2.5 - nt_value_noise(p * 0.2) * 0.3, 0.0, 1.0);
	alb = mix(alb, vec3(0.86, 0.88, 0.92), snow);
	rough = mix(rough, 0.7, snow);

	// Normal: planar layers use X/Z as tangent frame; fade detail out with distance.
	float k = (1.0 - snow * 0.8) * mix(1.0, 0.35, smoothstep(40.0, 250.0, dist));
	vec3 Nw = env_perturb(N, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, -1.0), nrm.rg, k);
	NORMAL = normalize((VIEW_MATRIX * vec4(Nw, 0.0)).xyz);
	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
}
