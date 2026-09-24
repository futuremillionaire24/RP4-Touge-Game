// Deterministic RNG + hash noise. The noise functions are mirrored bit-for-bit (up to float
// precision) in godot/shaders/include/nt_noise.gdshaderinc so puddles in the physics match
// puddles on screen.
#pragma once

#include "vmath.h"

namespace nt {

// SplitMix64 seeded xoshiro256**: fast, high quality, fully deterministic across platforms.
class Rng {
	uint64_t s[4];

	static uint64_t splitmix(uint64_t &x) {
		uint64_t z = (x += 0x9E3779B97F4A7C15ull);
		z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
		z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
		return z ^ (z >> 31);
	}
	static uint64_t rotl(uint64_t x, int k) { return (x << k) | (x >> (64 - k)); }

public:
	explicit Rng(uint64_t seed = 0x5EEDull) { reseed(seed); }
	void reseed(uint64_t seed) {
		uint64_t x = seed;
		for (auto &v : s) v = splitmix(x);
	}
	uint64_t next_u64() {
		uint64_t r = rotl(s[1] * 5, 7) * 9;
		uint64_t t = s[1] << 17;
		s[2] ^= s[0];
		s[3] ^= s[1];
		s[1] ^= s[2];
		s[0] ^= s[3];
		s[2] ^= t;
		s[3] = rotl(s[3], 45);
		return r;
	}
	// [0, 1)
	real next() { return (real)(next_u64() >> 11) * (1.0 / 9007199254740992.0); }
	real range(real lo, real hi) { return lo + (hi - lo) * next(); }
	int irange(int lo, int hi_inclusive) { return lo + (int)(next_u64() % (uint64_t)(hi_inclusive - lo + 1)); }
	bool chance(real p) { return next() < p; }
	real gauss() {
		real u1 = std::max(next(), 1e-12), u2 = next();
		return std::sqrt(-2.0 * std::log(u1)) * std::cos(TAU * u2);
	}
	template <typename T>
	const T &pick(const T *arr, int n) { return arr[irange(0, n - 1)]; }
};

inline uint32_t hash_u32(uint32_t x) {
	x ^= x >> 16;
	x *= 0x7FEB352Du;
	x ^= x >> 15;
	x *= 0x846CA68Bu;
	x ^= x >> 16;
	return x;
}
inline uint32_t hash2i(int32_t x, int32_t y, uint32_t seed = 0) {
	return hash_u32((uint32_t)x * 0x8DA6B343u ^ (uint32_t)y * 0xD8163841u ^ seed * 0xCB1AB31Fu);
}
inline real hash01(int32_t x, int32_t y, uint32_t seed = 0) { return (real)(hash2i(x, y, seed) & 0xFFFFFFu) / 16777215.0; }

// Shader-mirrorable value noise: fract(sin(dot)) hash is avoided (precision-dependent on GPUs);
// instead a cheap polynomial hash in float range that behaves identically in GLSL.
inline real shader_hash(real x, real y) {
	real px = std::fmod(std::fabs(x * 0.1031), 1.0);
	real py = std::fmod(std::fabs(y * 0.1030), 1.0);
	real pz = std::fmod(std::fabs(x * 0.0973), 1.0);
	real d = px * (py + 33.33) + py * (pz + 33.33) + pz * (px + 33.33);
	px += d; py += d; pz += d;
	real r = (px + py) * pz;
	return r - std::floor(r);
}
inline real value_noise(real x, real y) {
	real ix = std::floor(x), iy = std::floor(y);
	real fx = x - ix, fy = y - iy;
	real ux = fx * fx * (3.0 - 2.0 * fx), uy = fy * fy * (3.0 - 2.0 * fy);
	real a = shader_hash(ix, iy), b = shader_hash(ix + 1.0, iy);
	real c = shader_hash(ix, iy + 1.0), d = shader_hash(ix + 1.0, iy + 1.0);
	return lerpr(lerpr(a, b, ux), lerpr(c, d, ux), uy);
}
inline real fbm2(real x, real y, int octaves) {
	real sum = 0.0, amp = 0.5, norm = 0.0;
	for (int i = 0; i < octaves; ++i) {
		sum += value_noise(x, y) * amp;
		norm += amp;
		x = x * 2.03 + 17.1;
		y = y * 2.03 + 9.7;
		amp *= 0.5;
	}
	return sum / norm;
}
// Standing-water mask in [0,1] for world position (xz) and global wetness. Same formula as the
// wet-road shader so the car aquaplanes exactly where the player sees a puddle.
inline real puddle_mask(real x, real z, real wetness) {
	if (wetness <= 0.0) return 0.0;
	real n = fbm2(x * 0.11, z * 0.11, 3);
	real threshold = 1.0 - wetness * 0.55;
	return smoothstep(threshold, threshold + 0.08, n);
}

} // namespace nt
