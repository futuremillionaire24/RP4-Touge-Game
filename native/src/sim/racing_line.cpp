#include "racing_line.h"

#include <limits>

namespace nt {

static real cross2(const Vec3 &u, const Vec3 &v) { return u.x * v.z - u.z * v.x; }

void RacingLine::build(const std::vector<TrackSample> &samples, bool closed, real margin, int iterations) {
	samples_ = samples;
	closed_ = closed;
	int n = (int)samples_.size();
	pts_.assign(n, Vec3());
	offset_.assign(n, 0.0);
	curv_.assign(n, 0.0);
	dist_.assign(n, 0.0);
	if (n < 5) {
		for (int i = 0; i < n; ++i) pts_[i] = samples_[i].center;
		compute_geometry();
		return;
	}
	std::vector<real> lo(n), hi(n);
	for (int i = 0; i < n; ++i) {
		lo[i] = -std::max(0.0, samples_[i].half_width_left - margin);
		hi[i] = std::max(0.0, samples_[i].half_width_right - margin);
	}
	std::vector<real> e(n, 0.0);
	std::vector<Vec3> right(n);
	for (int i = 0; i < n; ++i) right[i] = right_vector(i);
	if (iterations > 0) k1999(e, right, lo, hi, iterations);
	for (int i = 0; i < n; ++i) {
		offset_[i] = e[i];
		pts_[i] = samples_[i].center + right[i] * e[i];
	}
	compute_geometry();
}

// K1999 (Remi Coulom): make each point's curvature the distance-weighted mean of its neighbours'
// at progressively finer resolutions. Converges to a smooth out-in-out line that uses the full
// corridor, and never oscillates the way plain gradient methods on curvature do.
void RacingLine::k1999(std::vector<real> &e, const std::vector<Vec3> &right, const std::vector<real> &lo,
		const std::vector<real> &hi, int iterations) {
	int n = (int)samples_.size();
	auto P = [&](int i) { int w = wrap(i); return samples_[w].center + right[w] * e[w]; };
	auto rinv = [&](int a, int b, int c) {
		Vec3 pa = P(a), pb = P(b), pc = P(c);
		Vec3 ab = (pb - pa).flat(), bc = (pc - pb).flat(), ac = (pc - pa).flat();
		real den = ab.length() * bc.length() * ac.length();
		return den > 1e-12 ? 2.0 * cross2(ab, bc) / den : 0.0;
	};
	auto usable = [&](int i) { return closed_ || (i > 0 && i < n - 1); };
	auto adjust = [&](int prev, int i, int next, real target) {
		int wi = wrap(i);
		// Put point i on the chord prev->next, then bend it to the target curvature.
		Vec3 a = P(prev), b = P(next);
		Vec3 c = samples_[wi].center, r = right[wi];
		Vec3 d = (b - a).flat();
		real den = cross2(r.flat(), d);
		if (std::fabs(den) > 1e-9) e[wi] = clampr(cross2(a.flat() - c.flat(), d) / den, lo[wi] - 2.0, hi[wi] + 2.0);
		const real delta = 0.001;
		real base = e[wi];
		e[wi] = base + delta;
		real k = rinv(prev, i, next);
		e[wi] = base;
		if (std::fabs(k) > 1e-12) e[wi] = base + delta * target / k;
		e[wi] = clampr(e[wi], lo[wi], hi[wi]);
	};
	auto smooth = [&](int step) {
		for (int i = 0; i < n; i += step) {
			int prev = i - step, next = i + step;
			if (!closed_ && (prev < 0 || next > n - 1)) continue;
			int pp = closed_ ? prev - step : std::max(prev - step, 0);
			int nn = closed_ ? next + step : std::min(next + step, n - 1);
			real r0 = rinv(pp, prev, i);
			real r1 = rinv(i, next, nn);
			real l0 = distance(P(i), P(prev));
			real l1 = distance(P(i), P(next));
			real target = (l1 * r0 + l0 * r1) / std::max(l0 + l1, 1e-9);
			if (usable(i)) adjust(prev, i, next, target);
		}
	};
	auto interpolate = [&](int step) {
		if (step <= 1) return;
		for (int i = 0; i < n; i += step) {
			int next = i + step;
			if (!closed_ && next > n - 1) next = n - 1;
			if (next == i) continue;
			real r0 = rinv(i - step, i, next);
			real r1 = rinv(i, next, next + step);
			for (int k = i + 1; k < next; ++k) {
				real t = (real)(k - i) / (real)(next - i);
				if (usable(k)) adjust(i, k, next, lerpr(r0, r1, t));
			}
		}
	};
	int base_iters = std::max(1, iterations / 4);
	for (int step = 64; step >= 1; step /= 2) {
		int reps = base_iters * (int)std::sqrt((real)step);
		for (int r = 0; r < reps; ++r) smooth(step);
		interpolate(step);
	}
}

Vec3 RacingLine::right_vector(int i) const {
	const TrackSample &s = samples_[wrap(i)];
	return s.tangent.cross(s.normal).normalized();
}

void RacingLine::compute_geometry() {
	int n = (int)pts_.size();
	length_ = 0.0;
	for (int i = 0; i < n; ++i) {
		dist_[i] = length_;
		if (i + 1 < n || closed_) length_ += distance(pts_[i], pts_[wrap(i + 1)]);
	}
	for (int i = 0; i < n; ++i) {
		if (!closed_ && (i == 0 || i == n - 1)) {
			curv_[i] = 0.0;
			continue;
		}
		// Curvature over a +-2 sample baseline for noise robustness.
		const Vec3 &a = pts_[wrap(i - 2)];
		const Vec3 &b = pts_[i];
		const Vec3 &c = pts_[wrap(i + 2)];
		Vec3 ab = (b - a).flat(), bc = (c - b).flat(), ac = (c - a).flat();
		real den = ab.length() * bc.length() * ac.length();
		curv_[i] = den > 1e-9 ? 2.0 * cross2(ab, bc) / den : 0.0;
	}
	// Light smoothing of curvature.
	std::vector<real> sm(n);
	for (int i = 0; i < n; ++i) sm[i] = (curv_[wrap(i - 1)] + 2.0 * curv_[i] + curv_[wrap(i + 1)]) * 0.25;
	curv_.swap(sm);
	// Vertical curvature (+ = crest): -d2y/ds2 over a ~24 m baseline, smoothed.
	vcurv_.assign(n, 0.0);
	const int b = 4;
	for (int i = 0; i < n; ++i) {
		if (!closed_ && (i < b || i >= n - b)) continue;
		const Vec3 &a = pts_[wrap(i - b)], &c = pts_[wrap(i + b)], &m = pts_[i];
		real s1 = distance(a.flat(), m.flat()), s2 = distance(m.flat(), c.flat());
		if (s1 < 1e-3 || s2 < 1e-3) continue;
		real d2 = 2.0 * ((c.y - m.y) / s2 - (m.y - a.y) / s1) / (s1 + s2);
		vcurv_[i] = -d2;
	}
	std::vector<real> vs(n);
	for (int i = 0; i < n; ++i) vs[i] = (vcurv_[wrap(i - 2)] + vcurv_[wrap(i - 1)] + vcurv_[i] + vcurv_[wrap(i + 1)] + vcurv_[wrap(i + 2)]) * 0.2;
	vcurv_.swap(vs);
}

int RacingLine::nearest(const Vec3 &p, int hint, int window) const {
	int n = (int)pts_.size();
	if (n == 0) return 0;
	int best = 0;
	real best_d = std::numeric_limits<real>::max();
	if (hint < 0) {
		for (int i = 0; i < n; ++i) {
			Vec3 dv = pts_[i] - p;
			real d = dv.x * dv.x + dv.z * dv.z + 6.0 * dv.y * dv.y;
			if (d < best_d) {
				best_d = d;
				best = i;
			}
		}
		return best;
	}
	// Forward-biased window and height-weighted distance: on switchbacks the next leg can be
	// closer horizontally than the current one, but it is several meters higher or lower.
	int back = std::max(4, window / 3);
	for (int k = -back; k <= window; ++k) {
		int i = closed_ ? wrap(hint + k) : hint + k;
		if (i < 0 || i >= n) continue;
		Vec3 d = pts_[i] - p;
		real dist = d.x * d.x + d.z * d.z + 6.0 * d.y * d.y;
		if (dist < best_d) {
			best_d = dist;
			best = i;
		}
	}
	return best;
}

int RacingLine::index_ahead(int i, real ahead) const {
	int n = (int)pts_.size();
	int idx = wrap(i);
	real acc = 0.0;
	int guard = 0;
	while (acc < ahead && guard++ < n) {
		int nx = wrap(idx + 1);
		if (!closed_ && nx == idx) break;
		acc += distance(pts_[idx], pts_[nx]);
		idx = nx;
	}
	return idx;
}

Vec3 RacingLine::position_ahead(int i, real ahead, real lateral_shift, int *out_index) const {
	int n = (int)pts_.size();
	int idx = wrap(i);
	real remaining = ahead;
	int guard = 0;
	while (guard++ < n) {
		int nx = wrap(idx + 1);
		if (!closed_ && nx == idx) break;
		real seg = distance(pts_[idx], pts_[nx]);
		if (remaining <= seg && seg > 1e-6) {
			real t = remaining / seg;
			if (out_index) *out_index = idx;
			Vec3 r = lerp(right_vector(idx), right_vector(nx), t).normalized();
			real e = lerpr(offset_[idx], offset_[nx], t);
			const TrackSample &sa = samples_[idx];
			const TrackSample &sb = samples_[nx];
			real lo = -std::max(0.3, lerpr(sa.half_width_left, sb.half_width_left, t) - 0.9);
			real hi = std::max(0.3, lerpr(sa.half_width_right, sb.half_width_right, t) - 0.9);
			real shift = clampr(e + lateral_shift, lo, hi) - e;
			return lerp(pts_[idx], pts_[nx], t) + r * shift;
		}
		remaining -= seg;
		idx = nx;
	}
	if (out_index) *out_index = idx;
	return pts_[idx];
}

real RacingLine::progress(const Vec3 &p, int index) const {
	int i = wrap(index);
	int nx = wrap(i + 1);
	Vec3 seg = pts_[nx] - pts_[i];
	real len = seg.length();
	real t = len > 1e-6 ? clampr((p - pts_[i]).dot(seg) / (len * len), 0.0, 1.0) : 0.0;
	return dist_[i] + t * len;
}

void RacingLine::speed_profile(std::vector<real> &out, real mu, real df, real mass, real accel, real decel, real top) const {
	int n = (int)pts_.size();
	out.assign(n, top);
	if (n == 0) return;
	for (int i = 0; i < n; ++i) {
		real k = std::fabs(curv_[i]);
		real g = GRAVITY * samples_[i].grip;
		// Hairpins (R < 30 m) punish any overshoot with a wall; keep extra margin there.
		real m = mu * lerpr(1.0, 0.86, smoothstep(1.0 / 60.0, 1.0 / 18.0, k));
		// Narrow two-lane roads leave no room to run wide.
		real half = std::min(samples_[i].half_width_left, samples_[i].half_width_right);
		m *= lerpr(0.93, 1.0, smoothstep(3.5, 6.0, half));
		// Crests unload the car: lateral grip ~ m * (g - v^2 kv). Dips add a little.
		real kv = vcurv_.empty() ? 0.0 : vcurv_[i];
		real den = k + m * std::max(kv, 0.0) - m * df / mass;
		real v = den > 1e-6 ? std::sqrt(m * g / den) : top;
		// Never go light over a crest: keep 70% of the car's weight on the tyres.
		if (kv > 1e-5) v = std::min(v, std::sqrt(0.3 * GRAVITY / kv));
		// Road-width speed cap: a 7 m country lane leaves no room for tracking error at 250 km/h
		// (~190 km/h there), while avenues and expressways allow 270+.
		v = std::min(v, 28.0 + 7.0 * half);
		out[i] = std::min(v, top);
	}
	auto seg_len = [&](int i) { return distance(pts_[i], pts_[wrap(i + 1)]); };
	int passes = closed_ ? 2 : 1;
	// Forward: traction-limited acceleration shares the friction circle with cornering.
	for (int p = 0; p < passes; ++p) {
		for (int j = 0; j < n; ++j) {
			int i = j, nx = wrap(j + 1);
			if (!closed_ && j == n - 1) break;
			real v = out[i];
			real lat_use = v * v * std::fabs(curv_[i]) / (mu * GRAVITY + 1e-6);
			real a = accel * (1.0 - sqr(v / top)) * std::sqrt(std::max(0.0, 1.0 - sqr(std::min(lat_use, 1.0))));
			real vmax = std::sqrt(v * v + 2.0 * std::max(a, 0.0) * seg_len(i));
			if (out[nx] > vmax) out[nx] = vmax;
		}
	}
	// Backward: braking.
	for (int p = 0; p < passes; ++p) {
		for (int j = n - 1; j >= 0; --j) {
			int i = j, nx = wrap(j + 1);
			if (!closed_ && j == n - 1) continue;
			real v = out[nx];
			real lat_use = v * v * std::fabs(curv_[nx]) / (mu * GRAVITY + 1e-6);
			real d = decel * std::sqrt(std::max(0.05, 1.0 - sqr(std::min(lat_use, 1.0))));
			real vmax = std::sqrt(v * v + 2.0 * d * seg_len(i));
			if (out[i] > vmax) out[i] = vmax;
		}
	}
}

CarEnvelope estimate_envelope(const VehicleParams &p) {
	CarEnvelope e;
	real grip = (p.tire_front.grip + p.tire_rear.grip) * 0.5;
	e.mu = grip * 0.82;
	e.downforce_per_v2 = 0.5 * AIR_DENSITY * (p.lift_front + p.lift_rear);
	// Peak power from the torque curve (incl. boost).
	real boost_mult = 1.0 + p.max_boost * p.boost_gain;
	real peak_power = 0.0;
	for (int i = 0; i < p.torque_curve.n; ++i) {
		real w = p.torque_curve.xs[i] * TAU / 60.0;
		real t = p.torque_curve.ys[i] * (p.torque_curve.xs[i] > p.spool_rpm ? boost_mult : 1.0);
		peak_power = std::max(peak_power, w * t);
	}
	peak_power += p.hybrid_boost_nm * 300.0 * 0.5;
	real v_drag = std::cbrt(peak_power * p.drivetrain_efficiency / (0.5 * AIR_DENSITY * p.drag_area));
	real R = p.wheel_radius_rear;
	real v_gear = p.redline_rpm * TAU / 60.0 / (p.gear_ratios[p.gear_count - 1] * p.final_drive) * R;
	e.top_speed = std::min(v_drag, v_gear);
	if (p.top_speed_limiter > 0.0) e.top_speed = std::min(e.top_speed, p.top_speed_limiter);
	real driven_frac = p.layout == DRIVE_AWD ? 1.0 : (p.layout == DRIVE_FF ? p.weight_front : 1.0 - p.weight_front);
	real traction = e.mu * GRAVITY * std::min(1.0, driven_frac + 0.08);
	real peak_t = p.torque_curve.max_y() * boost_mult;
	real power_accel = peak_t * p.gear_ratios[1] * p.final_drive * p.drivetrain_efficiency / R / p.mass;
	e.accel = std::min(traction, power_accel) * 0.8;
	e.decel = std::min(e.mu * GRAVITY * 0.92, p.brake_torque / (R * p.mass) * 0.95);
	return e;
}

} // namespace nt
