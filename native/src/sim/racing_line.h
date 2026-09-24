// Racing line: minimum-curvature path inside the track corridor + per-car speed profile
// (grip-limited cornering, forward acceleration pass, backward braking pass).
#pragma once

#include "vehicle.h"
#include "vmath.h"

#include <vector>

namespace nt {

struct TrackSample {
	Vec3 center;
	Vec3 tangent; // along direction of travel
	Vec3 normal = {0, 1, 0}; // road surface up
	real half_width_left = 4.0; // usable width to the left of center
	real half_width_right = 4.0;
	real grip = 1.0; // surface grip hint (dirt sections, etc.)
};

class RacingLine {
public:
	// Samples should be ~2-4 m apart. `closed` = circuit.
	void build(const std::vector<TrackSample> &samples, bool closed, real margin = 0.9, int iterations = 400);

	int size() const { return (int)pts_.size(); }
	bool closed() const { return closed_; }
	real length() const { return length_; }
	const Vec3 &point(int i) const { return pts_[wrap(i)]; }
	real offset(int i) const { return offset_[wrap(i)]; } // lateral offset from center (+ right)
	real curvature(int i) const { return curv_[wrap(i)]; } // signed 1/m, + = turning right
	real distance_at(int i) const { return dist_[wrap(i)]; }
	const TrackSample &sample(int i) const { return samples_[wrap(i)]; }
	Vec3 right_vector(int i) const;

	// Nearest index to `p`, searching around `hint` (pass -1 for a global search).
	int nearest(const Vec3 &p, int hint, int window = 40) const;
	// Interpolated position `ahead` meters past index i (+ fractional lateral shift).
	Vec3 position_ahead(int i, real ahead, real lateral_shift, int *out_index = nullptr) const;
	int index_ahead(int i, real ahead) const;
	// Progress along the line in meters for a world point (projected on the local segment).
	real progress(const Vec3 &p, int index) const;

	// Grip-limited speed profile for a given car. `mu` is effective lateral friction, `accel`
	// and `decel` the car's usable longitudinal accelerations (m/s^2).
	void speed_profile(std::vector<real> &out, real mu, real downforce_per_v2, real mass, real accel, real decel,
			real top_speed) const;

	int wrap(int i) const {
		int n = (int)pts_.size();
		if (n == 0) return 0;
		if (closed_) {
			i %= n;
			return i < 0 ? i + n : i;
		}
		return i < 0 ? 0 : (i >= n ? n - 1 : i);
	}

private:
	void compute_geometry();
	void k1999(std::vector<real> &e, const std::vector<Vec3> &right, const std::vector<real> &lo, const std::vector<real> &hi,
			int iterations);

	std::vector<TrackSample> samples_;
	std::vector<Vec3> pts_;
	std::vector<real> offset_;
	std::vector<real> curv_;
	std::vector<real> vcurv_; // vertical curvature, + = crest
	std::vector<real> dist_;
	real length_ = 0.0;
	bool closed_ = true;
};

// Estimates the numbers the speed profile needs from vehicle params.
struct CarEnvelope {
	real mu, downforce_per_v2, accel, decel, top_speed;
};
CarEnvelope estimate_envelope(const VehicleParams &p);

} // namespace nt
