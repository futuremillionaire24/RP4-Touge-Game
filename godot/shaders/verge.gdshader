// Road verges and pavements. UV2.x = surface id (native SurfaceId): 2 sidewalk (stone pavers),
// 5 gravel, 6 dirt, 7 grass, 8 sand, 12 port / plaza slabs. Real surfaces from the "ground"
// texture array (Poly Haven CC0, layer order in tools/carbake/envtex.json), world-projected.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/include/nt_noise.gdshaderinc"
#include "res://shaders/include/env_layers.gdshaderinc"
#include "res://shaders/include/lamp_pools.gdshaderinc"

global uniform float nt_wetness;
global uniform float nt_snow;
global uniform float nt_night;
global uniform float nt_season;

uniform sampler2DArray ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_normal : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	int surf = int(round(UV2.x));
	vec2 p = world_pos.xz;
	// Surface -> ground layer and tile size (m).
	float layer = 0.0;
	float tile = 7.0;
	if (surf == 2) { layer = 8.0; tile = 2.12; }
	else if (surf == 5) { layer = 7.0; tile = 4.0; }
	else if (surf == 6) { layer = 6.0; tile = 3.0; }
	else if (surf == 8) { layer = 4.0; tile = 6.0; }
	else if (surf == 12) { layer = 5.0; tile = 2.0; }
	vec4 a = texture(ground_albedo, vec3(p / tile, layer));
	vec4 n = texture(ground_normal, vec3(p / tile, layer));
	vec3 albedo = a.rgb * (0.9 + 0.2 * nt_fbm(p * 0.03, 2));
	float rough = mix(0.75, 0.95, n.b);
	bool paved = surf == 2 || surf == 12;
	float wet = clamp(nt_wetness * 1.1, 0.0, 1.0);
	albedo *= mix(1.0, 0.6, wet);
	rough = mix(rough, 0.3, wet * (paved ? 1.0 : 0.6));
	float snow = clamp(nt_snow * 1.3 - nt_value_noise(p * 4.0) * 0.3, 0.0, 1.0);
	albedo = mix(albedo, vec3(0.88, 0.9, 0.93), snow);
	vec3 N = normalize(world_nrm);
	vec3 Nw = env_perturb(N, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, -1.0), n.rg, 1.0 - snow * 0.7);
	NORMAL = normalize((VIEW_MATRIX * vec4(Nw, 0.0)).xyz);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	AO = COLOR.r * n.a;
	if (nt_night > 0.02) EMISSION = albedo * lamp_pool_light(world_pos) * nt_night;
}
