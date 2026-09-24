#include "benchmark.h"

#include "collision_grid.h"

#include <vector>

namespace nt {

static const real DT = 1.0 / 120.0;

static const CollisionGrid &test_pad() {
	static CollisionGrid g = [] {
		CollisionGrid grid;
		std::vector<float> pos;
		std::vector<uint8_t> surf, flags;
		const real half = 4200.0, tile = 128.0;
		for (real x = -half; x < half; x += tile)
			for (real z = -half; z < half; z += tile) {
				float a[3] = {(float)x, 0.f, (float)z}, b[3] = {(float)x, 0.f, (float)(z + tile)};
				float c[3] = {(float)(x + tile), 0.f, (float)(z + tile)}, d[3] = {(float)(x + tile), 0.f, (float)z};
				for (float *v : {a, b, c, a, c, d}) pos.insert(pos.end(), v, v + 3);
				surf.insert(surf.end(), {SURF_ASPHALT, SURF_ASPHALT});
				flags.insert(flags.end(), {COL_ALL, COL_ALL});
			}
		grid.add_chunk(1, pos.data(), surf.data(), flags.data(), (int)surf.size());
		return grid;
	}();
	return g;
}

static Vehicle settled(const VehicleParams &p, const Vec3 &at, real speed) {
	Vehicle v;
	v.configure(p);
	v.assists.gearbox = GEARBOX_AUTO;
	v.reset({at.x, p.cg_height + 0.05, at.z}, Quat(), speed);
	return v;
}

const char *pi_class_name(int c) {
	static const char *names[7] = {"D", "C", "B", "A", "S1", "S2", "X"};
	return names[c < 0 ? 0 : (c > 6 ? 6 : c)];
}

int pi_class_of(int pi) {
	if (pi <= 400) return 0;
	if (pi <= 580) return 1;
	if (pi <= 640) return 2;
	if (pi <= 720) return 3;
	if (pi <= 820) return 4;
	if (pi <= 920) return 5;
	return 6;
}

int pi_from_scores(real accel, real top, real grip, real brake) {
	real s = 0.34 * accel + 0.22 * top + 0.30 * grip + 0.14 * brake;
	s = std::pow(saturate(s), 0.9);
	return (int)clampr(std::round(100.0 + 899.0 * s), 100, 999);
}

BenchmarkResult run_benchmark(const VehicleParams &p) {
	const CollisionGrid &g = test_pad();
	BenchmarkResult r;
	r.weight_kg = p.mass;

	// Launch, 0-200, quarter mile, top speed.
	{
		Vehicle v = settled(p, {0, 0, 4100}, 0.0);
		for (int i = 0; i < 120; ++i) v.step(g, DT);
		Vec3 start = v.state.pos;
		real t = 0.0;
		real best_power = 0.0;
		for (int i = 0; i < 120 * 75; ++i) {
			v.input.throttle = 1.0;
			v.step(g, DT);
			t += DT;
			real kmh = v.state.forward_speed() * 3.6;
			if (r.t_0_100 > 98 && kmh >= 100.0) r.t_0_100 = t;
			if (r.t_0_200 > 98 && kmh >= 200.0) r.t_0_200 = t;
			if (r.quarter_mile > 98 && (v.state.pos - start).length() >= 402.3) r.quarter_mile = t;
			r.top_speed = std::max(r.top_speed, kmh);
			best_power = std::max(best_power, v.state.engine_torque_out * v.state.engine_rpm * TAU / 60.0);
			if (!std::isfinite(kmh)) break;
		}
		r.power_kw = best_power / 1000.0;
	}
	// Braking 100-0.
	{
		Vehicle v = settled(p, {-2000, 0, 2000}, 100.0 / 3.6);
		for (int i = 0; i < 60; ++i) {
			v.input.throttle = 0.35;
			v.step(g, DT);
		}
		v.state.vel = v.state.rot.forward() * (100.0 / 3.6);
		Vec3 start = v.state.pos;
		for (int i = 0; i < 120 * 15; ++i) {
			v.input.throttle = 0.0;
			v.input.brake = 1.0;
			v.step(g, DT);
			if (v.state.speed() < 0.3) break;
		}
		r.brake_100_0 = (v.state.pos - start).flat().length();
	}
	// Skidpad with a slow steering sweep.
	{
		Vehicle v = settled(p, {2000, 0, 0}, 16.0);
		real best = 0.0;
		for (int i = 0; i < 120 * 14; ++i) {
			real spd = v.state.forward_speed();
			v.input.throttle = clampr((17.0 - spd) * 0.3, 0.0, 1.0);
			v.input.brake = clampr((spd - 18.0) * 0.3, 0.0, 1.0);
			v.input.steer = lerpr(0.15, 1.0, clampr(i / (120.0 * 12.0), 0.0, 1.0));
			v.step(g, DT);
			if (i > 240) best = std::max(best, std::fabs(v.state.vel.flat().length() * v.state.ang_vel.y) / GRAVITY);
		}
		r.lateral_g = best;
	}
	real accel = saturate((14.0 - r.t_0_100) / 11.0);
	real top = saturate((r.top_speed - 150.0) / 200.0);
	real grip = saturate((r.lateral_g - 0.7) / 0.5);
	real brake = saturate((60.0 - r.brake_100_0) / 30.0);
	r.pi = pi_from_scores(accel, top, grip, brake);
	r.pi_class = pi_class_of(r.pi);
	r.accel_score = accel * 10.0;
	r.speed_score = top * 10.0;
	r.handling_score = grip * 10.0;
	r.braking_score = brake * 10.0;
	r.launch_score = saturate((8.0 - (r.t_0_100 < 98 ? r.t_0_100 : 20.0) * 0.5) / 6.5) * 10.0;
	return r;
}

} // namespace nt
