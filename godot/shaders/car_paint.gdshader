// Automotive multi-layer paint (Mobile renderer), tuned for a 1334x750 handheld screen:
//   base coat  - colour, metallic face/flop, pearl interference flop, candy (Beer-Lambert tint)
//   metallic   - flakes are modelled statistically, never per pixel: a brighter face, darker flop
//                and a soft secondary specular lobe around each highlight (the "glow" of real
//                metallic paint). No per-pixel glints, so no sparkle / glitter at any distance.
//   clear coat - Fresnel-weighted sharp layer (engine IBL + own GGX direct), wet sheen from the
//                nt_wetness global
//   masks      - optional livery texture (blended over / multiplied into the base), dirt, scratches
//   geometry   - dent deformation (8 dents, car-local xyz + depth) driven by the damage model
// Specular anti-aliasing widens roughness where the normal changes quickly across a pixel.
// Uniforms set by CarMaterials.paint_material / CarStage.apply_finish: base_color, pearl_color,
// metallic, roughness, flake_amount, pearl, clearcoat_amount, clearcoat_gloss, candy (+ dirt,
// scratches, dents, livery/use_livery/tint_livery).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

#include "res://shaders/include/nt_noise.gdshaderinc"
#include "res://shaders/include/car_common.gdshaderinc"

global uniform float nt_wetness;

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
uniform sampler2D livery : source_color, hint_default_transparent, filter_linear_mipmap, repeat_enable;
uniform bool use_livery = false;
// Liveries that carry the whole body colour (opaque) are shown as-is; tint_livery multiplies the
// texture by base_color instead, so the player's colour still reads through white-based artwork.
uniform bool tint_livery = false;
uniform sampler2D thin_film_lut : hint_default_black, filter_linear, repeat_disable;
uniform float film_row : hint_range(0.0, 5.0) = 0.0;
uniform bool use_thin_film = false;

varying vec3 local_pos;
varying vec3 local_normal;
varying float v_coat;
varying float v_coat_rough;
varying float v_flake;

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
	vec3 n_geo = NORMAL;
	float ndv = clamp(dot(n_geo, VIEW), 0.0, 1.0);
	float wet = clamp(nt_wetness, 0.0, 1.0);

	// ---- Base coat colour.
	vec3 col = base_color;
	if (use_livery) {
		vec4 l = texture(livery, UV);
		col = tint_livery ? col * l.rgb : mix(col, l.rgb, l.a);
	}
	float graz = 1.0 - ndv;
	float chrome_k = smoothstep(0.9, 1.0, metallic) * (1.0 - smoothstep(0.08, 0.15, roughness));
	if (use_thin_film) {
		vec3 spec_film = texture(thin_film_lut, vec2(ndv, (film_row + 0.5) / 6.0)).rgb;
		col = mix(col, col * spec_film * 1.5, pearl * 0.7);
		col += spec_film * pearl * 0.25 * graz;
	} else {
		col = mix(col, pearl_color, pearl * (graz * graz * 0.9));
		col += pearl * pearl_color * 0.05 * ndv;
	}
	// Metallic face/flop: flakes lie flat in the paint, so panels facing you are brighter and the
	// edges fall away darker - the main visual signature of metallic paint.
	float mflop = metallic * (1.0 - chrome_k);
	col *= mix(1.0, mix(0.5, 1.12, pow(ndv, 0.7)), mflop * 0.8);
	if (candy > 0.0) {
		float path = 1.0 / max(ndv, 0.2);
		vec3 dye = clamp(col, vec3(0.002), vec3(1.0));
		col = mix(col, pow(dye, vec3(0.55 + 0.45 * path)) * 1.2, candy);
	}

	// ---- Dirt build-up (lower body, rear, behind wheels) and scratches (car-local metres; the
	// baked models have the ground at y = 0 and the nose toward -Z).
	vec3 lp = local_pos;
	vec3 nl = normalize(local_normal);
	float grime = 0.0;
	if (dirt > 0.0) {
		float low = smoothstep(0.55, 0.05, lp.y);
		float rear = smoothstep(0.5, 2.2, lp.z);
		float streak = car_vnoise(vec2((lp.x + lp.z) * 9.0, lp.y * 1.5));
		float n = nt_fbm(lp.xy * 3.0 + lp.z, 3);
		grime = clamp(dirt * (low * 0.95 + rear * 0.35 + (1.0 - abs(nl.y)) * 0.15 * streak) * (0.5 + 0.9 * n), 0.0, 1.0);
	}
	float scr = 0.0;
	if (scratches > 0.0) {
		vec2 sp = vec2(lp.x * 31.0 + lp.z * 5.0, lp.y * 1.3 + lp.z * 0.4);
		float line = car_vnoise(vec2(sp.x * 1.3 + sp.y * 17.0, sp.y * 2.0));
		float line2 = car_vnoise(vec2(sp.x * 0.7 - sp.y * 23.0 + 13.0, sp.x * 0.5));
		scr = scratches * max(smoothstep(0.93, 0.975, line), smoothstep(0.95, 0.985, line2) * 0.7);
		scr *= smoothstep(0.1, 0.5, car_vnoise(lp.xz * 2.0 + lp.y));
	}

	// ---- Compose.
	col = mix(col, vec3(0.19, 0.16, 0.12) * (1.0 - 0.45 * wet), grime * 0.85);
	col = mix(col, mix(col, vec3(0.75), 0.6), scr);
	col *= 1.0 - 0.05 * wet;

	float coat = clearcoat_amount * (1.0 - grime * 0.85);
	// Water on a matte/satin finish still forms a glossy film.
	coat = max(coat, wet * 0.7);
	float coat_r = mix(1.0 - clearcoat_gloss, 0.03, wet * 0.8);
	coat_r = mix(coat_r, 0.35, scr * 0.8);
	coat_r = car_spec_aa(n_geo, max(coat_r, 0.03));
	float rough = mix(roughness, 0.9, grime);

	ALBEDO = col;
	METALLIC = mix(metallic, 0.0, grime);
	ROUGHNESS = car_spec_aa(n_geo, rough);
	SPECULAR = 0.5;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = coat_r;
	v_coat = coat;
	v_coat_rough = coat_r;
	v_flake = flake_amount * (1.0 - chrome_k) * (1.0 - grime);
}

// Direct lighting: base GGX under the coat, clear-coat GGX with Fresnel, and a broad "flake glow"
// lobe that metallic paint shows around every highlight.
void light() {
	float cndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 H = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(NORMAL, H), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
	float ldh = clamp(dot(LIGHT, H), 1e-3, 1.0);
	vec3 rad = LIGHT_COLOR * ATTENUATION;

	// Clearcoat Fresnel reflection and transmission
	float fc = v_coat * car_schlick(0.04, ldh);
	float trans = 1.0 - fc;

	// Dielectric diffuse vs metallic: metals absorb diffuse light, dielectrics reflect it
	float diffuse_k = (1.0 - METALLIC) * trans;
	DIFFUSE_LIGHT += rad * (cndl * diffuse_k / PI);

	// Base specular GGX lobe
	float a = max(ROUGHNESS * ROUGHNESS, 0.002);
	vec3 f0 = mix(vec3(0.04), ALBEDO, METALLIC);
	vec3 spec = (car_d_ggx(ndh, a) * car_v_smith(ndv, cndl, a) * trans) * car_schlick3(f0, ldh);

	// Clearcoat GGX lobe: use Smith visibility for physically bounded, non-diverging reflections
	float ac = max(v_coat_rough * v_coat_rough, 0.0012);
	spec += vec3(car_d_ggx(ndh, ac) * car_v_smith(ndv, cndl, ac) * fc);

	// Flake glow: soft subtle secondary lobe for metallic flake shimmer
	if (v_flake > 0.001) {
		float af = 0.16;
		spec += ALBEDO * (car_d_ggx(ndh, af) * car_v_smith(ndv, cndl, af) * v_flake * trans);
	}
	SPECULAR_LIGHT += rad * cndl * spec * SPECULAR_AMOUNT;
}
