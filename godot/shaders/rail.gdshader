// European galvanized W-beam guardrail with realistic corrugation, zinc spangle crystals,
// vertical post shadows, retro-reflective cat-eyes, and wetness response.
// UV.x: length along the rail (in 4m intervals); UV.y: 0.0 top to 1.0 bottom.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/nt_noise.gdshaderinc"

global uniform float nt_wetness;
global uniform float nt_night;

uniform vec3 metal_color : source_color = vec3(0.74, 0.76, 0.78);
uniform vec3 zinc_dark : source_color = vec3(0.58, 0.60, 0.62);
uniform float roughness_base = 0.32;
uniform float metallic_base = 0.88;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wp = world_pos.xz;
	float along = UV.x * 4.0; // meters along the rail
	float v = clamp(UV.y, 0.0, 1.0);

	// ---- W-beam normal corrugation ----
	// A W-beam has two convex ridges and a central concave trough:
	// y=0 top lip, y~0.22 upper crown, y=0.5 valley, y~0.78 lower crown, y=1 bottom lip.
	float w_slope = -cos(v * 6.2831853);
	// Normal tilt in Y direction based on derivative of W-profile
	vec3 nrm = normalize(vec3(0.0, w_slope * 0.45, 1.0));

	// ---- Galvanized zinc crystal spangles ----
	float spangle1 = nt_value_noise(vec2(along * 6.5, v * 12.0));
	float spangle2 = nt_value_noise(vec2(along * 22.0, v * 35.0));
	float spangles = mix(spangle1, spangle2, 0.35);

	// Steel albedo modulated by galvanized crystal grain
	vec3 alb = mix(zinc_dark, metal_color, 0.4 + 0.6 * spangles);

	// Post shadows: every 2 meters, bracket attaches to vertical post
	float post_phase = fract(along / 2.0);
	float post_shadow = smoothstep(0.0, 0.06, post_phase) * (1.0 - smoothstep(0.08, 0.14, post_phase));
	alb *= 1.0 - post_shadow * 0.28;

	// Road spray and soil grime on lower third
	float road_grime = smoothstep(0.5, 1.0, v) * 0.35;
	alb = mix(alb, vec3(0.45, 0.44, 0.42), road_grime);

	// ---- Reflective Cat-Eyes / Delineators ----
	// Mounted in the central trough every 4 meters
	float reflector_phase = fract(UV.x);
	float in_refl_x = step(0.015, reflector_phase) * (1.0 - step(0.065, reflector_phase));
	float in_refl_y = step(0.40, v) * (1.0 - step(0.60, v));
	float is_reflector = in_refl_x * in_refl_y;

	// European delineators: amber/white retro-reflective with micro-prismatic facets
	vec3 refl_col = vec3(1.0, 0.72, 0.15); // amber reflector
	alb = mix(alb, refl_col, is_reflector);
	float rgh = mix(roughness_base, 0.12, is_reflector);
	float met = mix(metallic_base, 0.1, is_reflector);

	// Headlight retro-reflective emission at night
	float refl_glow = is_reflector * nt_night * 2.5;

	// Wetness response
	float wet = clamp(nt_wetness * 1.2, 0.0, 1.0);
	alb *= mix(1.0, 0.75, wet);
	rgh = mix(rgh, 0.08, wet);

	ALBEDO = alb;
	ROUGHNESS = rgh;
	METALLIC = met;
	SPECULAR = mix(0.6, 0.95, is_reflector);
	NORMAL_MAP = nrm * 0.5 + 0.5;
	EMISSION = refl_col * refl_glow;
}
