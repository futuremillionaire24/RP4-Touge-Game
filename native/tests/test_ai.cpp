#include "doctest.h"

#include "sim/roster.h"
#include "sim/spline.h"
#include "sim/world_sim.h"

#include <cstdio>

using namespace nt;

static const real DT = 1.0 / 120.0;

static void flat_ground(CollisionGrid &g, real half) {
	std::vector<float> pos;
	std::vector<uint8_t> surf, flags;
	const real tile = 64.0;
	for (real x = -half; x < half; x += tile)
		for (real z = -half; z < half; z += tile) {
			float a[3] = {(float)x, 0.f, (float)z}, b[3] = {(float)x, 0.f, (float)(z + tile)};
			float c[3] = {(float)(x + tile), 0.f, (float)(z + tile)}, d[3] = {(float)(x + tile), 0.f, (float)z};
			for (float *v : {a, b, c, a, c, d}) pos.insert(pos.end(), v, v + 3);
			surf.insert(surf.end(), {0, 0});
			flags.insert(flags.end(), {COL_ALL, COL_ALL});
		}
	g.add_chunk(1, pos.data(), surf.data(), flags.data(), (int)surf.size());
}

// Mixed circuit: long straight, fast sweeper, hairpin, chicane, medium corners (~2.3 km).
static std::vector<TrackSample> test_circuit(real half_width) {
	Spline sp({{0, 0, 0}, {250, 0, 0}, {380, 0, -40}, {420, 0, -150}, {360, 0, -230}, {250, 0, -220}, {200, 0, -160},
					  {140, 0, -200}, {60, 0, -300}, {-80, 0, -300}, {-160, 0, -220}, {-140, 0, -120}, {-200, 0, -60}, {-120, 0, 10}},
			true);
	std::vector<Vec3> pts, tan;
	sp.resample(3.0, pts, tan);
	std::vector<TrackSample> out(pts.size());
	for (size_t i = 0; i < pts.size(); ++i) {
		out[i].center = pts[i];
		out[i].tangent = tan[i];
		out[i].half_width_left = out[i].half_width_right = half_width;
	}
	return out;
}

static void grid_start(WorldSim &w, int slot, int car) {
	const RacingLine &L = w.line;
	int back = L.size() - 1 - slot * 3; // 9 m per row pair
	int idx = L.wrap(back);
	Vec3 c = L.sample(idx).center;
	Vec3 r = L.right_vector(idx);
	Vec3 dir = L.sample(idx).tangent;
	Vec3 pos = c + r * (slot % 2 ? 2.8 : -2.8) + Vec3(0, w.cars[car].params.cg_height + 0.1, 0);
	w.cars[car].reset(pos, quat_look(dir, {0, 1, 0}), 0.0);
	w.reset_progress(car);
}

TEST_CASE("racing line stays inside the corridor and is smoother than the centerline") {
	auto samples = test_circuit(6.0);
	RacingLine L;
	L.build(samples, true);
	real sum_center = 0, sum_line = 0, max_center = 0, max_line = 0;
	RacingLine C;
	C.build(samples, true, 0.9, 0); // zero iterations = centerline
	for (int i = 0; i < L.size(); ++i) {
		CHECK(L.offset(i) >= -5.1 - 1e-6);
		CHECK(L.offset(i) <= 5.1 + 1e-6);
		sum_line += sqr(L.curvature(i));
		sum_center += sqr(C.curvature(i));
		max_line = std::max(max_line, std::fabs(L.curvature(i)));
		max_center = std::max(max_center, std::fabs(C.curvature(i)));
	}
	CHECK(sum_line < sum_center * 0.9);
	CHECK(max_line < max_center * 0.8); // tightest corner opened up by 20%+
	CHECK(L.length() > 1500.0);
}

TEST_CASE("12 AI cars finish a 3-lap race without getting stuck") {
	WorldSim w;
	flat_ground(w.grid, 1200.0);
	w.set_line(test_circuit(7.0), true);
	const int N = 12;
	for (int i = 0; i < N; ++i) {
		int car_id = i % CAR_COUNT;
		int id = w.add_car(make_car_params(car_id), true, 1000 + i);
		w.ai[id].personality = difficulty_personality(4, 77 + i);
		// Equalize: race of mixed classes, scale each car so the field is close.
	}
	for (int i = 0; i < N; ++i) {
		grid_start(w, i, i);
		w.ai[i].set_line(&w.line, w.cars[i]);
	}
	const int LAPS = 3;
	std::vector<real> finish(N, -1.0);
	std::vector<real> best_lap(N, 1e9), lap_start(N, 0.0);
	std::vector<int> last_lap(N, 0);
	real t = 0;
	for (int step = 0; step < 120 * 900; ++step) {
		w.step(DT);
		t += DT;
		bool all = true;
		for (int i = 0; i < N; ++i) {
			const RaceProgress &p = w.progress[i];
			if (p.lap > last_lap[i]) {
				if (last_lap[i] >= 1) best_lap[i] = std::min(best_lap[i], t - lap_start[i]);
				lap_start[i] = t;
				last_lap[i] = p.lap;
			}
			if (finish[i] < 0 && p.lap >= LAPS) finish[i] = t;
			if (finish[i] < 0) all = false;
		}
		if (all) break;
	}
	std::printf("\n%-16s %9s %9s %9s\n", "car", "finish s", "best lap", "respawns");
	int finished = 0;
	for (int i = 0; i < N; ++i) {
		std::printf("%-16s %9.1f %9.1f %9d\n", car_key(i % CAR_COUNT), finish[i], best_lap[i] < 1e8 ? best_lap[i] : -1.0, w.progress[i].respawn_count);
		if (finish[i] > 0) finished++;
		INFO("car " << i);
		CHECK(w.progress[i].respawn_count <= 2);
	}
	CHECK(finished == N);
}
