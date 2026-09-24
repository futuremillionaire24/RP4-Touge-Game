// Shared shader for all instanced props. Vertex COLOR.rgb = base colour, COLOR.a = wind sway
// weight. UV.x = material id: 0 plain, 1 foliage, 2 blossom, 3 lamp head, 4 vending/sign light,
// 5 instance paint, 6 traffic signal, 7 metal. INSTANCE_CUSTOM.x = per-instance variation.
shader_type spatial;
render_mode cull_back, diffuse_burley;

global uniform float nt_night;
global uniform float nt_season;
global uniform float nt_snow;
global uniform float nt_wetness;
global uniform vec3 nt_wind;

varying float mat_id;
varying float variation;
varying vec3 world_pos;

const vec3 PAINTS[6] = vec3[](vec3(0.62, 0.09, 0.06), vec3(0.1, 0.25, 0.55), vec3(0.12, 0.42, 0.24), vec3(0.8, 0.55, 0.1), vec3(0.72, 0.72, 0.7), vec3(0.45, 0.2, 0.45));

void vertex() {
	mat_id = UV.x;
	variation = INSTANCE_CUSTOM.x;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = COLOR.a;
	if (sway > 0.0) {
		float ph = dot(wp.xz, vec2(0.13, 0.17)) + variation * 6.28;
		vec3 w = nt_wind * (sin(TIME * 1.3 + ph) * 0.6 + sin(TIME * 2.9 + ph * 1.7) * 0.25);
		VERTEX += (inverse(mat3(MODEL_MATRIX)) * w) * sway * 0.25;
	}
	world_pos = wp;
}

vec3 foliage_color(vec3 base) {
	float s = nt_season;
	vec3 spring = base * vec3(1.0, 1.12, 0.9);
	vec3 summer = base * vec3(0.8, 0.95, 0.75);
	vec3 autumn = mix(base, vec3(0.55, 0.22, 0.06), 0.8 * step(0.5, variation) + 0.4);
	vec3 winter = mix(base, vec3(0.3, 0.25, 0.18), 0.6);
	return s < 1.0 ? mix(spring, summer, s) : (s < 2.0 ? mix(summer, autumn, s - 1.0) : mix(autumn, winter, s - 2.0));
}

void fragment() {
	vec3 c = COLOR.rgb * (0.9 + 0.2 * variation);
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	int id = int(round(mat_id));
	if (id == 1) {
		c = foliage_color(COLOR.rgb) * (0.85 + 0.3 * variation);
	} else if (id == 2) {
		// Sakura: pink blossom in spring, green leaves in summer, red in autumn, bare-ish in winter.
		float s = nt_season;
		vec3 pink = vec3(0.95, 0.68, 0.78);
		vec3 green = vec3(0.2, 0.34, 0.12);
		vec3 red = vec3(0.6, 0.18, 0.08);
		vec3 bare = vec3(0.3, 0.24, 0.2);
		c = s < 1.0 ? mix(pink, green, smoothstep(0.6, 1.0, s)) : (s < 2.0 ? mix(green, red, s - 1.0) : mix(red, bare, s - 2.0));
		c *= 0.85 + 0.3 * variation;
	} else if (id == 3) {
		emit = vec3(1.0, 0.82, 0.55) * mix(0.0, 7.0, nt_night);
		c = vec3(0.9);
	} else if (id == 4) {
		emit = mix(vec3(0.8, 0.9, 1.0), vec3(1.0, 0.9, 0.7), variation) * mix(0.6, 3.0, nt_night);
		c = vec3(0.8);
	} else if (id == 5) {
		c = PAINTS[int(variation * 5.99)] * (0.85 + 0.2 * fract(variation * 17.0));
		rough = 0.6;
		metal = 0.3;
	} else if (id == 6) {
		// Signal heads: red -> green -> amber cycle, offset per corner.
		float phase = fract(TIME / 30.0 + variation);
		vec3 lamp = phase < 0.45 ? vec3(1.0, 0.1, 0.05) : (phase < 0.9 ? vec3(0.1, 1.0, 0.6) : vec3(1.0, 0.6, 0.05));
		emit = lamp * mix(2.0, 5.0, nt_night);
		c = vec3(0.1);
	} else if (id == 7) {
		metal = 0.8;
		rough = 0.4;
	} else if (id == 8) {
		emit = vec3(1.0, 0.04, 0.02) * mix(0.8, 4.5, nt_night);
		c = vec3(0.5, 0.05, 0.05);
	}
	float wet = clamp(nt_wetness, 0.0, 1.0);
	c *= mix(1.0, 0.75, wet);
	rough = mix(rough, rough * 0.6, wet);
	// Snow caps on upward faces.
	float snow = clamp(nt_snow * 1.6 - (1.0 - NORMAL.y) * 2.0, 0.0, 1.0) * step(0.5, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
	c = mix(c, vec3(0.88, 0.9, 0.94), snow);
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
