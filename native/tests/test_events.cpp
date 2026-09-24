#include "doctest.h"

#include "sim/roster.h"
#include "sim/world/chunk_builder.h"
#include "sim/world/world.h"
#include "sim/world_sim.h"

#include <algorithm>
#include <cstdio>
#include <string>

using namespace nt;

World &test_world_instance(); // defined below (shared with this file only)

World &test_world_instance() {
	static World w;
	static bool built = false;
	if (!built) {
		w.build(1);
		built = true;
	}
	return w;
}

struct EventSpec {
	const char *id;
	std::vector<std::string> roads;
	bool closed;
	int laps;
	int grid;
};

static std::vector<std::string> city_loop() {
	std::vector<std::string> r;
	char b[32];
	for (int j = 2; j < 6; ++j) { std::snprintf(b, 32, "city_ns_2_%d", j); r.push_back(b); }
	for (int i = 2; i < 6; ++i) { std::snprintf(b, 32, "city_ew_6_%d", i); r.push_back(b); }
	for (int j = 5; j > 1; --j) { std::snprintf(b, 32, "~city_ns_6_%d", j); r.push_back(b); }
	for (int i = 5; i > 1; --i) { std::snprintf(b, 32, "~city_ew_2_%d", i); r.push_back(b); }
	return r;
}

// Mirrors godot/scripts/data/events.gd.
static std::vector<EventSpec> events() {
	return {
		{"shuto_c1_night", {"shuto_loop"}, true, 1, 8},
		{"shibuya_gp", city_loop(), true, 2, 8},
		{"docks_circuit", {"dock_ns_0_0", "dock_ns_0_1", "dock_ew_2_0", "dock_ew_2_1", "dock_ew_2_2", "~dock_ns_3_1", "~dock_ns_3_0", "~dock_ew_0_2", "~dock_ew_0_1", "~dock_ew_0_0"}, true, 2, 6},
		{"coast_sprint", {"coast_road"}, false, 1, 8},
		{"satoyama_sprint", {"rural_main"}, false, 1, 6},
		{"route1_sprint", {"~route1"}, false, 1, 6},
		{"akina_downhill", {"~touge_ascent"}, false, 1, 2},
		{"akina_north", {"touge_descent"}, false, 1, 4},
		{"wangan_duel", {"wangan_spur"}, false, 1, 2},
	};
}

static void load_route_collision(const World &w, WorldSim &sim, const std::vector<RouteSample> &route) {
	std::vector<int64_t> loaded;
	for (const RouteSample &s : route) {
		int cx = (int)std::floor((s.center.x - w.min_x()) / World::CHUNK), cz = (int)std::floor((s.center.z - w.min_z()) / World::CHUNK);
		for (int dx = -1; dx <= 1; ++dx)
			for (int dz = -1; dz <= 1; ++dz) {
				int64_t id = (int64_t)(cx + dx) * 100000 + cz + dz;
				if (std::find(loaded.begin(), loaded.end(), id) != loaded.end()) continue;
				loaded.push_back(id);
				ChunkOptions opt;
				opt.props = false;
				ChunkOutput o;
				build_chunk(w, cx + dx, cz + dz, opt, o);
				sim.grid.add_chunk(id, o.collision.positions.data(), o.collision.surfaces.data(), o.collision.flags.data(), o.collision.tri_count());
			}
	}
}

TEST_CASE("every event route is raceable by a full AI grid") {
	World &w = test_world_instance();
	std::printf("\n%-16s %7s %6s %9s %8s %9s\n", "event", "len km", "grid", "winner s", "finish", "respawns");
	const int car_pool[] = {CAR_SYLPH_S2, CAR_RAIJIN_R, CAR_TATSU_IX, CAR_ROTORA_FD, CAR_SENKO, CAR_TITAN_RZ, CAR_KYUDO_TYPE_S, CAR_HACHI_GT};
	for (const EventSpec &e : events()) {
		std::vector<RouteSample> route = w.compose_route(e.roads);
		REQUIRE(route.size() > 50);
		WorldSim sim;
		load_route_collision(w, sim, route);
		std::vector<TrackSample> ts(route.size());
		for (size_t i = 0; i < route.size(); ++i) {
			ts[i].center = route[i].center;
			ts[i].tangent = route[i].tangent;
			ts[i].normal = route[i].up;
			ts[i].half_width_left = route[i].width_left;
			ts[i].half_width_right = route[i].width_right;
		}
		sim.set_line(ts, e.closed);
		int n = (int)route.size();
		int rows = (e.grid + 1) / 2;
		int start = e.closed ? 0 : std::min(8 + rows * 3, n - 1);
		for (int slot = 0; slot < e.grid; ++slot) {
			int id = sim.add_car(make_car_params(car_pool[slot % 8]), true, 500 + slot);
			sim.ai[id].personality = difficulty_personality(4, 91 + slot);
			int i = start - 5 - (slot / 2) * 3 - (slot % 2);
			i = e.closed ? ((i % n) + n) % n : std::clamp(i, 0, n - 1);
			Vec3 right = route[i].tangent.cross(Vec3(0, 1, 0)).normalized();
			real half = std::min(route[i].width_left, route[i].width_right);
			Vec3 pos = route[i].center + right * (std::clamp(half * 0.45, 1.6, 3.2) * (slot % 2 ? 1.0 : -1.0)) + Vec3(0, 0.9, 0);
			sim.cars[id].reset(pos, quat_look(route[i].tangent, Vec3(0, 1, 0)), 0.0);
			sim.ai[id].set_line(&sim.line, sim.cars[id]);
			sim.reset_progress(id);
		}
		real finish_dist = e.closed ? 0.0 : sim.line.distance_at(n - 1) - 20.0;
		std::vector<real> finish(e.grid, -1.0);
		real t = 0.0;
		const real limit = 1200.0;
		while (t < limit) {
			sim.step(1.0 / 120.0);
			t += 1.0 / 120.0;
			bool all = true;
			for (int k = 0; k < e.grid; ++k) {
				if (finish[k] > 0.0) continue;
				bool done = e.closed ? sim.progress[k].lap >= e.laps : sim.progress[k].line_distance >= finish_dist;
				if (done) {
					finish[k] = t;
					sim.cars[k].frozen = true; // parked after the flag, like the game does
				} else {
					all = false;
				}
			}
			if (all) break;
		}
		int finished = 0, respawns = 0;
		int reasons[5] = {0, 0, 0, 0, 0};
		real best = 1e9;
		for (int k = 0; k < e.grid; ++k) {
			if (finish[k] > 0.0) {
				finished++;
				best = std::min(best, finish[k]);
			}
			respawns += sim.progress[k].respawn_count;
			for (int q = 0; q < 5; ++q) reasons[q] += sim.progress[k].respawn_reasons[q];
		}
		std::printf("%-16s %7.2f %6d %9.1f %5d/%-2d %9d   (offtrack %d stuck %d flipped %d noprogress %d)\n", e.id, sim.line.length() / 1000.0, e.grid,
				best < 1e8 ? best : -1.0, finished, e.grid, respawns, reasons[1], reasons[2], reasons[3], reasons[4]);
		INFO("event " << e.id);
		CHECK(finished == e.grid);
		CHECK(respawns <= e.grid); // on average at most one incident per car
	}
}
