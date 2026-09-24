#include "doctest.h"

#include "sim/roster.h"
#include "sim/world/chunk_builder.h"
#include "sim/world/world.h"
#include "sim/world_sim.h"

#include <chrono>
#include <cstdio>

using namespace nt;

static World &shared_world() {
	static World w;
	static bool built = false;
	if (!built) {
		auto t0 = std::chrono::steady_clock::now();
		w.build(1);
		auto t1 = std::chrono::steady_clock::now();
		std::printf("\nworld build: %.0f ms, %d roads, %d junctions, %d blocks, %d pois\n",
				std::chrono::duration<double, std::milli>(t1 - t0).count(), (int)w.roads.size(), (int)w.junctions.size(), (int)w.blocks.size(), (int)w.pois.size());
		built = true;
	}
	return w;
}

TEST_CASE("world builds a large connected network") {
	World &w = shared_world();
	real total = 0.0;
	int tunnels = 0, bridges = 0;
	for (const Road &r : w.roads) {
		total += r.length;
		for (const RoadSampleX &s : r.samples) {
			tunnels += s.type == ST_TUNNEL;
			bridges += s.type == ST_BRIDGE;
		}
	}
	std::printf("road length %.1f km, tunnel %.1f km, bridge %.1f km\n", total / 1000.0, tunnels * 3.0 / 1000.0, bridges * 3.0 / 1000.0);
	CHECK(total > 30000.0);
	CHECK(bridges > 100);
	int touge = w.road_by_name("touge_ascent");
	REQUIRE(touge >= 0);
	const Road &t = w.roads[touge];
	real climb = t.samples.back().rs.center.y - t.samples.front().rs.center.y;
	std::printf("touge ascent: %.1f km, climb %.0f m\n", t.length / 1000.0, climb);
	CHECK(t.length > 3000.0);
	CHECK(climb > 250.0);
	// Hairpins: count spots with radius < 30 m.
	int hairpins = 0;
	bool in_pin = false;
	for (size_t i = 5; i + 5 < t.samples.size(); ++i) {
		Vec3 a = t.samples[i - 5].rs.center, b = t.samples[i].rs.center, c = t.samples[i + 5].rs.center;
		Vec3 ab = (b - a).flat(), bc = (c - b).flat(), ac = (c - a).flat();
		real k = 2.0 * std::fabs(ab.x * bc.z - ab.z * bc.x) / (ab.length() * bc.length() * ac.length() + 1e-9);
		bool pin = k > 1.0 / 30.0;
		if (pin && !in_pin) hairpins++;
		in_pin = pin;
	}
	std::printf("touge hairpins: %d\n", hairpins);
	CHECK(hairpins >= 10);
}

TEST_CASE("chunks build fast with sane contents") {
	World &w = shared_world();
	ChunkOptions opt;
	int cx = (int)((0.0 - w.min_x()) / World::CHUNK), cz = (int)((0.0 - w.min_z()) / World::CHUNK);
	auto t0 = std::chrono::steady_clock::now();
	ChunkOutput city;
	build_chunk(w, cx, cz, opt, city);
	auto t1 = std::chrono::steady_clock::now();
	int tris = 0;
	for (auto &g : city.groups) tris += (int)g.indices.size() / 3;
	int props = 0;
	for (auto &p : city.props) props += (int)p.size();
	std::printf("city chunk: %.1f ms, %d tris, %d collision tris, %d props, %d lights, %d building verts\n",
			std::chrono::duration<double, std::milli>(t1 - t0).count(), tris, city.collision.tri_count(), props, (int)city.lights.size() / 5,
			city.groups[WG_BUILDING].vertex_count());
	CHECK(city.groups[WG_BUILDING].vertex_count() > 100);
	CHECK(city.groups[GROUP_ROAD].vertex_count() > 50);
	CHECK(city.collision.tri_count() > 1000);
	// Every chunk in the map builds without blowing up (lod 2 to keep the test quick).
	ChunkOptions far;
	far.lod = 2;
	far.collision = false;
	int total_tris = 0;
	auto t2 = std::chrono::steady_clock::now();
	for (int z = 0; z < w.chunks_z(); ++z)
		for (int x = 0; x < w.chunks_x(); ++x) {
			ChunkOutput o;
			build_chunk(w, x, z, far, o);
			for (auto &g : o.groups) total_tris += (int)g.indices.size() / 3;
		}
	auto t3 = std::chrono::steady_clock::now();
	std::printf("all %d chunks @lod2: %.0f ms, %.1f M tris\n", w.chunks_x() * w.chunks_z(), std::chrono::duration<double, std::milli>(t3 - t2).count(), total_tris / 1e6);
}

TEST_CASE("AI completes the touge ascent on real terrain") {
	World &w = shared_world();
	int ti = w.road_by_name("touge_ascent");
	REQUIRE(ti >= 0);
	const Road &road = w.roads[ti];
	WorldSim sim;
	// Collision for every chunk the road passes through (and neighbours).
	std::vector<int64_t> loaded;
	auto load = [&](int cx, int cz) {
		int64_t id = (int64_t)cx * 100000 + cz;
		if (std::find(loaded.begin(), loaded.end(), id) != loaded.end()) return;
		loaded.push_back(id);
		ChunkOptions opt;
		opt.props = false;
		ChunkOutput o;
		build_chunk(w, cx, cz, opt, o);
		sim.grid.add_chunk(id, o.collision.positions.data(), o.collision.surfaces.data(), o.collision.flags.data(), o.collision.tri_count());
	};
	for (const RoadSampleX &s : road.samples) {
		int cx = (int)std::floor((s.rs.center.x - w.min_x()) / World::CHUNK);
		int cz = (int)std::floor((s.rs.center.z - w.min_z()) / World::CHUNK);
		for (int dx = -1; dx <= 1; ++dx)
			for (int dz = -1; dz <= 1; ++dz) load(cx + dx, cz + dz);
	}
	std::vector<TrackSample> ts(road.samples.size());
	for (size_t i = 0; i < ts.size(); ++i) {
		ts[i].center = road.samples[i].rs.center;
		ts[i].tangent = road.samples[i].rs.tangent;
		ts[i].normal = road.samples[i].rs.up;
		ts[i].half_width_left = road.samples[i].rs.width_left;
		ts[i].half_width_right = road.samples[i].rs.width_right;
	}
	sim.set_line(ts, false);
	int id = sim.add_car(make_car_params(CAR_HACHI_GT), true, 42);
	sim.ai[id].personality = difficulty_personality(5, 3);
	const RoadSample &s0 = road.samples[2].rs;
	sim.cars[id].reset(s0.center + Vec3(0, 0.7, 0), quat_look(s0.tangent, Vec3(0, 1, 0)), 0.0);
	sim.ai[id].set_line(&sim.line, sim.cars[id]);
	sim.reset_progress(id);
	real t = 0.0;
	bool finished = false;
	while (t < 900.0) {
		sim.step(1.0 / 120.0);
		t += 1.0 / 120.0;
		if (sim.progress[id].line_index >= sim.line.size() - 15) { // finish line 45 m before the road end
			finished = true;
			break;
		}
	}
	std::printf("touge ascent AI time: %.1f s (%.1f km/h avg), respawns %d\n", t, road.length / t * 3.6, sim.progress[id].respawn_count);
	CHECK(finished);
	CHECK(sim.progress[id].respawn_count <= 3);
}
