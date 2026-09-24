// Presentation environment sky: an analytic "room" (floor pool, walls, ceiling) plus up to 12
// emissive panels (softboxes, strip lights, neon tubes) ray-traced from the subject's position.
// It is only sampled for the radiance / irradiance maps (paint, glass and clearcoat reflections,
// ambient light), so it costs nothing per frame unless it is also the visible background.
// Panels: centre c, half-extent vectors u and v (the panel is c + a*u + b*v, |a|,|b| <= 1),
// colour (rgb already multiplied by energy) and edge softness in panel_col.a.
shader_type sky;

uniform vec3 origin = vec3(0.0, 0.6, 0.0);
uniform int panel_count = 0;
uniform vec3 panel_c[12];
uniform vec3 panel_u[12];
uniform vec3 panel_v[12];
uniform vec4 panel_col[12];
// Room.
uniform vec3 top_color : source_color = vec3(0.02);
uniform vec3 wall_color : source_color = vec3(0.05);
uniform vec3 horizon_color : source_color = vec3(0.08);
uniform vec3 floor_color : source_color = vec3(0.03);
uniform vec3 pool_color : source_color = vec3(0.25);
uniform float pool_radius = 5.0;
uniform float horizon_width = 10.0;
uniform float energy = 1.0;

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col;
	if (d.y >= 0.0) {
		col = mix(wall_color, top_color, smoothstep(0.05, 0.75, d.y));
		col = mix(col, horizon_color, exp(-d.y * horizon_width));
	} else {
		// Floor: pool of light under the subject fading to the dark room floor.
		float t = origin.y / max(-d.y, 1e-3);
		float r = length(d.xz * t);
		col = mix(pool_color, floor_color, smoothstep(pool_radius * 0.25, pool_radius, r));
		col = mix(col, horizon_color, exp(d.y * horizon_width * 1.5) * 0.6);
	}
	for (int i = 0; i < 12; i++) {
		if (i >= panel_count) {
			break;
		}
		vec3 u = panel_u[i];
		vec3 v = panel_v[i];
		vec3 n = cross(u, v);
		float dn = dot(d, n);
		if (abs(dn) < 1e-6) {
			continue;
		}
		vec3 c = panel_c[i] - origin;
		float t = dot(c, n) / dn;
		if (t <= 0.0) {
			continue;
		}
		vec3 p = d * t - c;
		float a = abs(dot(p, u) / dot(u, u));
		float b = abs(dot(p, v) / dot(v, v));
		float s = max(panel_col[i].a, 1e-3);
		float m = (1.0 - smoothstep(1.0 - s, 1.0, a)) * (1.0 - smoothstep(1.0 - s, 1.0, b));
		// Diffuser hot spot: a touch brighter in the middle, like a real softbox.
		float hot = 1.0 + 0.25 * (1.0 - a * a) * (1.0 - b * b);
		col = mix(col, panel_col[i].rgb * hot, m);
	}
	COLOR = col * energy;
}
