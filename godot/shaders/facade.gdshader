// Procedural building facades: 8 styles (glass office, tiled commercial, mixed-use with shop
// fronts, concrete apartments with balconies...). UV = meters along the perimeter / height,
// UV2.x style, UV2.y per-building seed. Windows light up at night with per-window randomness.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/include/nt_noise.gdshaderinc"

global uniform float nt_night;
global uniform float nt_wetness;

const vec3 BASES[8] = vec3[](
	vec3(0.85, 0.68, 0.45), // Warm Mediterranean Ochre
	vec3(0.88, 0.84, 0.76), // Cream Limestone
	vec3(0.78, 0.48, 0.35), // Tuscan Terracotta / Sienna
	vec3(0.82, 0.64, 0.58), // Riviera Pastel Rose
	vec3(0.80, 0.73, 0.60), // Golden Sandstone
	vec3(0.66, 0.68, 0.58), // Olive Stucco
	vec3(0.48, 0.52, 0.58), // Heritage Slate
	vec3(0.70, 0.45, 0.36)  // Heritage Brick
);

void fragment() {
	int style = int(round(UV2.x));
	float seed = UV2.y;
	vec2 m = UV; // meters
	// Real-world scale: 1.5-1.8 m window bays, 3.4 m commercial / 2.9 m residential floors.
	float bay_w = style <= 3 ? 1.5 + 0.3 * seed : 1.8;
	float floor_h = style <= 3 ? 3.4 : 2.9;
	vec2 cell = vec2(floor(m.x / bay_w), floor(m.y / floor_h));
	vec2 f = vec2(fract(m.x / bay_w), fract(m.y / floor_h));
	vec3 base = BASES[style] * (0.85 + 0.3 * seed);
	// Window rectangle within each bay (curtain wall: thin mullions; others: punched windows).
	vec2 win_min = style == 0 || style == 3 ? vec2(0.05, 0.1) : vec2(0.14, 0.3);
	vec2 win_max = style == 0 || style == 3 ? vec2(0.95, 0.94) : vec2(0.86, 0.82);
	float aa = 0.02;
	float win = smoothstep(win_min.x - aa, win_min.x, f.x) * smoothstep(win_max.x + aa, win_max.x, f.x) *
			smoothstep(win_min.y - aa, win_min.y, f.y) * smoothstep(win_max.y + aa, win_max.y, f.y);
	// Ground floor: shop fronts (commercial) / entrances.
	bool ground = m.y < floor_h * 1.15;
	float h = nt_hash(cell + seed * 97.0);
	vec3 glass = mix(vec3(0.05, 0.07, 0.1), vec3(0.2, 0.28, 0.36), h * 0.5);
	vec3 albedo = mix(base, glass, win);
	float rough = mix(0.85, 0.08, win);
	float metal = style == 0 ? win * 0.3 : 0.0;
	// Balconies on apartments (horizontal bands).
	if (style >= 5) {
		float slab = step(0.9, f.y);
		albedo = mix(albedo, base * 1.15, slab);
		float rail = step(0.1, f.y) * step(f.y, 0.38) * (1.0 - win) ;
		albedo = mix(albedo, base * 0.7, rail * 0.5);
	}
	// Grime streaks below windows and toward the ground.
	float streak = nt_value_noise(vec2(m.x * 1.7, m.y * 0.08) + seed * 10.0);
	albedo *= 0.8 + 0.2 * streak;
	albedo *= mix(0.75, 1.0, smoothstep(0.0, 6.0, m.y));
	// Night: random lit windows in warm/cool tints; shop fronts glow.
	vec3 emit = vec3(0.0);
	if (nt_night > 0.0) {
		// ~30-45% of windows lit, grouped by floor (offices light whole floors), dim and varied so
		// the neon stays the brightest thing on the street.
		float floor_lit = nt_hash(vec2(cell.y, seed * 51.0));
		float lit = step(0.62 - 0.12 * seed, h * 0.6 + floor_lit * 0.4);
		vec3 tint = mix(vec3(1.0, 0.8, 0.55), vec3(0.72, 0.85, 1.0), step(0.55, nt_hash(cell + 3.3)));
		float blind = 0.55 + 0.45 * step(0.5, fract(f.y * 6.0 + h)); // venetian blinds pattern
		emit += tint * win * lit * blind * (0.35 + 0.35 * h) * nt_night;
		if (ground && style <= 4) {
			// Shop fronts: warm or cool interiors with a dark lower counter band.
			vec3 shop = mix(vec3(1.0, 0.78, 0.5), vec3(0.55, 0.85, 1.0), h) * mix(0.45, 0.8, nt_hash(cell + 9.1));
			emit += shop * win * step(0.35, f.y) * nt_night;
		}
	}
	if (ground && style <= 4) {
		albedo = mix(albedo, vec3(0.08, 0.08, 0.09), 1.0 - win);
	}
	float wet = clamp(nt_wetness, 0.0, 1.0);
	ALBEDO = albedo * mix(1.0, 0.8, wet);
	ROUGHNESS = mix(rough, rough * 0.6, wet);
	METALLIC = metal;
	EMISSION = emit;
}
