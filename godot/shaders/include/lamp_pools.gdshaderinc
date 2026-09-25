// Street-lamp light pools for ground shaders (road, junctions, pavements). The mobile renderer can
// afford only a handful of real OmniLights (LightPool); the next nearest lamps are passed here
// every few frames so avenues keep their pools of light between the real ones.
// lamp_pos[i] = world xyz + intensity (0 = unused slot), lamp_tint[i] = light colour.
const int LAMP_POOLS = 12;
uniform vec4 lamp_pos[12];
uniform vec3 lamp_tint[12];

// Irradiance from lamps above `p` (point source over a plane: h^3 / (r^2 + h^2)^1.5, 1 right under
// the lamp), fading out by 24 m so the cut-off never shows.
vec3 lamp_pool_light(vec3 p) {
	vec3 acc = vec3(0.0);
	for (int i = 0; i < LAMP_POOLS; i++) {
		vec4 l = lamp_pos[i];
		if (l.w <= 0.0) continue;
		vec3 d = l.xyz - p;
		float h = max(d.y, 1.5);
		float r2 = dot(d.xz, d.xz);
		float e = h * h * h * inversesqrt((r2 + h * h) * (r2 + h * h) * (r2 + h * h));
		acc += lamp_tint[i] * l.w * e * (1.0 - smoothstep(16.0 * 16.0, 24.0 * 24.0, r2));
	}
	return acc;
}
