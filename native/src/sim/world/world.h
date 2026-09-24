// The whole map: terrain, road network, junctions, city blocks and points of interest.
// build() is deterministic for a seed and takes well under a second on the Dimensity 1100.
#pragma once

#include "heightfield.h"
#include "world_types.h"

#include <vector>

namespace nt {

struct NearestRoad {
	int road = -1;
	int sample = -1;
	real distance = 1e9;
	real lateral = 0.0; // + right of travel direction
	real s = 0.0; // arc length
};

class World {
public:
	static constexpr real CHUNK = 256.0;
	static constexpr real SEA_LEVEL = 0.0;

	Heightfield terrain;
	std::vector<Road> roads;
	std::vector<Intersection> junctions;
	std::vector<Block> blocks;
	std::vector<Poi> pois;
	uint64_t seed = 1;

	void build(uint64_t seed);

	real base_height(real x, real z, uint8_t &material) const; // pre-carve terrain function
	real height(real x, real z) const { return terrain.sample(x, z); }
	District district_at(real x, real z) const;
	NearestRoad nearest_road(const Vec3 &p, real max_dist = 60.0) const;
	bool is_sea(real x, real z) const;

	// Chunk grid.
	real min_x() const { return terrain.min_x(); }
	real min_z() const { return terrain.min_z(); }
	int chunks_x() const { return (int)std::ceil((terrain.max_x() - terrain.min_x()) / CHUNK); }
	int chunks_z() const { return (int)std::ceil((terrain.max_z() - terrain.min_z()) / CHUNK); }
	void chunk_bounds(int cx, int cz, Vec3 &mn, Vec3 &mx) const;
	// Roads (index, sample range) overlapping a chunk.
	struct RoadSpan {
		int road;
		int begin, end; // sample indices, inclusive begin, exclusive end
	};
	std::vector<RoadSpan> roads_in_chunk(int cx, int cz, real margin = 6.0) const;

	// Named road lookup (for events / racing lines).
	int road_by_name(const std::string &name) const;
	// Chains roads end to end ("~name" = driven in reverse) into one sampled route, bridging
	// junction gaps with interpolated samples. Output feeds WorldSim::set_line.
	std::vector<struct RouteSample> compose_route(const std::vector<std::string> &names) const;

private:
	void layout_roads();
	void layout_pois();
	void process_road(Road &r);
	void classify_and_furnish(Road &r, const std::vector<Vec3> &pts, const std::vector<Vec3> &tan, const std::vector<real> &ys,
			const std::vector<real> &base);
	void add_road(RoadDef def);
	void carve_roads();
	void open_merges();
	void weld_endpoints();
	void make_touge(const Vec3 &base, const Vec3 &summit, int hairpins, real leg_len, uint64_t s, const char *name, bool descent_fast);
	std::vector<RoadDef> defs_;
};

} // namespace nt
