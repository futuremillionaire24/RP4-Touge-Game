// Procedural grille mesh: honeycomb (pattern 0) or diamond/square wire mesh (pattern 1) on a
// dominant-axis planar projection. Opaque variant shades the openings near-black with occlusion;
// the `cutout` variant alpha-scissors them. Rib edges get a rolled-edge normal; the pattern fades
// to its average with the pixel footprint so distant grilles do not moire.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/car_common.gdshaderinc"

uniform int pattern = 0;
uniform float cell = 0.014; // cell pitch, metres
uniform float rib = 0.13; // rib width as a fraction of the cell
uniform vec3 rib_color : source_color = vec3(0.025, 0.025, 0.027);
uniform float rib_rough : hint_range(0.0, 1.0) = 0.45;
uniform float rib_metal : hint_range(0.0, 1.0) = 0.0;
uniform bool cutout = false;

varying vec3 local_pos;
varying vec3 local_normal;

// Hex tiling: offset from the nearest hex centre (pointy-top, unit pitch).
vec2 hex_offset(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 nl = normalize(local_normal);
	vec3 an = abs(nl);
	vec2 p;
	vec3 du;
	vec3 dv;
	if (an.z >= an.x && an.z >= an.y) {
		p = local_pos.xy; du = vec3(1.0, 0.0, 0.0); dv = vec3(0.0, 1.0, 0.0);
	} else if (an.x >= an.y) {
		p = local_pos.zy; du = vec3(0.0, 0.0, 1.0); dv = vec3(0.0, 1.0, 0.0);
	} else {
		p = local_pos.xz; du = vec3(1.0, 0.0, 0.0); dv = vec3(0.0, 0.0, 1.0);
	}
	vec2 q = p / cell;
	float edge; // 0 at the opening centre -> 0.5 at the rib centre line
	vec2 dir;
	if (pattern == 0) {
		vec2 h = hex_offset(q);
		vec2 ah = abs(h);
		edge = max(dot(ah, vec2(0.5, 0.8660254)), ah.x);
		dir = h;
	} else {
		vec2 d = vec2(q.x + q.y, q.x - q.y) * 0.7071;
		vec2 f = fract(d) - 0.5;
		edge = max(abs(f.x), abs(f.y));
		dir = abs(f.x) > abs(f.y) ? vec2(f.x, 0.0) : vec2(0.0, f.y);
	}
	float fp = car_footprint(local_pos) / cell;
	float w = 0.5 - rib * 0.5;
	float ribm = smoothstep(w - fp, w + fp, edge);
	float vis = 1.0 - smoothstep(0.25, 0.7, fp);
	float avg = 1.0 - (1.0 - rib) * (1.0 - rib);
	float coverage = mix(avg, ribm, vis);
	// Rolled rib edge.
	float roll = smoothstep(w, 0.5, edge) * ribm;
	vec3 tilt = normalize(du * dir.x + dv * dir.y + 1e-5) * (1.0 - roll) * 0.8 * vis * ribm;
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * tilt);
	vec3 hole = vec3(0.004);
	ALBEDO = mix(hole, rib_color, coverage);
	METALLIC = rib_metal * coverage;
	ROUGHNESS = car_spec_aa(NORMAL, mix(0.9, rib_rough, coverage));
	AO = mix(0.15, 1.0, coverage);
	SPECULAR = 0.5 * coverage;
	if (cutout) {
		ALPHA = mix(1.0, ribm, vis);
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
}
