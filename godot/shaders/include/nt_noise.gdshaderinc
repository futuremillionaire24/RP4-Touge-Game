// Mirrors native/src/sim/rng.h (shader_hash / value_noise / fbm2 / puddle_mask) so the puddles the
// player sees are exactly where the tires lose grip.

float nt_hash(vec2 p) {
	vec3 p3 = abs(vec3(p.x * 0.1031, p.y * 0.1030, p.x * 0.0973));
	p3 = mod(p3, 1.0);
	float d = p3.x * (p3.y + 33.33) + p3.y * (p3.z + 33.33) + p3.z * (p3.x + 33.33);
	p3 += d;
	return fract((p3.x + p3.y) * p3.z);
}

float nt_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = nt_hash(i);
	float b = nt_hash(i + vec2(1.0, 0.0));
	float c = nt_hash(i + vec2(0.0, 1.0));
	float d = nt_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float nt_fbm(vec2 p, int octaves) {
	float sum = 0.0, amp = 0.5, norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		sum += nt_value_noise(p) * amp;
		norm += amp;
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return sum / norm;
}

float nt_puddle(vec2 xz, float wetness) {
	if (wetness <= 0.0) return 0.0;
	float n = nt_fbm(xz * 0.11, 3);
	float threshold = 1.0 - wetness * 0.55;
	return smoothstep(threshold, threshold + 0.08, n);
}

// Animated raindrop ripples: returns a tangent-space normal offset.
vec2 nt_ripples(vec2 xz, float t, float intensity) {
	if (intensity <= 0.0) return vec2(0.0);
	vec2 acc = vec2(0.0);
	for (int layer = 0; layer < 2; layer++) {
		vec2 p = xz * (2.2 + float(layer) * 1.3) + float(layer) * 7.3;
		vec2 cell = floor(p);
		vec2 f = fract(p) - 0.5;
		float h = nt_hash(cell + float(layer) * 13.0);
		float phase = fract(t * (0.9 + h * 0.6) + h);
		vec2 center = vec2(nt_hash(cell + 3.1), nt_hash(cell + 5.7)) - 0.5;
		vec2 d = f - center * 0.6;
		float r = length(d);
		float ring = sin((r - phase * 0.45) * 60.0) * smoothstep(0.45, 0.0, r) * (1.0 - phase) * smoothstep(0.0, 0.05, phase);
		acc += normalize(d + 1e-4) * ring;
	}
	return acc * intensity * 0.35;
}
