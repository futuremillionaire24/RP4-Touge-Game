// Real (baked) prop models: tools/carbake/props.mjs -> assets/props. Textured albedo with
// alpha-tested foliage, wind sway rising with height, per-instance colour variation
// (INSTANCE_CUSTOM.x), season tint on foliage, wet darkening, snow caps and a night glow on
// lamp heads (downward faces above lamp_y).
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

global uniform float nt_night;
global uniform float nt_season;
global uniform float nt_snow;
global uniform float nt_wetness;
global uniform vec3 nt_wind;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_tex = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform bool cutout = false;
uniform bool foliage = false;
uniform float roughness = 0.85;
uniform float metallic = 0.0;
// Sway: 0 below sway_from (m), full at model_height; sway_amount scales the wind push.
uniform float model_height = 10.0;
uniform float sway_from = 1.5;
uniform float sway_amount = 0.0;
uniform float lamp_y = 1e6;
uniform bool bob = false; // boats: heave, roll and pitch on the swell

varying float variation;
varying vec3 local_pos;

void vertex() {
	variation = INSTANCE_CUSTOM.x;
	local_pos = VERTEX;
	if (bob) {
		float ph = dot(MODEL_MATRIX[3].xz, vec2(0.13, 0.07)) + TIME * 0.7;
		VERTEX.y += sin(ph) * 0.07 + VERTEX.x * sin(ph * 0.8 + 1.0) * 0.012 + VERTEX.z * sin(ph * 0.6 + 2.0) * 0.004;
	}
	if (sway_amount > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float k = smoothstep(sway_from, model_height, VERTEX.y);
		float ph = dot(MODEL_MATRIX[3].xz, vec2(0.13, 0.17)) + variation * 6.28;
		vec3 w = nt_wind * (sin(TIME * 1.1 + ph) * 0.6 + sin(TIME * 2.7 + ph * 1.7) * 0.25);
		// Leaf flutter: small high-frequency motion per vertex on foliage.
		float fl = foliage ? sin(TIME * 7.0 + dot(wp, vec3(1.7, 2.3, 1.1))) * 0.04 * length(nt_wind) : 0.0;
		VERTEX += (inverse(mat3(MODEL_MATRIX)) * (w * k * sway_amount + vec3(fl, fl * 0.5, fl)));
	}
}

vec3 season_tint(vec3 c) {
	float s = nt_season;
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	vec3 spring = c * vec3(1.0, 1.08, 0.92);
	vec3 summer = c;
	vec3 autumn = mix(c, vec3(lum * 1.9, lum * 0.95, lum * 0.3), 0.55 + 0.35 * step(0.5, variation));
	vec3 winter = mix(c, vec3(lum * 1.1, lum, lum * 0.8), 0.55);
	return s < 1.0 ? mix(spring, summer, s) : (s < 2.0 ? mix(summer, autumn, s - 1.0) : mix(autumn, winter, s - 2.0));
}

void fragment() {
	vec4 t = has_tex ? texture(albedo_tex, UV) : vec4(1.0);
	vec3 c = t.rgb * base_color.rgb;
	if (cutout) {
		ALPHA = t.a * base_color.a;
		ALPHA_SCISSOR_THRESHOLD = 0.4;
	}
	// Per-instance variation: +-10% brightness, slight hue shift on foliage.
	c *= 0.9 + 0.2 * variation;
	if (foliage) {
		c = season_tint(c * vec3(1.0 + (variation - 0.5) * 0.12, 1.0, 1.0 - (variation - 0.5) * 0.12));
		// Back-lit leaves: a little transmission.
		BACKLIGHT = c * 0.35;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	float rough = roughness;
	float wet = clamp(nt_wetness, 0.0, 1.0);
	c *= mix(1.0, 0.72, wet);
	rough = mix(rough, rough * 0.55, wet);
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	float snow = clamp(nt_snow * 1.6 - (1.0 - up) * 2.0, 0.0, 1.0);
	c = mix(c, vec3(0.88, 0.9, 0.94), snow);
	if (local_pos.y > lamp_y && up < -0.3) {
		EMISSION = vec3(1.0, 0.84, 0.6) * mix(0.0, 9.0, nt_night);
		c = mix(c, vec3(0.95), 0.6);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metallic;
}
