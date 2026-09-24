// Retro Arcade Post-Processing Shader (Initial D / Tokyo Xtreme Racer Style)
// Combines:
// 1. AMD FidelityFX CAS (Contrast-Adaptive Sharpening) for razor-sharp rendering on Mali-G77.
// 2. High-speed radial speedlines (Initial D manga style, activated at high speed > 80 km/h).
// 3. Anamorphic horizontal lens flare on bright neons/headlights (Wangan Midnight aesthetic).
// 4. Subtle arcade CRT scanline and vignette option (controllable via uniform).
// 5. High-speed edge chromatic aberration during aggressive cornering & boost.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float sharpness : hint_range(0.0, 1.0) = 0.65;
uniform float scale_factor : hint_range(0.5, 1.5) = 1.0;

// Retro arcade dynamics (driven by freeroam.gd / telemetry)
uniform float speed_intensity : hint_range(0.0, 1.0) = 0.0; // 0 at low speed, 1 at 200+ km/h
uniform float drift_intensity : hint_range(0.0, 1.0) = 0.0; // lateral G / drift angle
uniform int arcade_mode : hint_range(0, 2) = 1; // 0 = Off, 1 = Subtle Arcade, 2 = Full Retro CRT
uniform vec2 vanishing_point = vec2(0.5, 0.48);

// Fast pseudo-random hash
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 ts = vec2(1.0) / vec2(textureSize(screen_tex, 0));

	// 1. High-Speed Edge Chromatic Aberration
	vec2 to_center = uv - vanishing_point;
	float dist_sq = dot(to_center, to_center);
	float ca_strength = (speed_intensity * 0.006 + drift_intensity * 0.008) * dist_sq * 4.0;
	vec2 ca_offset = normalize(to_center + vec2(0.0001)) * ca_strength;

	// 2. Sample RGB with Chromatic Aberration
	float col_r = texture(screen_tex, uv - ca_offset).r;
	float col_g = texture(screen_tex, uv).g;
	float col_b = texture(screen_tex, uv + ca_offset).b;
	vec3 base_color = vec3(col_r, col_g, col_b);

	// 3. CAS Spatial Sharpening Pass (3x3 cardinal cross)
	vec3 c = base_color;
	vec3 n = texture(screen_tex, uv + vec2(0.0, -ts.y)).rgb;
	vec3 s = texture(screen_tex, uv + vec2(0.0,  ts.y)).rgb;
	vec3 e = texture(screen_tex, uv + vec2( ts.x, 0.0)).rgb;
	vec3 w = texture(screen_tex, uv + vec2(-ts.x, 0.0)).rgb;

	vec3 mn = min(c, min(min(n, s), min(e, w)));
	vec3 mx = max(c, max(max(n, s), max(e, w)));
	vec3 d = vec3(1.0) / (mx + 0.001);
	float peak = -1.0 / mix(8.0, 5.0, clamp(sharpness, 0.0, 1.0));
	float boost = mix(1.0, 1.5, clamp(1.0 - scale_factor, 0.0, 0.5) * 2.0);
	float w_cas = clamp(min(mn.r * d.r, min(mn.g * d.g, mn.b * d.b)) * peak, peak, 0.0) * sharpness * boost;
	vec3 sharp_color = (c + (n + s + e + w) * w_cas) / (1.0 + 4.0 * w_cas);

	// 4. Initial D Radial Speedlines (active at high speed)
	if (speed_intensity > 0.05) {
		float angle = atan(to_center.y, to_center.x);
		float radius = length(to_center);
		// Center deadzone: clear visibility for car and oncoming track
		float center_mask = smoothstep(0.28, 0.65, radius);
		// Procedural radial streaks
		float streak_id = floor(angle * 45.0);
		float streak_rand = hash(vec2(streak_id, floor(TIME * 24.0)));
		float streak_line = step(0.68, streak_rand) * sin(angle * 90.0);
		streak_line = max(0.0, streak_line);

		float speedline_alpha = center_mask * streak_line * speed_intensity * 0.22;
		// Add subtle white/cyan speedline tint
		vec3 speedline_col = mix(sharp_color * 1.35, vec3(0.9, 0.96, 1.0), 0.4);
		sharp_color = mix(sharp_color, speedline_col, speedline_alpha);
	}

	// 5. Anamorphic Horizontal Bloom Flares (Wangan Midnight highway aesthetic)
	// Sample horizontal taps for bright highway lights
	if (arcade_mode > 0) {
		float luma = dot(sharp_color, vec3(0.2126, 0.7152, 0.0722));
		if (luma > 0.85) {
			vec3 flare = vec3(0.0);
			flare += texture(screen_tex, uv + vec2(-ts.x * 12.0, 0.0)).rgb * 0.08;
			flare += texture(screen_tex, uv + vec2(-ts.x * 6.0, 0.0)).rgb * 0.14;
			flare += texture(screen_tex, uv + vec2( ts.x * 6.0, 0.0)).rgb * 0.14;
			flare += texture(screen_tex, uv + vec2( ts.x * 12.0, 0.0)).rgb * 0.08;
			// Anamorphic cyan/magenta tint
			vec3 flare_tint = vec3(0.4, 0.7, 1.0) * flare;
			sharp_color += flare_tint * 0.35;
		}
	}

	// 6. Retro Arcade CRT Vignette & Scanlines
	if (arcade_mode == 1) {
		// Subtle Arcade: mild corner vignette
		float vig = 1.0 - smoothstep(0.4, 1.1, length(uv - vec2(0.5)));
		sharp_color *= mix(0.92, 1.0, vig);
	} else if (arcade_mode == 2) {
		// Full Retro CRT: scanlines + arcade cabinet vignette
		float vig = 1.0 - smoothstep(0.35, 1.05, length(uv - vec2(0.5)));
		sharp_color *= mix(0.82, 1.0, vig);
		// Scanlines: 750 lines
		float scanline = sin(uv.y * 750.0 * 3.14159) * 0.5 + 0.5;
		sharp_color *= mix(0.92, 1.0, scanline);
	}

	COLOR = vec4(clamp(sharp_color, vec3(0.0), vec3(1.0)), 1.0);
}
