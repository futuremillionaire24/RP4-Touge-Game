// Mediterranean sea / harbours. Opaque (mobile friendly): the water colour comes from the real
// depth under it (NTWorld.sea_depth, bound by WorldMaterials): deep ultramarine offshore,
// turquoise over shallow sand, green-grey in the ports, foam lapping at the shoreline.
// Waves are analytic sums in world space (deep-water dispersion), detail fading with distance;
// reflections come from the sky radiance through Fresnel.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/nt_noise.gdshaderinc"

global uniform float nt_night;
global uniform float nt_rain;
global uniform vec3 nt_wind;
global uniform vec3 nt_sun_dir; // towards the sun (SkyWeather)

uniform sampler2D sea_depth : filter_linear, repeat_disable;
uniform vec4 sea_rect = vec4(-4500.0, -3100.0, 9000.0, 6200.0); // x0, z0, size x, size z

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Wave i: direction angle, wavelength (m), amplitude (m).
const vec3 WAVES[7] = vec3[](
	vec3(0.35, 31.0, 0.22), vec3(-0.25, 17.0, 0.12), vec3(0.9, 9.5, 0.06), vec3(-0.7, 5.3, 0.035),
	vec3(0.1, 2.9, 0.018), vec3(1.4, 1.6, 0.009), vec3(-1.2, 0.85, 0.005));

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float px = max(fwidth(p.x), fwidth(p.y)); // metres per pixel
	// Depth under the surface (0..24 m).
	vec2 duv = (p - sea_rect.xy) / sea_rect.zw;
	float depth = texture(sea_depth, duv).r * 24.0;
	float calm = mix(0.35, 1.0, smoothstep(1.0, 12.0, depth)); // sheltered / shallow water is calmer
	float wind = 0.7 + 0.5 * length(nt_wind);

	vec2 grad = vec2(0.0);
	float crest = 0.0;
	for (int i = 0; i < 7; i++) {
		vec3 w = WAVES[i];
		float k = 6.2831 / w.y;
		// Waves shorter than ~4 pixels would alias: fade them out.
		float fade = 1.0 - smoothstep(w.y * 0.12, w.y * 0.3, px);
		if (fade <= 0.0) continue;
		vec2 d = vec2(cos(w.x), sin(w.x));
		float ph = dot(d, p) * k - sqrt(9.81 * k) * t + float(i) * 1.7;
		float a = w.z * calm * wind * fade;
		grad += d * (a * k * cos(ph));
		crest += a * sin(ph);
	}
	// Fine capillary ripples + rain rings.
	vec2 n = vec2(nt_value_noise(p * 1.9 + vec2(t * 0.6, t * 0.35)), nt_value_noise(p * 1.9 - vec2(t * 0.45, -t * 0.5) + 11.0)) - 0.5;
	grad += n * 0.12 * (1.0 - smoothstep(0.02, 0.08, px));
	grad += nt_ripples(p * 0.5, t, nt_rain) * 0.35;
	vec3 Nw = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(Nw, 0.0)).xyz);

	// Scattering colour by depth: shallow sand turquoise -> deep ultramarine.
	vec3 deep = vec3(0.004, 0.028, 0.07);
	vec3 mid = vec3(0.01, 0.09, 0.14);
	vec3 shallow = vec3(0.06, 0.32, 0.33);
	vec3 col = mix(shallow, mid, smoothstep(0.5, 5.0, depth));
	col = mix(col, deep, smoothstep(6.0, 22.0, depth));
	// Wave crests catch more scattered light.
	col *= 1.0 + clamp(crest * 3.0, -0.3, 0.6);
	// Shoreline foam: lapping bands where the water gets thin.
	float shore = 1.0 - smoothstep(0.15, 1.1, depth);
	float lap = sin(depth * 9.0 - t * 1.6 + nt_value_noise(p * 0.3) * 4.0) * 0.5 + 0.5;
	float foam = shore * smoothstep(0.35, 0.8, lap * nt_value_noise(p * 2.5 + t * 0.2) + shore * 0.4);
	col = mix(col, vec3(0.85, 0.88, 0.88), foam);
	col *= mix(1.0, 0.25, nt_night);

	// Sun glitter on the wave facets, from the real sun (a tight lobe on top of the GGX highlight).
	vec3 V = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 sun_dir = normalize(nt_sun_dir + vec3(0.0, 1e-4, 0.0));
	vec3 H = normalize(V + sun_dir);
	float NdotH = max(dot(Nw, H), 0.0);
	float sparkle = pow(NdotH, 256.0) * smoothstep(0.0, 0.08, sun_dir.y) * (1.0 - nt_night) * (1.0 - foam) * 2.5;

	ALBEDO = col;
	EMISSION = vec3(1.0, 0.95, 0.85) * sparkle;
	ROUGHNESS = mix(0.04, 0.5, foam) + smoothstep(200.0, 2000.0, dist) * 0.08;
	METALLIC = 0.0;
	SPECULAR = mix(0.4, 0.5, foam); // F0 ~0.02 for water
}
