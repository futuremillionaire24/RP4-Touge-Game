// Global terrain heightfield (regular grid) with bilinear sampling and road carving.
#pragma once

#include "../vmath.h"

#include <cstdint>
#include <vector>

namespace nt {

class Heightfield {
public:
	// World rectangle [min_x, min_x + size_x] x [min_z, min_z + size_z] at `cell` meters.
	void init(real min_x, real min_z, real size_x, real size_z, real cell);
	int width() const { return w_; }
	int height() const { return h_; }
	real cell() const { return cell_; }
	real min_x() const { return min_x_; }
	real min_z() const { return min_z_; }
	real max_x() const { return min_x_ + (w_ - 1) * cell_; }
	real max_z() const { return min_z_ + (h_ - 1) * cell_; }

	float &at(int ix, int iz) { return data_[(size_t)iz * w_ + ix]; }
	float at(int ix, int iz) const { return data_[(size_t)clampi(iz, 0, h_ - 1) * w_ + clampi(ix, 0, w_ - 1)]; }
	uint8_t &mask(int ix, int iz) { return mask_[(size_t)iz * w_ + ix]; }
	uint8_t mask_at(int ix, int iz) const { return mask_[(size_t)clampi(iz, 0, h_ - 1) * w_ + clampi(ix, 0, w_ - 1)]; }

	real sample(real x, real z) const;
	Vec3 normal(real x, real z) const;
	// Surface material hint written by the generator (0 grass, 1 dirt, 2 rock, 3 sand, 4 paddy, 5 urban).
	int material(real x, real z) const;

	// Fills heights from a function of (x, z), multithreaded by row bands via `rows_fn`.
	template <typename F>
	void fill_rows(int row_begin, int row_end, F &&fn) {
		for (int iz = row_begin; iz < row_end; ++iz)
			for (int ix = 0; ix < w_; ++ix) {
				real x = min_x_ + ix * cell_, z = min_z_ + iz * cell_;
				data_[(size_t)iz * w_ + ix] = (float)fn(x, z, mask_[(size_t)iz * w_ + ix]);
			}
	}

	// Blends the terrain toward `road_y` inside `half_width` (flat) with an embankment falloff
	// of `blend` meters beyond. `priority` stops later roads from undercutting earlier ones.
	void carve_segment(const Vec3 &a, const Vec3 &b, real half_width, real blend, uint8_t material);
	// Keeps terrain at least `depth` below a line (for bridges / elevated roads: clears the ground).
	void keep_below(const Vec3 &a, const Vec3 &b, real half_width, real depth);

private:
	static int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
	std::vector<float> data_;
	std::vector<uint8_t> mask_;
	std::vector<float> carve_weight_;
	int w_ = 0, h_ = 0;
	real cell_ = 4.0, min_x_ = 0.0, min_z_ = 0.0;
};

} // namespace nt
