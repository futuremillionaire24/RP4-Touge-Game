// Roofs: UV2.x 0 = flat (tarred gravel / terrace), 1 = pitched clay tiles (tile columns run down
// the slope); UV2.y per-building seed. UV in 2 m units (along the eave / up the slope on pitched
// faces, world x/z on flat ones). Textures from the "facade" array (Poly Haven CC0).
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/include/nt_noise.gdshaderinc"
#include "res://shaders/include/env_layers.gdshaderinc"

global uniform float nt_wetness;
global uniform float nt_snow;

uniform sampler2DArray facade_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray facade_normal : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool tiles = UV2.x > 0.5;
	float seed = UV2.y;
	vec2 m = UV * 2.0;
	vec3 N = normalize(world_nrm);
	vec3 dp1 = dFdx(world_pos);
	vec3 dp2 = dFdy(world_pos);
	vec3 T = cross(dp2, N) * dFdx(m.x) + cross(N, dp1) * dFdy(m.x);
	T = normalize(T - N * dot(T, N) + vec3(1e-6));
	vec3 B = normalize(cross(N, T));
	float layer = tiles ? 6.0 : 7.0;
	float tile_m = tiles ? 2.5 : 2.2;
	vec3 uv = vec3(m / tile_m + seed * 7.0, layer);
	vec4 a = texture(facade_albedo, uv);
	vec4 n = texture(facade_normal, uv);
	vec3 albedo = a.rgb;
	if (tiles) {
		// Terracotta varies from orange to brown-red between buildings; lichen and soot patches.
		albedo *= mix(vec3(1.08, 0.95, 0.88), vec3(0.85, 0.8, 0.78), fract(seed * 5.3));
		float lichen = smoothstep(0.6, 0.8, nt_fbm(world_pos.xz * 0.35 + seed * 9.0, 3));
		albedo = mix(albedo, albedo * vec3(0.75, 0.78, 0.7), lichen * 0.6);
	} else {
		// Flat roofs: pale gravel or sun-bleached membrane.
		albedo = mix(albedo * 1.6, vec3(0.72, 0.7, 0.66) * (0.8 + 0.4 * a.rgb), step(0.6, seed));
	}
	float rough = mix(0.7, 0.95, n.b);
	float wet = clamp(nt_wetness, 0.0, 1.0);
	albedo *= mix(1.0, 0.7, wet);
	rough = mix(rough, 0.3, wet);
	float snow = clamp(nt_snow * 1.5 - (1.0 - N.y) * 1.5, 0.0, 1.0);
	albedo = mix(albedo, vec3(0.88, 0.9, 0.93), snow);
	vec3 Nw = env_perturb(N, T, B, n.rg, 1.0 - snow * 0.7);
	NORMAL = normalize((VIEW_MATRIX * vec4(Nw, 0.0)).xyz);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	AO = n.a;
}
