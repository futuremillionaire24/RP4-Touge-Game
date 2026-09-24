#include "heightfield.h"

namespace nt {

void Heightfield::init(real min_x, real min_z, real size_x, real size_z, real cell) {
	cell_ = cell;
	min_x_ = min_x;
	min_z_ = min_z;
	w_ = (int)std::ceil(size_x / cell) + 1;
	h_ = (int)std::ceil(size_z / cell) + 1;
	data_.assign((size_t)w_ * h_, 0.0f);
	mask_.assign((size_t)w_ * h_, 0);
	carve_weight_.assign((size_t)w_ * h_, 0.0f);
}

real Heightfield::sample(real x, real z) const {
	real fx = (x - min_x_) / cell_, fz = (z - min_z_) / cell_;
	int ix = (int)std::floor(fx), iz = (int)std::floor(fz);
	real tx = fx - ix, tz = fz - iz;
	real a = at(ix, iz), b = at(ix + 1, iz), c = at(ix, iz + 1), d = at(ix + 1, iz + 1);
	return lerpr(lerpr(a, b, tx), lerpr(c, d, tx), tz);
}

Vec3 Heightfield::normal(real x, real z) const {
	real e = cell_;
	real hx = sample(x + e, z) - sample(x - e, z);
	real hz = sample(x, z + e) - sample(x, z - e);
	return Vec3(-hx, 2.0 * e, -hz).normalized();
}

int Heightfield::material(real x, real z) const {
	int ix = (int)std::round((x - min_x_) / cell_), iz = (int)std::round((z - min_z_) / cell_);
	return mask_at(ix, iz);
}

static real seg_dist(const Vec3 &p, const Vec3 &a, const Vec3 &b, real &t) {
	Vec3 ab = (b - a).flat(), ap = (p - a).flat();
	real l2 = ab.length_sq();
	t = l2 > 1e-9 ? clampr(ap.dot(ab) / l2, 0.0, 1.0) : 0.0;
	return (ap - ab * t).length();
}

void Heightfield::carve_segment(const Vec3 &a, const Vec3 &b, real half_width, real blend, uint8_t material) {
	real reach = half_width + blend;
	real minx = std::min(a.x, b.x) - reach, maxx = std::max(a.x, b.x) + reach;
	real minz = std::min(a.z, b.z) - reach, maxz = std::max(a.z, b.z) + reach;
	int ix0 = clampi((int)std::floor((minx - min_x_) / cell_), 0, w_ - 1), ix1 = clampi((int)std::ceil((maxx - min_x_) / cell_), 0, w_ - 1);
	int iz0 = clampi((int)std::floor((minz - min_z_) / cell_), 0, h_ - 1), iz1 = clampi((int)std::ceil((maxz - min_z_) / cell_), 0, h_ - 1);
	for (int iz = iz0; iz <= iz1; ++iz) {
		for (int ix = ix0; ix <= ix1; ++ix) {
			Vec3 p(min_x_ + ix * cell_, 0.0, min_z_ + iz * cell_);
			real t;
			real d = seg_dist(p, a, b, t);
			if (d > reach) continue;
			// Terrain sits well under the road deck: banking drops the low edge ~0.3 m below the
			// centreline, and terrain poking through would kick the wheels at speed.
			real road_y = lerpr(a.y, b.y, t) - 0.6;
			// Weight 1 on the road, easing out over the embankment.
			real w = d <= half_width ? 1.0 : 1.0 - smoothstep(half_width, reach, d);
			size_t k = (size_t)iz * w_ + ix;
			// Stronger (closer) carves win so crossing roads don't fight.
			if (w <= carve_weight_[k] * 0.999) continue;
			data_[k] = (float)lerpr(data_[k], road_y, w);
			carve_weight_[k] = (float)w;
			if (d <= half_width + 1.5) mask_[k] = material;
		}
	}
}

void Heightfield::keep_below(const Vec3 &a, const Vec3 &b, real half_width, real depth) {
	real reach = half_width;
	real minx = std::min(a.x, b.x) - reach, maxx = std::max(a.x, b.x) + reach;
	real minz = std::min(a.z, b.z) - reach, maxz = std::max(a.z, b.z) + reach;
	int ix0 = clampi((int)std::floor((minx - min_x_) / cell_), 0, w_ - 1), ix1 = clampi((int)std::ceil((maxx - min_x_) / cell_), 0, w_ - 1);
	int iz0 = clampi((int)std::floor((minz - min_z_) / cell_), 0, h_ - 1), iz1 = clampi((int)std::ceil((maxz - min_z_) / cell_), 0, h_ - 1);
	for (int iz = iz0; iz <= iz1; ++iz)
		for (int ix = ix0; ix <= ix1; ++ix) {
			Vec3 p(min_x_ + ix * cell_, 0.0, min_z_ + iz * cell_);
			real t;
			if (seg_dist(p, a, b, t) > reach) continue;
			float limit = (float)(lerpr(a.y, b.y, t) - depth);
			float &hgt = data_[(size_t)iz * w_ + ix];
			if (hgt > limit) hgt = limit;
		}
}

} // namespace nt
