// Ambient traffic car (MultiMesh). One shader for every surface of the "lite" traffic bakes
// (tools/carbake): part 0 = body (baked vertex colours), 1 = paint (instance colour from a real-world
// European colour mix), 2 = glass, 3 = head lamps, 4 = tail lamps.
// INSTANCE_CUSTOM = (colour seed, knocked loose, speed/30, odometer metres).
// Wheel vertices carry their hub (z, y) in UV2 and spin around it from the odometer.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float nt_night;
global uniform float nt_wetness;

uniform int part = 0;
uniform float wheel_radius = 0.32;
uniform vec3 origin_offset = vec3(0.0); // model origin -> traffic car centre (sim frame)

varying vec3 v_paint;
varying float v_loose;

// Share of cars per colour roughly follows European registrations: grey/silver, black, white,
// blue, red, then a few greens/beiges.
vec3 paint_colour(float s) {
	if (s < 0.22) return vec3(0.55, 0.56, 0.58); // silver
	if (s < 0.36) return vec3(0.18, 0.19, 0.2); // graphite
	if (s < 0.52) return vec3(0.015, 0.015, 0.018); // black
	if (s < 0.68) return vec3(0.85, 0.85, 0.83); // white
	if (s < 0.79) return vec3(0.04, 0.09, 0.25); // dark blue
	if (s < 0.87) return vec3(0.42, 0.03, 0.03); // red
	if (s < 0.92) return vec3(0.06, 0.16, 0.1); // green
	if (s < 0.96) return vec3(0.45, 0.38, 0.28); // beige
	return vec3(0.12, 0.3, 0.55); // light blue
}

void vertex() {
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	v_loose = INSTANCE_CUSTOM.g;
	if (UV2.y > -50.0 && v_loose < 0.5) {
		// Rolling forward (-Z) turns the wheel top toward -Z: rotate about +X by -angle.
		float a = -INSTANCE_CUSTOM.a / max(wheel_radius, 0.1);
		float c = cos(a), s = sin(a);
		vec2 hub = vec2(UV2.y, UV2.x); // (y, z)
		vec2 p = v.yz - hub;
		v.yz = hub + vec2(p.x * c - p.y * s, p.x * s + p.y * c);
		n.yz = vec2(n.y * c - n.z * s, n.y * s + n.z * c);
	}
	VERTEX = v + origin_offset;
	NORMAL = n;
	v_paint = paint_colour(INSTANCE_CUSTOM.r);
}

void fragment() {
	float wet = clamp(nt_wetness, 0.0, 1.0);
	if (part == 1) {
		ALBEDO = v_paint;
		METALLIC = 0.35;
		ROUGHNESS = mix(0.28, 0.12, wet);
		CLEARCOAT = 0.8;
		CLEARCOAT_ROUGHNESS = 0.08;
	} else if (part == 2) {
		ALBEDO = vec3(0.02, 0.025, 0.03);
		ROUGHNESS = 0.05;
		SPECULAR = 0.6;
	} else if (part == 3) {
		ALBEDO = vec3(0.8, 0.82, 0.85);
		ROUGHNESS = 0.1;
		EMISSION = vec3(1.0, 0.97, 0.9) * nt_night * 3.0;
	} else if (part == 4) {
		ALBEDO = vec3(0.35, 0.02, 0.02);
		ROUGHNESS = 0.15;
		EMISSION = vec3(1.0, 0.04, 0.02) * (0.15 + nt_night * 1.8);
	} else {
		ALBEDO = COLOR.rgb;
		ROUGHNESS = mix(0.6, 0.35, wet);
		METALLIC = 0.0;
	}
}
