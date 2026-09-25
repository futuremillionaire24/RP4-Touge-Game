// The whole map: terrain, road network, junctions, city blocks and points of interest.
// build() is deterministic for a seed and takes well under a second on the Dimensity 1100.
#pragma once

#include "heightfield.h"
#include "world_types.h"

#include <string>
#include <unordered_map>
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
	std::vector<int> road_of_def; // baked: RoadDef::id (baker edge index) -> index in `roads`, -1 if dropped
	uint64_t seed = 1;
	// Baked map (tools/mapbake) data.
	bool baked = false;
	std::vector<Building> buildings;
	std::vector<Tree> trees;
	std::vector<Route> routes;
	std::vector<std::string> district_names;

	void build(uint64_t seed);
	// Loads a tools/mapbake "NTMB" blob (heights, land, districts, roads, junctions, buildings,
	// trees, POIs, routes) and builds the world from it. Returns false with `error` set on failure.
	bool build_from_bake(const uint8_t *data, size_t size, std::string &error);
	uint8_t land_at(real x, real z) const;
	// Road indices meeting at a road-graph vertex (baked maps).
	const std::vector<int> &roads_at_node(int64_t node) const;

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
	void index_nodes();
	void weld_baked_junctions();
	void fit_baked_junctions();
	void clear_buildings_off_roads();
	void clip_junction_overlaps();
	void dress_circuits();
	void shape_quays();
	real bake_height(real x, real z) const;
	std::vector<RoadDef> defs_;
	// Baked grids.
	std::vector<uint16_t> bake_h_;
	std::vector<uint8_t> bake_land_, bake_dist_;
	real bake_x0_ = 0, bake_z0_ = 0, bake_cell_ = 8, dist_cell_ = 32;
	int bake_w_ = 0, bake_hgt_ = 0, dist_w_ = 0, dist_h_ = 0;
	std::unordered_map<int64_t, std::vector<int>> node_roads_;
};

} // namespace nt
