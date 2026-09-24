// Automotive multi-layer paint (Mobile renderer):
//   base coat  - colour, metallic face/flop, pearl interference flop, candy (Beer-Lambert tint)
//   flake layer - stochastic mirror flakes that glint per light (2 LOD levels sized to the pixel
//                 footprint, so they sparkle instead of reading as grain), faint IBL speckle up close
//   clear coat - Fresnel-weighted sharp layer (engine IBL + own GGX direct), orange-peel waviness,
//                wet beading/sheeting from the nt_wetness global
//   masks      - panel gaps from UV2.x (metres to seam), baked AO from UV2.y, dirt, scratches
//   geometry   - dent deformation (8 dents, car-local xyz + depth) driven by the damage model
// Specular anti-aliasing widens roughness where the normal changes quickly across a pixel.
// Uniforms set by CarMaterials.paint_material / CarStage.apply_finish: base_color, pearl_color,
// metallic, roughness, flake_amount, pearl, clearcoat_amount, clearcoat_gloss, candy (+ dirt,
// scratches, dents, livery/use_livery). Everything else is derived so live finish previews work.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

#include "res://shaders/include/nt_noise.gdshaderinc"
#include "res://shaders/include/car_common.gdshaderinc"

global uniform float nt_wetness;
global uniform float nt_rain;

uniform vec3 base_color : source_color = vec3(0.8, 0.05, 0.1);
uniform vec3 pearl_color : source_color = vec3(0.2, 0.3, 0.9);
uniform float metallic : hint_range(0.0, 1.0) = 0.6;
uniform float roughness : hint_range(0.0, 1.0) = 0.32;
uniform float flake_amount : hint_range(0.0, 1.0) = 0.5;
uniform float pearl : hint_range(0.0, 1.0) = 0.0;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 1.0;
uniform float clearcoat_gloss : hint_range(0.0, 1.0) = 0.9;
uniform float candy : hint_range(0.0, 1.0) = 0.0;
uniform float dirt : hint_range(0.0, 1.0) = 0.0;
uniform float scratches : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dents[8];
uniform sampler2D livery : source_color, hint_default_transparent, filter_linear_mipmap, repeat_disable;
uniform bool use_livery = false;
// Extras (safe defaults; CarMaterials sets them per car).
uniform vec3 two_tone_color : source_color = vec3(0.02, 0.02, 0.022);
uniform float two_tone_y = -10.0; // car-local Y below which two_tone_color applies (<= -9 = off)
uniform float flake_size : hint_range(0.25, 4.0) = 0.75;
uniform float glint_gain : hint_range(0.0, 100.0) = 8.0;
uniform float panel_gap_width : hint_range(0.0, 0.01) = 0.0022; // half width, metres
uniform float orange_peel : hint_range(0.0, 2.0) = 1.0;
uniform sampler2D thin_film_lut : hint_default_black, filter_linear, repeat_disable;
uniform float film_row : hint_range(0.0, 5.0) = 0.0;
uniform bool use_thin_film = false;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec4 v_fl0;
varying vec4 v_fl1;
varying float v_coat;
varying float v_coat_rough;
varying vec3 v_glint_tint;

void vertex() {
	vec3 v = VERTEX;
	for (int i = 0; i < 8; i++) {
		float depth = dents[i].w;
		if (depth <= 0.0) continue;
		vec3 d = v - dents[i].xyz;
		float r = length(d);
		float fall = smoothstep(0.55, 0.0, r);
		float crumple = 0.7 + 0.6 * nt_value_noise(v.xz * 11.0 + float(i) * 3.7);
		v -= NORMAL * depth * fall * crumple;
	}
	VERTEX = v;
	local_pos = v;
	local_normal = NORMAL;
}

void fragment() {
	vec3 nl = normalize(local_normal);
	mat3 l2v = mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX);
	vec3 n_geo = NORMAL;
	float ndv = clamp(dot(n_geo, VIEW), 0.0, 1.0);
	float fp = car_footprint(local_pos);
	float wet = clamp(nt_wetness, 0.0, 1.0);

	// ---- UV2 contract: x = metres to nearest panel seam, y = baked AO (>= 0.02). (0,0) = absent.
	bool has2 = UV2.y > 0.0005;
	float gap_d = has2 ? UV2.x : 1.0;
	float ao = has2 ? UV2.y : 1.0;

	// ---- Base coat colour.
	vec3 col = base_color;
	if (two_tone_y > -9.0) {
		float fy = fwidth(local_pos.y) + 0.002;
		col = mix(two_tone_color, col, smoothstep(two_tone_y - fy, two_tone_y + fy, local_pos.y));
	}
	if (use_livery) {
		vec4 l = texture(livery, UV);
		col = mix(col, l.rgb, l.a);
	}
	float graz = 1.0 - ndv;
	float chrome_k = smoothstep(0.9, 1.0, metallic) * (1.0 - smoothstep(0.08, 0.15, roughness));
	// Pearl: spectral interference from thin-film LUT when enabled, fallback to pearl_color.
	if (use_thin_film) {
		vec3 spec_film = texture(thin_film_lut, vec2(ndv, (film_row + 0.5) / 6.0)).rgb;
		col = mix(col, col * spec_film * 1.5, pearl * 0.7);
		col += spec_film * pearl * 0.25 * graz;
	} else {
		col = mix(col, pearl_color, pearl * (graz * graz * 0.9));
		col += pearl * pearl_color * 0.06 * ndv;
	}
	// Metallic face/flop: flakes aligned with the panel make the face bright and the flop dark.
	float mflop = metallic * (1.0 - chrome_k);
	col *= mix(1.0, mix(0.42, 1.18, pow(ndv, 0.65)), mflop * 0.85);
	// Candy: light crosses a dyed layer twice; longer path at grazing -> deeper, richer colour.
	if (candy > 0.0) {
		float path = 1.0 / max(ndv, 0.2);
		vec3 dye = clamp(col, vec3(0.002), vec3(1.0));
		col = mix(col, pow(dye, vec3(0.55 + 0.45 * path)) * 1.2, candy);
	}

	// ---- Metallic flakes: two footprint-sized LOD levels, blended.
	v_fl0 = vec4(0.0, 0.0, 1.0, 0.0);
	v_fl1 = vec4(0.0, 0.0, 1.0, 0.0);
	float speck = 0.0;
	if (flake_amount > 0.001) {
		float c0 = 0.0035 * flake_size;
		float lod = log2(max(fp * 2.4 / c0, 1.0));
		float l0 = floor(lod);
		float lt = lod - l0;
		float ca = c0 * exp2(l0);
		vec4 fa = car_flake(local_pos, nl, ca, fp, 0.3);
		vec4 fb = car_flake(local_pos + vec3(0.37, 0.11, 0.73) * ca, nl, ca * 2.0, fp, 0.3);
		v_fl0 = vec4(normalize(l2v * fa.xyz), fa.w * (1.0 - lt));
		v_fl1 = vec4(normalize(l2v * fb.xyz), fb.w * lt);
		// Faint albedo speckle only when flakes are several pixels wide (close-ups).
		speck = fa.w * (1.0 - smoothstep(0.0, 1.2, lod)) * flake_amount;
	}
	v_glint_tint = mix(vec3(1.0), mix(vec3(1.0), pearl_color * 1.6 + 0.2, pearl), 0.85) * mix(vec3(1.0), col * 2.0 + 0.3, candy * 0.6);

	// ---- Normal perturbations (local space): orange peel, panel-edge roll, water beads.
	vec3 nper = vec3(0.0);
	float peel_vis = (1.0 - smoothstep(0.0006, 0.0025, fp)) * orange_peel * clearcoat_amount;
	if (peel_vis > 0.001) {
		vec3 p = local_pos * 1900.0;
		vec3 k1 = vec3(0.83, 0.31, 0.46), k2 = vec3(-0.27, 0.72, 0.64), k3 = vec3(0.51, -0.66, 0.55);
		vec3 g = k1 * cos(dot(k1, p) + sin(p.y * 0.37) * 2.0) + k2 * cos(dot(k2, p) * 1.31) + k3 * cos(dot(k3, p) * 0.77 + 1.7);
		nper += g * 0.012 * peel_vis;
	}
	// Panel gaps: coverage-antialiased dark line, occlusion either side, rolled edge highlight.
	float gw = panel_gap_width;
	float fwd = max(fwidth(gap_d), 1e-5);
	float gap_cov = clamp((gw - gap_d) / fwd + 0.5, 0.0, 1.0) * min(1.0, 2.2 * gw / fwd);
	ao *= mix(0.45, 1.0, smoothstep(gw * 0.5, gw + 0.012, gap_d));
	if (has2 && gap_d < gw + 0.006) {
		vec3 dpdx = dFdx(local_pos);
		vec3 dpdy = dFdy(local_pos);
		vec3 r1 = cross(dpdy, nl);
		vec3 r2 = cross(nl, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = (dFdx(gap_d) * r1 + dFdy(gap_d) * r2) / (abs(det) > 1e-12 ? det : 1e-12);
		float gl = length(grad);
		vec3 away = gl > 1e-4 ? grad / gl : vec3(0.0);
		float roll = 1.0 - smoothstep(gw, gw + 0.005, gap_d);
		nper -= away * roll * 0.9 * (1.0 - smoothstep(0.002, 0.006, fp));
	}
	// Water: beads on up-facing panels, elongated runs on vertical ones; sheeting streaks.
	float bead = 0.0;
	float sheet = 0.0;
	if (wet > 0.001) {
		float up = nl.y;
		float stretch = 2.5 * (1.0 - smoothstep(0.35, 0.8, up));
		float vis = 1.0 - smoothstep(0.004, 0.014, fp);
		vec4 b = car_beads(local_pos, nl, 0.011, fp, stretch, 0.35 + 0.4 * wet);
		vec4 b2 = car_beads(local_pos * 1.7 + 3.1, nl, 0.011, fp * 1.7, stretch, 0.3 * wet);
		bead = max(b.w, b2.w) * vis * smoothstep(0.0, 0.25, wet);
		nper += (b.xyz + b2.xyz) * 0.85 * vis * smoothstep(0.0, 0.25, wet);
		// Sheeting: vertical streaks of thicker water on side panels.
		float side = 1.0 - smoothstep(0.3, 0.7, abs(up));
		float s = car_vnoise(vec2((local_pos.x + local_pos.z) * 38.0, local_pos.y * 3.0 + nt_rain * TIME * 0.4));
		sheet = side * smoothstep(0.55, 0.85, s) * wet;
	}
	NORMAL = normalize(n_geo + l2v * nper);

	// ---- Dirt build-up (lower body, rear, behind wheels) and scratches.
	float grime = 0.0;
	if (dirt > 0.0) {
		float low = smoothstep(0.15, -0.4, local_pos.y);
		float rear = smoothstep(0.5, 2.2, local_pos.z);
		float streak = car_vnoise(vec2((local_pos.x + local_pos.z) * 9.0, local_pos.y * 1.5));
		float n = nt_fbm(local_pos.xy * 3.0 + local_pos.z, 3);
		grime = clamp(dirt * (low * 0.95 + rear * 0.35 + (1.0 - abs(nl.y)) * 0.15 * streak) * (0.5 + 0.9 * n), 0.0, 1.0);
		grime *= 1.0 - 0.35 * wet * sheet;
	}
	float scr = 0.0;
	if (scratches > 0.0) {
		vec2 sp = vec2(local_pos.x * 31.0 + local_pos.z * 5.0, local_pos.y * 1.3 + local_pos.z * 0.4);
		float line = car_vnoise(vec2(sp.x * 1.3 + sp.y * 17.0, sp.y * 2.0));
		float line2 = car_vnoise(vec2(sp.x * 0.7 - sp.y * 23.0 + 13.0, sp.x * 0.5));
		scr = scratches * max(smoothstep(0.93, 0.975, line), smoothstep(0.95, 0.985, line2) * 0.7);
		scr *= smoothstep(0.1, 0.5, car_vnoise(local_pos.xz * 2.0 + local_pos.y));
	}

	// ---- Compose.
	col *= 1.0 + speck * 0.35;
	col = mix(col, vec3(0.19, 0.16, 0.12) * (1.0 - 0.45 * wet), grime * 0.85);
	col = mix(col, mix(col, vec3(0.75), 0.6), scr);
	col *= 1.0 - 0.04 * wet - bead * 0.06;
	col = mix(col, col * 0.06, gap_cov);

	float coat = clearcoat_amount * (1.0 - grime * 0.85) * (1.0 - gap_cov);
	// Water on a matte/satin finish still forms a glossy film.
	coat = max(coat, wet * 0.85 * (1.0 - gap_cov) * max(bead, 0.55 + 0.45 * sheet));
	float coat_r = mix(1.0 - clearcoat_gloss, 0.02, max(wet * 0.8, bead));
	coat_r = mix(coat_r, 0.35, scr * 0.8);
	coat_r = car_spec_aa(n_geo, max(coat_r, 0.03));
	float rough = mix(roughness, 0.9, grime);
	rough = mix(rough, 0.95, gap_cov);
	rough = mix(rough, 0.08, bead * (1.0 - clearcoat_amount));

	ALBEDO = col;
	METALLIC = mix(metallic, 0.0, max(grime, gap_cov));
	ROUGHNESS = car_spec_aa(n_geo, rough);
	SPECULAR = 0.5;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = coat_r;
	AO = ao;
	AO_LIGHT_AFFECT = 0.2;
	v_coat = coat;
	v_coat_rough = coat_r;
}

// Direct lighting: base GGX (under the coat), clear-coat GGX with Fresnel, per-light flake glints.
void light() {
	float cndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 H = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(NORMAL, H), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
	float ldh = clamp(dot(LIGHT, H), 1e-3, 1.0);
	vec3 rad = LIGHT_COLOR * ATTENUATION;
	float fc = v_coat * car_schlick(0.04, ldh);
	float trans = 1.0 - fc;
	DIFFUSE_LIGHT += rad * (cndl * trans / PI);

	float a = max(ROUGHNESS * ROUGHNESS, 0.002);
	vec3 f0 = mix(vec3(0.04), ALBEDO, METALLIC);
	vec3 spec = (car_d_ggx(ndh, a) * car_v_smith(ndv, cndl, a) * trans) * car_schlick3(f0, ldh);
	float ac = max(v_coat_rough * v_coat_rough, 0.0012);
	spec += vec3(car_d_ggx(ndh, ac) * (0.25 / (ldh * ldh)) * fc);
	float g0 = smoothstep(0.998, 0.9996, dot(v_fl0.xyz, H)) * v_fl0.w;
	float g1 = smoothstep(0.998, 0.9996, dot(v_fl1.xyz, H)) * v_fl1.w;
	spec += v_glint_tint * ((g0 + g1) * flake_amount * glint_gain * trans * clamp(METALLIC * 1.0, 0.1, 0.6));
	SPECULAR_LIGHT += rad * cndl * spec * SPECULAR_AMOUNT;
}
