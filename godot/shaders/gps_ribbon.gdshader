shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Forza Horizon-style 3D GPS Navigation / Dynamic Racing Line Ribbon
uniform vec4 color_straight : source_color = vec4(0.08, 0.88, 1.0, 0.75); // Electric cyan
uniform vec4 color_brake : source_color = vec4(1.0, 0.12, 0.25, 0.85);    // Neon braking red
uniform vec4 color_coast : source_color = vec4(1.0, 0.82, 0.15, 0.78);    // Amber coasting
uniform float pulse_speed : hint_range(1.0, 15.0) = 7.0;
uniform float chevron_freq : hint_range(5.0, 50.0) = 22.0;
uniform float glow_intensity : hint_range(1.0, 5.0) = 2.4;

void fragment() {
	// UV.x across ribbon (-0.5 to 0.5 centered), UV.y along ribbon distance
	float u_dist = abs(UV.x - 0.5) * 2.0; // 0 at center, 1 at edge
	
	// Soft edge falloff
	float edge_alpha = 1.0 - smoothstep(0.4, 0.98, u_dist);
	
	// Chevron arrow pattern moving forward along the ribbon
	float flow = fract(UV.y * chevron_freq - TIME * pulse_speed);
	// V-shape chevron calculation: arrow points in direction of travel
	float chevron_dist = abs(UV.x - 0.5) * 1.6;
	float chevron = smoothstep(0.12, 0.0, abs(flow - chevron_dist));
	
	// Base ribbon color blended with vertex color (COLOR encodes curvature/braking: R=brake, G=coast, B=straight)
	vec3 base_col = COLOR.rgb;
	
	// Boost brightness at center and on chevrons
	float center_highlight = (1.0 - u_dist * 0.7);
	vec3 final_col = base_col * (center_highlight + chevron * 0.8) * glow_intensity;
	
	ALBEDO = final_col;
	EMISSION = final_col * 0.7;
	ALPHA = edge_alpha * clamp(COLOR.a * (0.65 + chevron * 0.35), 0.0, 1.0);
}
