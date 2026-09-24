// Double-precision vector math for the simulation core. Godot-independent so the sim can be
// unit-tested natively. Conventions match Godot: +Y up, -Z forward, +X right, right-handed.
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace nt {

using real = double;

constexpr real PI = 3.14159265358979323846;
constexpr real TAU = 2.0 * PI;
constexpr real GRAVITY = 9.81;
constexpr real AIR_DENSITY = 1.225;

inline real clampr(real v, real lo, real hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline real saturate(real v) { return clampr(v, 0.0, 1.0); }
inline real lerpr(real a, real b, real t) { return a + (b - a) * t; }
inline real signr(real v) { return v > 0.0 ? 1.0 : (v < 0.0 ? -1.0 : 0.0); }
inline real sqr(real v) { return v * v; }
inline real smoothstep(real e0, real e1, real x) {
	real t = saturate((x - e0) / (e1 - e0));
	return t * t * (3.0 - 2.0 * t);
}
// Frame-rate independent exponential approach: returns factor to lerp by for rate `k` over `dt`.
inline real exp_blend(real k, real dt) { return 1.0 - std::exp(-k * dt); }
inline real move_toward(real from, real to, real delta) {
	if (std::fabs(to - from) <= delta) return to;
	return from + signr(to - from) * delta;
}
inline real wrap_angle(real a) {
	a = std::fmod(a + PI, TAU);
	if (a < 0.0) a += TAU;
	return a - PI;
}

struct Vec3 {
	real x = 0, y = 0, z = 0;
	constexpr Vec3() = default;
	constexpr Vec3(real px, real py, real pz) : x(px), y(py), z(pz) {}

	Vec3 operator+(const Vec3 &o) const { return {x + o.x, y + o.y, z + o.z}; }
	Vec3 operator-(const Vec3 &o) const { return {x - o.x, y - o.y, z - o.z}; }
	Vec3 operator-() const { return {-x, -y, -z}; }
	Vec3 operator*(real s) const { return {x * s, y * s, z * s}; }
	Vec3 operator/(real s) const { return {x / s, y / s, z / s}; }
	Vec3 &operator+=(const Vec3 &o) { x += o.x; y += o.y; z += o.z; return *this; }
	Vec3 &operator-=(const Vec3 &o) { x -= o.x; y -= o.y; z -= o.z; return *this; }
	Vec3 &operator*=(real s) { x *= s; y *= s; z *= s; return *this; }
	real operator[](int i) const { return i == 0 ? x : (i == 1 ? y : z); }

	real dot(const Vec3 &o) const { return x * o.x + y * o.y + z * o.z; }
	Vec3 cross(const Vec3 &o) const { return {y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x}; }
	real length_sq() const { return x * x + y * y + z * z; }
	real length() const { return std::sqrt(length_sq()); }
	Vec3 normalized() const {
		real l = length();
		return l > 1e-12 ? *this / l : Vec3(0, 0, 0);
	}
	Vec3 mul(const Vec3 &o) const { return {x * o.x, y * o.y, z * o.z}; }
	Vec3 flat() const { return {x, 0.0, z}; }
};
inline Vec3 operator*(real s, const Vec3 &v) { return v * s; }
inline Vec3 lerp(const Vec3 &a, const Vec3 &b, real t) { return a + (b - a) * t; }
inline real distance(const Vec3 &a, const Vec3 &b) { return (a - b).length(); }
inline Vec3 project_on_plane(const Vec3 &v, const Vec3 &n) { return v - n * v.dot(n); }

struct Quat {
	real x = 0, y = 0, z = 0, w = 1;
	constexpr Quat() = default;
	constexpr Quat(real px, real py, real pz, real pw) : x(px), y(py), z(pz), w(pw) {}

	static Quat from_axis_angle(const Vec3 &axis, real angle) {
		Vec3 a = axis.normalized();
		real s = std::sin(angle * 0.5);
		return {a.x * s, a.y * s, a.z * s, std::cos(angle * 0.5)};
	}
	// Yaw around +Y. Yaw 0 faces -Z.
	static Quat from_yaw(real yaw) { return from_axis_angle({0, 1, 0}, yaw); }

	Quat operator*(const Quat &q) const {
		return {
			w * q.x + x * q.w + y * q.z - z * q.y,
			w * q.y - x * q.z + y * q.w + z * q.x,
			w * q.z + x * q.y - y * q.x + z * q.w,
			w * q.w - x * q.x - y * q.y - z * q.z,
		};
	}
	Quat conjugate() const { return {-x, -y, -z, w}; }
	Quat normalized() const {
		real l = std::sqrt(x * x + y * y + z * z + w * w);
		return l > 1e-12 ? Quat(x / l, y / l, z / l, w / l) : Quat();
	}
	Vec3 rotate(const Vec3 &v) const {
		Vec3 u(x, y, z);
		Vec3 t = u.cross(v) * 2.0;
		return v + t * w + u.cross(t);
	}
	Vec3 inv_rotate(const Vec3 &v) const { return conjugate().rotate(v); }
	Vec3 right() const { return rotate({1, 0, 0}); }
	Vec3 up() const { return rotate({0, 1, 0}); }
	Vec3 forward() const { return rotate({0, 0, -1}); }
	// Integrate angular velocity (world space) over dt.
	Quat integrated(const Vec3 &omega, real dt) const {
		Quat dq(omega.x * dt * 0.5, omega.y * dt * 0.5, omega.z * dt * 0.5, 0.0);
		Quat r = dq * (*this);
		return Quat(x + r.x, y + r.y, z + r.z, w + r.w).normalized();
	}
	real yaw() const {
		Vec3 f = forward();
		return std::atan2(-f.x, -f.z);
	}
};

inline Quat slerp(const Quat &a, Quat b, real t) {
	real d = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
	if (d < 0.0) {
		b = Quat(-b.x, -b.y, -b.z, -b.w);
		d = -d;
	}
	if (d > 0.9995) {
		return Quat(lerpr(a.x, b.x, t), lerpr(a.y, b.y, t), lerpr(a.z, b.z, t), lerpr(a.w, b.w, t)).normalized();
	}
	real th = std::acos(d);
	real s = std::sin(th);
	real wa = std::sin((1.0 - t) * th) / s;
	real wb = std::sin(t * th) / s;
	return Quat(a.x * wa + b.x * wb, a.y * wa + b.y * wb, a.z * wa + b.z * wb, a.w * wa + b.w * wb);
}

// Builds an orientation whose forward (-Z) is `fwd` and up is as close to `up` as possible.
inline Quat quat_look(const Vec3 &fwd, const Vec3 &up) {
	Vec3 f = fwd.normalized();
	Vec3 r = f.cross(up).normalized();
	Vec3 u = r.cross(f);
	// Basis columns: X=r, Y=u, Z=-f.
	real m00 = r.x, m01 = u.x, m02 = -f.x;
	real m10 = r.y, m11 = u.y, m12 = -f.y;
	real m20 = r.z, m21 = u.z, m22 = -f.z;
	real tr = m00 + m11 + m22;
	Quat q;
	if (tr > 0.0) {
		real s = std::sqrt(tr + 1.0) * 2.0;
		q = {(m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s};
	} else if (m00 > m11 && m00 > m22) {
		real s = std::sqrt(1.0 + m00 - m11 - m22) * 2.0;
		q = {0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s};
	} else if (m11 > m22) {
		real s = std::sqrt(1.0 + m11 - m00 - m22) * 2.0;
		q = {(m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s};
	} else {
		real s = std::sqrt(1.0 + m22 - m00 - m11) * 2.0;
		q = {(m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s};
	}
	return q.normalized();
}

// Piecewise-linear lookup table on a sorted x axis.
struct Curve1D {
	static constexpr int MAX = 24;
	real xs[MAX] = {};
	real ys[MAX] = {};
	int n = 0;
	void add(real x, real y) {
		if (n < MAX) { xs[n] = x; ys[n] = y; ++n; }
	}
	real eval(real x) const {
		if (n == 0) return 0.0;
		if (x <= xs[0]) return ys[0];
		if (x >= xs[n - 1]) return ys[n - 1];
		int i = 1;
		while (i < n - 1 && xs[i] < x) ++i;
		real t = (x - xs[i - 1]) / (xs[i] - xs[i - 1]);
		return lerpr(ys[i - 1], ys[i], t);
	}
	real max_y() const {
		real m = -1e30;
		for (int i = 0; i < n; ++i) m = std::max(m, ys[i]);
		return m;
	}
};

} // namespace nt
