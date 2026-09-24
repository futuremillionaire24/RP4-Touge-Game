// Clear-coated 2x2 twill carbon fibre (procedural, planar projection on the dominant local axis).
// Each tow shows a view-dependent sheen across its fibres, so the checker flips light/dark as the
// view moves, like real carbon. The weave fades to its average at distance (no moire).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/car_common.gdshaderinc"

global uniform float nt_wetness;

uniform float tow = 0.0055; // tow width, metres
uniform vec3 fibre_color : source_color = vec3(0.045, 0.047, 0.052);
uniform float coat_gloss : hint_range(0.0, 1.0) = 0.94;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 nl = normalize(local_normal);
	vec3 an = abs(nl);
	// Dominant-axis planar projection (flat carbon parts: hoods, splitters, wings, mirrors).
	vec2 p;
	vec3 du;
	vec3 dv;
	if (an.y >= an.x && an.y >= an.z) {
		p = local_pos.xz; du = vec3(1.0, 0.0, 0.0); dv = vec3(0.0, 0.0, 1.0);
	} else if (an.x >= an.z) {
		p = local_pos.zy; du = vec3(0.0, 0.0, 1.0); dv = vec3(0.0, 1.0, 0.0);
	} else {
		p = local_pos.xy; du = vec3(1.0, 0.0, 0.0); dv = vec3(0.0, 1.0, 0.0);
	}
	vec2 uv = p / tow;
	vec2 cell = floor(uv);
	vec2 f = uv - cell;
	float warp = step(mod(cell.x + cell.y, 4.0), 1.5);
	float across = mix(f.x, f.y, warp);
	float along = mix(f.y, f.x, warp);
	float crown = sin(across * PI);
	float fp = car_footprint(local_pos);
	float vis = 1.0 - smoothstep(tow * 0.25, tow * 0.9, fp);
	mat3 l2v = mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX);
	vec3 fibre_dir = normalize(l2v * mix(dv, du, warp));
	// Sheen: fibres light up when they run perpendicular to the view's projection.
	float sheen = 1.0 - abs(dot(fibre_dir, VIEW));
	sheen = sheen * sheen;
	float avg_sheen = 0.5;
	float s = mix(avg_sheen, sheen * (0.55 + 0.45 * crown), vis);
	// Tow crown and the dark gap between tows as a gentle normal/occlusion.
	float gap = smoothstep(0.08, 0.0, min(across, 1.0 - across)) + smoothstep(0.06, 0.0, min(along, 1.0 - along)) * 0.6;
	vec3 across_dir = mix(du, dv, warp);
	vec3 bend = across_dir * (cos(across * PI) * 0.35) * vis;
	NORMAL = normalize(NORMAL + l2v * bend);
	vec3 alb = fibre_color * (0.55 + 1.3 * s) * (1.0 - 0.5 * gap * vis);
	ALBEDO = alb;
	METALLIC = 0.35;
	ROUGHNESS = car_spec_aa(NORMAL, mix(0.45, 0.28, s));
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = mix(1.0 - coat_gloss, 0.02, clamp(nt_wetness, 0.0, 1.0));
}
