// Static collision world: triangles bucketed into a 2D (XZ) hash grid. Chunks stream in and out
// on the main thread between physics ticks; all queries are read-only and safe to run from many
// worker threads at once (the vehicle step for every car runs in parallel).
#pragma once

#include "surface.h"
#include "vmath.h"

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace nt {

struct Tri {
	float v0[3], v1[3], v2[3];
	float n[3];
	uint8_t surface;
	uint8_t flags;
};

struct RayHit {
	real t = 0;
	Vec3 point;
	Vec3 normal;
	int surface = SURF_ASPHALT;
	bool hit = false;
};

struct SphereContact {
	Vec3 point; // closest point on the triangle
	Vec3 normal; // from triangle toward sphere center
	real depth = 0;
	int surface = SURF_ASPHALT;
};

class CollisionGrid {
public:
	explicit CollisionGrid(real cell_size = 8.0) : cell_(cell_size), inv_cell_(1.0 / cell_size) {}

	// Adds a chunk's triangles. `positions` holds 9 floats per triangle. Returns false if the
	// chunk id already exists.
	bool add_chunk(int64_t chunk_id, const float *positions, const uint8_t *surfaces, const uint8_t *flags, int tri_count);
	void remove_chunk(int64_t chunk_id);
	void clear();
	bool has_chunk(int64_t chunk_id) const { return chunks_.count(chunk_id) != 0; }
	int chunk_count() const { return (int)chunks_.size(); }
	int triangle_count() const;

	// Nearest hit along the ray within [0, max_t]. Two-sided unless `front_only`.
	RayHit raycast(const Vec3 &origin, const Vec3 &dir, real max_t, uint8_t mask, bool front_only = false) const;
	// Fills up to `max_out` contacts where the sphere overlaps SOLID triangles. Returns count.
	int sphere_contacts(const Vec3 &center, real radius, uint8_t mask, SphereContact *out, int max_out) const;
	// Height of the highest DRIVABLE surface below `from` (within `max_drop`). NaN if none.
	real ground_height(const Vec3 &from, real max_drop, Vec3 *normal = nullptr, int *surface = nullptr) const;

private:
	struct TriRef {
		uint32_t chunk_slot;
		uint32_t index;
	};
	struct Chunk {
		int64_t id;
		std::vector<Tri> tris;
		std::vector<int64_t> cells;
	};

	static int64_t key(int32_t cx, int32_t cz) { return ((int64_t)cx << 32) ^ (int64_t)(uint32_t)cz; }
	int32_t cell_of(real v) const { return (int32_t)std::floor(v * inv_cell_); }
	const Tri &tri(const TriRef &r) const { return slots_[r.chunk_slot].tris[r.index]; }
	void test_cell(int32_t cx, int32_t cz, const Vec3 &o, const Vec3 &d, real &best_t, RayHit &best, uint8_t mask, bool front_only) const;

	real cell_;
	real inv_cell_;
	std::vector<Chunk> slots_;
	std::vector<uint32_t> free_slots_;
	std::unordered_map<int64_t, uint32_t> chunks_;
	std::unordered_map<int64_t, std::vector<TriRef>> cells_;
};

// Geometry helpers exposed for tests.
bool ray_triangle(const Vec3 &o, const Vec3 &d, const Vec3 &a, const Vec3 &b, const Vec3 &c, real &t, bool front_only);
Vec3 closest_point_on_triangle(const Vec3 &p, const Vec3 &a, const Vec3 &b, const Vec3 &c);

} // namespace nt
