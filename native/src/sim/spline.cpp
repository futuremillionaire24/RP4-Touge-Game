#include "spline.h"

namespace nt {

const Vec3 &Spline::cp(int i) const {
	int n = (int)ctrl.size();
	if (closed) {
		i %= n;
		if (i < 0) i += n;
		return ctrl[i];
	}
	return ctrl[i < 0 ? 0 : (i >= n ? n - 1 : i)];
}

// Centripetal parameterization (alpha = 0.5) avoids cusps and self-intersections.
static Vec3 catmull(const Vec3 &p0, const Vec3 &p1, const Vec3 &p2, const Vec3 &p3, real t) {
	auto knot = [](real ti, const Vec3 &a, const Vec3 &b) { return ti + std::max(std::sqrt(distance(a, b)), 1e-4); };
	real t0 = 0.0;
	real t1 = knot(t0, p0, p1);
	real t2 = knot(t1, p1, p2);
	real t3 = knot(t2, p2, p3);
	real u = lerpr(t1, t2, t);
	Vec3 a1 = p0 * ((t1 - u) / (t1 - t0)) + p1 * ((u - t0) / (t1 - t0));
	Vec3 a2 = p1 * ((t2 - u) / (t2 - t1)) + p2 * ((u - t1) / (t2 - t1));
	Vec3 a3 = p2 * ((t3 - u) / (t3 - t2)) + p3 * ((u - t2) / (t3 - t2));
	Vec3 b1 = a1 * ((t2 - u) / (t2 - t0)) + a2 * ((u - t0) / (t2 - t0));
	Vec3 b2 = a2 * ((t3 - u) / (t3 - t1)) + a3 * ((u - t1) / (t3 - t1));
	return b1 * ((t2 - u) / (t2 - t1)) + b2 * ((u - t1) / (t2 - t1));
}

Vec3 Spline::eval(int seg, real t) const {
	const Vec3 &p1 = cp(seg), &p2 = cp(seg + 1);
	Vec3 p0 = (!closed && seg == 0) ? p1 * 2.0 - p2 : cp(seg - 1);
	Vec3 p3 = (!closed && seg + 1 >= (int)ctrl.size() - 1) ? p2 * 2.0 - p1 : cp(seg + 2);
	return catmull(p0, p1, p2, p3, clampr(t, 0.0, 1.0));
}

Vec3 Spline::derivative(int seg, real t) const {
	const real e = 1e-3;
	real a = std::max(0.0, t - e), b = std::min(1.0, t + e);
	return (eval(seg, b) - eval(seg, a)) / (b - a);
}

real Spline::approx_length(int steps) const {
	real len = 0.0;
	for (int s = 0; s < segment_count(); ++s) {
		Vec3 prev = eval(s, 0.0);
		for (int k = 1; k <= steps; ++k) {
			Vec3 p = eval(s, (real)k / steps);
			len += distance(prev, p);
			prev = p;
		}
	}
	return len;
}

void Spline::resample(real spacing, std::vector<Vec3> &points, std::vector<Vec3> &tangents) const {
	points.clear();
	tangents.clear();
	int segs = segment_count();
	if (segs <= 0) return;
	// Dense polyline first, then walk it at uniform spacing.
	std::vector<Vec3> dense;
	const int steps = 48;
	for (int s = 0; s < segs; ++s) {
		for (int k = 0; k < steps; ++k) dense.push_back(eval(s, (real)k / steps));
	}
	if (!closed) dense.push_back(eval(segs - 1, 1.0));
	else dense.push_back(dense.front());

	real carry = 0.0;
	points.push_back(dense[0]);
	for (size_t i = 1; i < dense.size(); ++i) {
		Vec3 a = dense[i - 1], b = dense[i];
		real seg = distance(a, b);
		real pos = spacing - carry;
		while (pos <= seg) {
			points.push_back(lerp(a, b, pos / seg));
			pos += spacing;
		}
		carry = seg - (pos - spacing);
	}
	if (closed && points.size() > 2 && distance(points.back(), points.front()) < spacing * 0.5) points.pop_back();
	if (!closed && distance(points.back(), dense.back()) > spacing * 0.25) points.push_back(dense.back());

	int n = (int)points.size();
	tangents.resize(n);
	for (int i = 0; i < n; ++i) {
		Vec3 prev = (i > 0) ? points[i - 1] : (closed ? points[n - 1] : points[0]);
		Vec3 next = (i < n - 1) ? points[i + 1] : (closed ? points[0] : points[n - 1]);
		tangents[i] = (next - prev).normalized();
	}
}

} // namespace nt
