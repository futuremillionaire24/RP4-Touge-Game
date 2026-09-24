// Textured automotive plastics / rubber / cast metal: fine stipple grain as a micro-normal and
// roughness variation that fades out with the pixel footprint (averages to the base roughness at
// distance, so no shimmer). Optional clear coat and metalness for painted or cast parts. Reacts
// to the nt_wetness global (darker, glossier film).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/car_common.gdshaderinc"

global uniform float nt_wetness;

uniform vec3 color : source_color = vec3(0.03, 0.03, 0.032);
uniform float rough : hint_range(0.0, 1.0) = 0.6;
uniform float metal : hint_range(0.0, 1.0) = 0.0;
uniform float grain : hint_range(0.0, 2.0) = 1.0;
uniform float grain_scale = 0.0011; // stipple cell size, metres
uniform float coat : hint_range(0.0, 1.0) = 0.0;
uniform float coat_rough : hint_range(0.0, 1.0) = 0.05;
uniform float wet_response : hint_range(0.0, 1.0) = 1.0;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 nl = normalize(local_normal);
	vec3 n_geo = NORMAL;
	float fp = car_footprint(local_pos);
	float vis = (1.0 - smoothstep(grain_scale * 0.6, grain_scale * 3.0, fp)) * grain;
	vec3 q = local_pos / grain_scale;
	float n1 = car_vnoise(q.xy + q.z * 0.37);
	float n2 = car_vnoise(q.zy * 1.3 + q.x * 0.41 + 5.0);
	float r = rough;
	vec3 alb = color;
	if (vis > 0.001) {
		vec3 g = vec3(n1 - 0.5, n2 - 0.5, n1 - n2);
		g -= nl * dot(g, nl);
		NORMAL = normalize(n_geo + mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * g * (0.35 * vis));
		r += (n1 - 0.5) * 0.18 * vis;
		alb *= 1.0 + (n2 - 0.5) * 0.25 * vis;
	}
	// Coarse, large-scale variation (fade/wear) visible at any distance, very subtle.
	float big = car_vnoise(local_pos.xz * 6.0 + local_pos.y * 3.0);
	alb *= 0.94 + 0.12 * big;
	float wet = clamp(nt_wetness, 0.0, 1.0) * wet_response;
	alb *= 1.0 - 0.3 * wet;
	r = mix(r, min(r, 0.18), wet * 0.8);
	ALBEDO = alb;
	METALLIC = metal;
	ROUGHNESS = car_spec_aa(n_geo, clamp(r, 0.02, 1.0));
	if (coat > 0.0) {
		CLEARCOAT = coat;
		CLEARCOAT_ROUGHNESS = car_spec_aa(n_geo, coat_rough);
	}
}
