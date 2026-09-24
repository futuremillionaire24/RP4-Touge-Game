// Photo-studio cyclorama: seamless floor + cove + wall. Semi-gloss painted floor (picks up soft
// reflections of the softboxes), matte walls fading darker with height.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 floor_albedo : source_color = vec3(0.12);
uniform vec3 wall_albedo : source_color = vec3(0.09);
uniform float floor_roughness = 0.32;
uniform float wall_roughness = 0.85;
uniform float cove_top = 3.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = smoothstep(0.02, cove_top, wpos.y);
	ALBEDO = mix(floor_albedo, wall_albedo, h) * mix(1.0, 0.55, smoothstep(cove_top, cove_top * 3.0, wpos.y));
	ROUGHNESS = mix(floor_roughness, wall_roughness, h);
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
