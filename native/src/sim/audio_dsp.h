// Small DSP building blocks for the procedural audio (engine, tires, wind, music).
#pragma once

#include <cmath>
#include <cstdint>

namespace nt {

constexpr float F_PI = 3.14159265358979f;
constexpr float F_TAU = 6.28318530717959f;

// Fast white noise (xorshift32), [-1, 1].
struct Noise {
	uint32_t s = 0x9E3779B9u;
	explicit Noise(uint32_t seed = 0x9E3779B9u) : s(seed ? seed : 1u) {}
	float next() {
		s ^= s << 13;
		s ^= s >> 17;
		s ^= s << 5;
		return (float)(int32_t)s * (1.0f / 2147483648.0f);
	}
	float uni() { return next() * 0.5f + 0.5f; }
};

// RBJ biquad (transposed direct form II).
struct Biquad {
	float b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
	float z1 = 0, z2 = 0;
	void bandpass(float fs, float f, float q) {
		f = std::fmin(f, fs * 0.45f);
		float w = F_TAU * f / fs, c = std::cos(w), s = std::sin(w), al = s / (2.0f * q);
		float a0 = 1.0f + al;
		b0 = al / a0; b1 = 0.0f; b2 = -al / a0; a1 = -2.0f * c / a0; a2 = (1.0f - al) / a0;
	}
	void lowpass(float fs, float f, float q = 0.7071f) {
		f = std::fmin(f, fs * 0.45f);
		float w = F_TAU * f / fs, c = std::cos(w), s = std::sin(w), al = s / (2.0f * q);
		float a0 = 1.0f + al;
		b0 = (1.0f - c) * 0.5f / a0; b1 = (1.0f - c) / a0; b2 = b0; a1 = -2.0f * c / a0; a2 = (1.0f - al) / a0;
	}
	void highpass(float fs, float f, float q = 0.7071f) {
		f = std::fmin(f, fs * 0.45f);
		float w = F_TAU * f / fs, c = std::cos(w), s = std::sin(w), al = s / (2.0f * q);
		float a0 = 1.0f + al;
		b0 = (1.0f + c) * 0.5f / a0; b1 = -(1.0f + c) / a0; b2 = b0; a1 = -2.0f * c / a0; a2 = (1.0f - al) / a0;
	}
	void peak(float fs, float f, float q, float gain_db) {
		f = std::fmin(f, fs * 0.45f);
		float A = std::pow(10.0f, gain_db / 40.0f);
		float w = F_TAU * f / fs, c = std::cos(w), s = std::sin(w), al = s / (2.0f * q);
		float a0 = 1.0f + al / A;
		b0 = (1.0f + al * A) / a0; b1 = -2.0f * c / a0; b2 = (1.0f - al * A) / a0; a1 = -2.0f * c / a0; a2 = (1.0f - al / A) / a0;
	}
	float process(float x) {
		float y = b0 * x + z1;
		z1 = b1 * x - a1 * y + z2;
		z2 = b2 * x - a2 * y;
		return y;
	}
	void reset() { z1 = z2 = 0.0f; }
};

struct OnePole {
	float a = 0.0f, y = 0.0f;
	void set(float fs, float cutoff) { a = std::exp(-F_TAU * cutoff / fs); }
	float process(float x) { return y = x + (y - x) * a; }
};

// Parameter smoother so values set at 60 Hz don't zipper at audio rate.
struct Smooth {
	float v = 0.0f, target = 0.0f, k = 0.002f;
	void set_time(float fs, float seconds) { k = 1.0f - std::exp(-1.0f / (fs * seconds)); }
	float tick() { return v += (target - v) * k; }
};

inline float fast_sin(float x) {
	// x in [-pi, pi]; Bhaskara-like parabola with correction.
	const float B = 4.0f / F_PI, C = -4.0f / (F_PI * F_PI);
	float y = B * x + C * x * std::fabs(x);
	return 0.225f * (y * std::fabs(y) - y) + y;
}
inline float wrap_pi(float p) {
	while (p > F_PI) p -= F_TAU;
	while (p < -F_PI) p += F_TAU;
	return p;
}
inline float soft_clip(float x) { return x / (1.0f + std::fabs(x)); }
inline float tanh_clip(float x) {
	float x2 = x * x;
	return x * (27.0f + x2) / (27.0f + 9.0f * x2);
}

} // namespace nt
