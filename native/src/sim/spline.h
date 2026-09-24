// Centripetal Catmull-Rom splines, resampled at uniform arc length. Used for road generation and
// racing lines.
#pragma once

#include "vmath.h"

#include <vector>

namespace nt {

class Spline {
public:
	std::vector<Vec3> ctrl;
	bool closed = false;

	Spline() = default;
	Spline(std::vector<Vec3> c, bool is_closed) : ctrl(std::move(c)), closed(is_closed) {}

	int segment_count() const { return closed ? (int)ctrl.size() : (int)ctrl.size() - 1; }
	Vec3 eval(int seg, real t) const;
	Vec3 derivative(int seg, real t) const;

	// Uniform arc-length resampling. Output tangents are normalized.
	void resample(real spacing, std::vector<Vec3> &points, std::vector<Vec3> &tangents) const;
	real approx_length(int steps_per_segment = 16) const;

private:
	const Vec3 &cp(int i) const;
};

} // namespace nt
