// Wet-capable asphalt with procedural aggregate, tire-worn lanes, Japanese road markings,
// crown-drained puddles and rain ripples. UV.x: 0..1 across the road, UV.y: along (per repeat).
// UV2.x: lanes*10 + marking style, UV2.y: road width in meters. COLOR.r: ambient occlusion.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/nt_noise.gdshaderinc"

global uniform float nt_wetness;
global uniform float nt_rain;
global uniform float nt_snow;

uniform vec3 asphalt_color : source_color = vec3(0.18, 0.18, 0.19);
uniform vec3 asphalt_light : source_color = vec3(0.28, 0.28, 0.29);
uniform vec3 marking_white : source_color = vec3(0.88, 0.88, 0.86);
uniform vec3 marking_yellow : source_color = vec3(0.96, 0.70, 0.14);
uniform float uv_length = 12.0;
uniform float wear = 0.5;
uniform float age = 0.5;

varying vec3 world_pos;

float band(float x, float center, float half_w) {
	float aa = fwidth(x) * 1.2;
	return 1.0 - smoothstep(half_w - aa, half_w + aa, abs(x - center));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Junction patch markings. UV 0..1 over the patch; size (x, z) in meters.
float junction_marks(int style, vec2 uv, vec2 size, out vec3 col) {
	col = vec3(0.86, 0.86, 0.84);
	vec2 m = uv * size;
	float mark = 0.0;
	if (style == 1 || style == 2) {
		// Zebra crossings across each approach, with proportional depth and setback.
		float z_depth = min(3.5, min(size.x, size.y) * 0.22);
		float z_back = min(1.0, min(size.x, size.y) * 0.06);
		float band_x = step(z_back, m.x) * step(m.x, z_back + z_depth) + step(size.x - (z_back + z_depth), m.x) * step(m.x, size.x - z_back);
		float band_z = step(z_back, m.y) * step(m.y, z_back + z_depth) + step(size.y - (z_back + z_depth), m.y) * step(m.y, size.y - z_back);
		float stripes_z = step(0.5, fract(m.x / 1.0)); // stripes run along z across the x-bands
		float stripes_x = step(0.5, fract(m.y / 1.0));
		mark = max(band_z * stripes_z * step(z_back + z_depth, m.x) * step(m.x, size.x - (z_back + z_depth)), band_x * stripes_x * step(z_back + z_depth, m.y) * step(m.y, size.y - (z_back + z_depth)));
		if (style == 2) {
			// Shibuya scramble: diagonal crossings through the middle.
			vec2 c = m - size * 0.5;
			float d1 = abs(c.x - c.y) / 1.414;
			float d2 = abs(c.x + c.y) / 1.414;
			float along1 = (c.x + c.y) / 1.414;
			float along2 = (c.x - c.y) / 1.414;
			float diag = max(step(d1, 1.8) * step(0.5, fract(along1 / 1.0)), step(d2, 1.8) * step(0.5, fract(along2 / 1.0)));
			float inner = step(4.8, m.x) * step(m.x, size.x - 4.8) * step(4.8, m.y) * step(m.y, size.y - 4.8);
			mark = max(mark, diag * inner);
		}
	} else if (style == 3) {
		// Parking bays: 2.5 m wide, 5.5 m deep rows with a 7 m aisle.
		float row = mod(m.y, 18.0);
		float bay_line = step(fract(m.x / 2.5), 0.05);
		float in_bay = step(row, 5.5) + step(12.5, row);
		mark = bay_line * clamp(in_bay, 0.0, 1.0);
		mark = max(mark, step(abs(row - 5.5), 0.07) + step(abs(row - 12.5), 0.07));
	}
	return clamp(mark, 0.0, 1.0);
}

void fragment() {
	float code = UV2.x;
	if (code > 79.5) {
		int jstyle = int(round(code - 80.0));
		vec2 size = vec2(max(UV2.y, 1.0), max(COLOR.a, 1.0));
		vec2 wpj = world_pos.xz;
		float n1j = nt_value_noise(wpj * 3.1);
		float n2j = nt_value_noise(wpj * 17.0);
		vec3 basej = mix(asphalt_color, asphalt_light, n1j * 0.35 + n2j * 0.25);
		if (jstyle == 4) basej = mix(vec3(0.4, 0.4, 0.39), vec3(0.5, 0.5, 0.48), n1j);
		vec3 mcol;
		float mk = junction_marks(jstyle, UV, size, mcol);
		mk *= 1.0 - 0.45 * smoothstep(0.4, 0.85, nt_value_noise(wpj * 5.0)) * wear;
		vec3 alb = mix(basej, mcol, mk);
		float rgh = mix(0.86, 0.55, mk);
		float wetj = clamp(nt_wetness * 1.25, 0.0, 1.0);
		float pud = nt_puddle(wpj, nt_wetness);
		alb *= mix(1.0, 0.52, wetj);
		alb = mix(alb, alb * 0.35, pud);
		rgh = mix(rgh, 0.28, wetj);
		rgh = mix(rgh, 0.03, pud);
		vec2 ripj = nt_ripples(wpj, TIME, nt_rain) * (0.25 + pud * 0.75);
		NORMAL_MAP = normalize(vec3(ripj, 1.0)) * 0.5 + 0.5;
		ALBEDO = alb;
		ROUGHNESS = rgh;
		SPECULAR = mix(0.5, 0.65, wetj);
	} else {
	float lanes = floor(code / 10.0);
	float style = code - lanes * 10.0;
	float width = max(UV2.y, 1.0);
	float across_m = UV.x * width; // meters from the left edge
	float along_m = UV.y * uv_length;

	// Aggregate: three noise scales + sparse bright stones + micro-crack detail.
	vec2 wp = world_pos.xz;
	float n1 = nt_value_noise(wp * 3.1);
	float n2 = nt_value_noise(wp * 17.0);
	float stones = step(0.86, nt_value_noise(wp * 41.0));
	float micro_cracks = nt_value_noise(wp * 65.0) * 0.12;  // Fine crack detail
	float patch_n = nt_fbm(wp * 0.05, 3);
	vec3 base = mix(asphalt_color, asphalt_light, n1 * 0.35 + n2 * 0.25 + stones * 0.4 + micro_cracks);
	// Resurfacing patches of darker, newer asphalt.
	base = mix(base, asphalt_color * 0.72, smoothstep(0.62, 0.66, patch_n) * age);
	// Polished wheel paths: two per lane, darker and smoother with rubber deposits.
	float lane_w = width / max(lanes, 1.0);
	float lane_pos = mod(across_m, lane_w);
	float tracks = band(lane_pos, lane_w * 0.28, 0.38) + band(lane_pos, lane_w * 0.72, 0.38);
	// Tire rubber darkens the polished paths (GT7-style)
	base *= 1.0 - tracks * 0.22 * wear;
	base = mix(base, base * vec3(0.92, 0.90, 0.88), tracks * 0.15 * wear);  // Slight warm tint from rubber
	float rough = mix(0.88, 0.68, tracks * wear) - stones * 0.12 - micro_cracks * 0.3;

	// ---- Markings (Japanese conventions) ----
	float mark = 0.0;
	vec3 mark_col = marking_white;
	float lw = 0.15; // half widths below are in meters
	float dash12 = step(fract(along_m / 12.0), 0.42); // 5 m dash / 7 m gap

	// Outer edge lines: always delineate road boundaries
	mark = max(mark, band(across_m, 0.35, 0.075));
	mark = max(mark, band(across_m, width - 0.35, 0.075));

	if (style > 0.5 && style < 1.5) { // 2-lane: dashed white centre
		mark = max(mark, band(across_m, width * 0.5, 0.075) * dash12);
	} else if (style > 1.5 && style < 2.5) { // no-overtaking double yellow
		float y = max(band(across_m, width * 0.5 - 0.14, 0.06), band(across_m, width * 0.5 + 0.14, 0.06));
		if (y > mark) { mark = y; mark_col = marking_yellow; }
	} else if (style > 2.5 && style < 3.5) { // expressway lanes: dashed white dividers
		for (float k = 1.0; k < 6.0; k += 1.0) {
			if (k >= lanes) break;
			mark = max(mark, band(across_m, lane_w * k, lw * 0.5) * step(fract(along_m / 20.0), 0.4));
		}
	} else if (style > 3.5 && style < 4.5) { // touge: solid yellow centre
		float y = band(across_m, width * 0.5, 0.075);
		if (y > mark) { mark = y; mark_col = marking_yellow; }
	}
	// Worn paint: breaks up where tires run.
	mark *= 1.0 - 0.55 * smoothstep(0.35, 0.8, nt_value_noise(wp * 6.0)) * wear;
	vec3 albedo = mix(base, mark_col, mark);
	rough = mix(rough, 0.55, mark);

	// Retro-reflective road studs (cat-eyes) along center & edges every 14m — brighter, directional
	float stud_hit = step(mod(along_m, 14.0), 0.35);
	float stud_c = band(across_m, width * 0.5, 0.07) * stud_hit;
	float stud_e = (band(across_m, 0.35, 0.07) + band(across_m, width - 0.35, 0.07)) * stud_hit;
	float cat_eye = max(stud_c, stud_e);
	// Cat-eye glass lens roughness (GT7-style sharp reflector)
	rough = mix(rough, 0.15, cat_eye);

	// ---- Wetness (GT7-quality specular response) ----
	float wet = nt_wetness;
	float puddle = nt_puddle(wp, wet);
	float edge = 1.0 - smoothstep(0.0, 1.6, min(across_m, width - across_m));
	puddle = clamp(puddle + edge * wet * 0.35 * smoothstep(0.4, 0.7, nt_value_noise(wp * 0.7)), 0.0, 1.0);
	float wet_surface = clamp(wet * 1.25, 0.0, 1.0);
	albedo *= mix(1.0, 0.50, wet_surface);  // Darker when wet
	albedo = mix(albedo, albedo * 0.30, puddle);  // Deep puddle reflection
	rough = mix(rough, 0.22, wet_surface);  // Smoother when wet
	rough = mix(rough, 0.02, puddle);  // Mirror-like puddles
	vec2 rip = nt_ripples(wp, TIME, nt_rain) * (0.25 + puddle * 0.75);
	vec2 grain = vec2(n1 - 0.5, n2 - 0.5) * 0.24;
	NORMAL_MAP = normalize(vec3(rip + grain * (1.0 - puddle * 0.8), 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// ---- Snow: wind-drift patterns (GT7 Nürburgring style) ----
	float wind_drift = nt_value_noise(wp * 0.15 + vec2(3.7, 1.2));
	float snow_cover = nt_snow * (1.0 - tracks * 0.85) * smoothstep(0.25, 0.55, nt_fbm(wp * 0.3, 2) + nt_snow * 0.4 + wind_drift * 0.15);
	albedo = mix(albedo, vec3(0.85, 0.87, 0.91), snow_cover);
	rough = mix(rough, 0.72, snow_cover);

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.55, 0.90, wet_surface + puddle * 0.15 + stones * 0.1);
	CLEARCOAT = puddle * 0.9;
	CLEARCOAT_ROUGHNESS = 0.02;
	EMISSION = cat_eye * vec3(1.0, 0.88, 0.45) * 3.5;  // Brighter, warmer cat-eyes
	AO = COLOR.r;
	AO_LIGHT_AFFECT = 0.4;
	}
}
