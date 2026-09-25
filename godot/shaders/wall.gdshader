// Road walls: tunnel barriers and bridge decks (UV2.x 0: board-formed concrete), retaining walls on
// mountain cuts and fills (1: dressed Riviera limestone in courses, coping stone on top when
// UV2.y = 1) and tunnel portals (2: concrete, black/yellow hazard chevrons within 0.6 m of the arch
// edge, UV2.y = metres from it). Textures come from the facade array (Poly Haven CC0), mapped in
// world space so any wall orientation tiles at true scale. COLOR.r: ambient occlusion.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/include/nt_noise.gdshaderinc"
#include "res://shaders/include/env_layers.gdshaderinc"

global uniform float nt_wetness;
global uniform float nt_snow;

uniform sampler2DArray facade_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray facade_normal : filter_linear_mipmap_anisotropic, repeat_enable;

const float F_STONE = 3.0;
const float F_CONCRETE = 4.0;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 N = normalize(world_nrm);
	bool flat_face = abs(N.y) > 0.6;
	// Horizontal run along the wall (metres) and height; caps and soffits map on x/z.
	vec3 T = flat_face ? vec3(1.0, 0.0, 0.0) : normalize(vec3(-N.z, 0.0, N.x));
	vec3 B = flat_face ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	vec2 m = flat_face ? world_pos.xz : vec2(dot(world_pos, T), world_pos.y);
	int kind = int(round(UV2.x));
	float layer = kind == 1 ? F_STONE : F_CONCRETE;
	float tile = kind == 1 ? 2.0 : 2.71;
	vec4 a = texture(facade_albedo, vec3(m / tile, layer));
	vec4 n = texture(facade_normal, vec3(m / tile, layer));
	vec3 albedo;
	float rough = mix(0.8, 0.95, n.b);
	float aa = max(fwidth(m.x), fwidth(m.y)) + 0.002;
	if (kind == 1) {
		// Coursed limestone: 0.45 m courses, blocks 0.6-1.4 m long, recessed mortar joints.
		float course = floor(m.y / 0.45);
		float bl = 0.6 + 0.8 * nt_hash(vec2(course, 3.1));
		float bx = m.x / bl + nt_hash(vec2(course, 7.7));
		float jy = abs(fract(m.y / 0.45) - 0.5) * 0.45;
		float jx = abs(fract(bx) - 0.5) * bl;
		float joint = smoothstep(0.225 - 0.018 - aa, 0.225 - 0.018 + aa, jy);
		joint = max(joint, flat_face ? 0.0 : smoothstep(bl * 0.5 - 0.018 - aa, bl * 0.5 - 0.018 + aa, jx));
		float tone = nt_hash(vec2(floor(bx), course));
		albedo = mix(vec3(0.78, 0.72, 0.6), vec3(0.86, 0.82, 0.72), tone) * (a.rgb / max(textureLod(facade_albedo, vec3(0.5, 0.5, layer), 12.0).rgb, vec3(0.05)));
		albedo = mix(albedo, vec3(0.52, 0.5, 0.46), joint);
		if (UV2.y > 0.5) albedo = vec3(0.84, 0.82, 0.77) * (0.9 + 0.1 * a.rgb); // coping stone
	} else {
		// Board-formed concrete with lift lines every 1.2 m.
		albedo = a.rgb * vec3(0.95, 0.94, 0.92);
		float lift = 1.0 - smoothstep(0.0, 0.02 + aa, abs(fract(m.y / 1.2) - 0.5) * 1.2 - 0.57);
		albedo *= 1.0 - 0.12 * lift * (flat_face ? 0.0 : 1.0);
		if (kind == 2 && UV2.y < 0.6) {
			// Hazard chevrons around the portal opening.
			float stripe = step(0.5, fract((m.x + m.y) / 0.6));
			albedo = mix(vec3(0.95, 0.72, 0.05), vec3(0.04), stripe);
			rough = 0.55;
		}
	}
	// Water run-off streaks and grime at the foot.
	albedo *= 0.85 + 0.15 * nt_value_noise(vec2(m.x * 1.7, m.y * 0.08));
	float wet = clamp(nt_wetness, 0.0, 1.0);
	albedo *= mix(1.0, 0.7, wet);
	rough = mix(rough, 0.35, wet);
	albedo = mix(albedo, vec3(0.88, 0.9, 0.93), flat_face ? clamp(nt_snow * 1.3, 0.0, 1.0) * step(0.0, N.y) : 0.0);
	vec3 Nw = env_perturb(N, T, B, n.rg, 0.8);
	NORMAL = normalize((VIEW_MATRIX * vec4(Nw, 0.0)).xyz);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	AO = COLOR.r;
}
