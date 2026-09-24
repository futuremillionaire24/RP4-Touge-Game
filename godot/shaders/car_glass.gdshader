// Automotive glass (Mobile renderer): tinted, strongly Fresnel-reflective, dark but see-through.
// Opacity rises with Fresnel so grazing panes become mirror-like (blend_mix scales reflections by
// alpha). Windscreen top shade band from UV.y (0 = belt, 1 = roof edge) on forward-facing panes,
// black ceramic frit from UV2.x (metres to the pane edge, UV2.y > 0 marks it present), rain drops
// (static beads + running drops on steep panes) from the nt_rain / nt_wetness globals.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

#include "res://shaders/include/car_common.gdshaderinc"

global uniform float nt_wetness;
global uniform float nt_rain;

uniform vec3 tint : source_color = vec3(0.07, 0.09, 0.1);
uniform float opacity : hint_range(0.0, 1.0) = 0.62; // face-on
uniform float reflectivity : hint_range(0.0, 1.0) = 0.6;
uniform float gloss_roughness : hint_range(0.0, 1.0) = 0.035;
uniform vec3 shade_color : source_color = vec3(0.04, 0.09, 0.14);
uniform float shade_band : hint_range(0.0, 1.0) = 1.0;
uniform float frit_width : hint_range(0.0, 0.2) = 0.045;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 nl = normalize(local_normal);
	mat3 l2v = mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX);
	vec3 n_geo = NORMAL;
	float ndv = clamp(dot(n_geo, VIEW), 0.0, 1.0);
	float fp = car_footprint(local_pos);
	float fres = car_schlick(0.04, ndv);

	vec3 col = tint;
	float a = opacity;
	float rough = gloss_roughness;

	// Shade band across the top of forward-facing panes.
	float fwd = smoothstep(-0.15, -0.5, nl.z) * step(0.0001, UV.y);
	float band = smoothstep(0.76, 0.9, UV.y) * fwd * shade_band;
	col = mix(col, shade_color, band * 0.85);
	a = mix(a, 0.9, band * 0.7);

	// Ceramic frit border (opaque black enamel with a dot-fade on its inner edge).
	float frit = 0.0;
	if (UV2.y > 0.0005) {
		float e = UV2.x;
		float solid = 1.0 - smoothstep(frit_width * 0.55, frit_width * 0.55 + fp, e);
		float fade = 1.0 - smoothstep(frit_width * 0.55, frit_width, e);
		vec2 dp = fract(vec2(local_pos.x + local_pos.z, local_pos.y) / 0.006) - 0.5;
		float dots = 1.0 - smoothstep(fade * 0.5 - 0.08, fade * 0.5 + 0.08, length(dp));
		float dot_vis = 1.0 - smoothstep(0.0015, 0.004, fp);
		frit = max(solid, mix(fade * 0.6, dots, dot_vis) * fade);
	}

	// Rain: static beads everywhere, running drops on steep panes.
	float drop = 0.0;
	float rain_w = max(clamp(nt_wetness, 0.0, 1.0), clamp(nt_rain, 0.0, 1.0));
	if (rain_w > 0.001) {
		float vis = 1.0 - smoothstep(0.005, 0.018, fp);
		vec4 d1 = car_beads(local_pos, nl, 0.012, fp, 0.0, 0.2 + 0.45 * rain_w);
		float steep = 1.0 - smoothstep(0.55, 0.9, abs(nl.y));
		float colid = floor((local_pos.x + local_pos.z) / 0.03);
		vec3 rp = local_pos + vec3(0.0, TIME * nt_rain * (0.15 + 0.35 * car_hash12(vec2(colid, 3.7))), 0.0);
		vec4 d2 = car_beads(rp, nl, 0.018, fp, 2.5, 0.35 * clamp(nt_rain, 0.0, 1.0) * steep);
		drop = max(d1.w, d2.w) * vis;
		NORMAL = normalize(n_geo + l2v * ((d1.xyz + d2.xyz) * 1.1 * vis));
		// Water film smooths the pane; drops scatter a little light.
		col += drop * 0.02;
		a = mix(a, min(a + 0.2, 1.0), drop);
	}

	col = mix(col, vec3(0.008), frit);
	a = mix(a, 1.0, frit);
	rough = mix(rough, 0.35, frit);

	// Fresnel-driven opacity: face-on panes see-through, grazing panes a dark mirror.
	a = mix(a, 1.0, clamp(fres * (1.0 + 2.0 * reflectivity), 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 1.0, reflectivity) * (1.0 - frit * 0.6);
	ROUGHNESS = car_spec_aa(n_geo, rough);
	CLEARCOAT = (1.0 - frit) * reflectivity;
	CLEARCOAT_ROUGHNESS = 0.02;
}
