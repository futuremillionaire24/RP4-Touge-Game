#include "doctest.h"

#include "sim/benchmark.h"
#include "sim/collision_grid.h"
#include "sim/roster.h"
#include "sim/vehicle.h"

#include <cstdio>
#include <cstring>
#include <vector>

using namespace nt;

static const real DT = 1.0 / 120.0;

// Flat asphalt pad (half size in meters), split into 64 m tiles.
static void build_pad(CollisionGrid &g, real half = 1600.0, int surface = SURF_ASPHALT) {
	std::vector<float> pos;
	std::vector<uint8_t> surf, flags;
	const real tile = 64.0;
	for (real x = -half; x < half; x += tile) {
		for (real z = -half; z < half; z += tile) {
			float a[3] = {(float)x, 0.f, (float)z};
			float b[3] = {(float)x, 0.f, (float)(z + tile)};
			float c[3] = {(float)(x + tile), 0.f, (float)(z + tile)};
			float d[3] = {(float)(x + tile), 0.f, (float)z};
			// Counter-clockwise seen from above so normals point +Y.
			for (float *v : {a, b, c, a, c, d}) pos.insert(pos.end(), v, v + 3);
			surf.push_back((uint8_t)surface);
			surf.push_back((uint8_t)surface);
			flags.push_back(COL_ALL);
			flags.push_back(COL_ALL);
		}
	}
	g.add_chunk(1, pos.data(), surf.data(), flags.data(), (int)surf.size());
}

static Vehicle make(int id, const CollisionGrid &g) {
	Vehicle v;
	v.configure(make_car_params(id));
	v.reset({0, v.params.cg_height + 0.05, 1400}, Quat(), 0.0);
	// Settle on the springs.
	for (int i = 0; i < 240; ++i) v.step(g, DT);
	return v;
}

static bool finite_state(const Vehicle &v) {
	const VehicleState &s = v.state;
	return std::isfinite(s.pos.x) && std::isfinite(s.pos.y) && std::isfinite(s.pos.z) && std::isfinite(s.vel.x) &&
			std::isfinite(s.ang_vel.y) && std::isfinite(s.engine_rpm);
}

TEST_CASE("tire curve peaks at rho=1 and slides to the slide ratio") {
	CHECK(tire_curve(1.0, 0.78) == doctest::Approx(1.0).epsilon(1e-6));
	CHECK(tire_curve(0.0, 0.78) == doctest::Approx(0.0));
	CHECK(tire_curve(0.5, 0.78) < 1.0);
	CHECK(tire_curve(50.0, 0.78) == doctest::Approx(0.78).epsilon(0.02));
	// Monotonic falloff beyond the peak.
	real prev = 1.0;
	for (real r = 1.1; r < 10.0; r += 0.3) {
		real f = tire_curve(r, 0.78);
		CHECK(f <= prev + 1e-9);
		prev = f;
	}
}

TEST_CASE("collision grid raycast and sphere contacts") {
	CollisionGrid g;
	build_pad(g, 64.0);
	RayHit h = g.raycast({3, 5, 7}, {0, -1, 0}, 10.0, COL_DRIVABLE);
	REQUIRE(h.hit);
	CHECK(h.t == doctest::Approx(5.0));
	CHECK(h.normal.y == doctest::Approx(1.0));
	// Long diagonal ray crossing many cells.
	RayHit h2 = g.raycast({-60, 10, -60}, Vec3(1, -0.1, 1).normalized(), 500.0, COL_DRIVABLE);
	REQUIRE(h2.hit);
	CHECK(h2.point.y == doctest::Approx(0.0).epsilon(1e-6));
	SphereContact c[4];
	int n = g.sphere_contacts({0, 0.3, 0}, 0.5, COL_SOLID, c, 4);
	REQUIRE(n >= 1);
	CHECK(c[0].depth == doctest::Approx(0.2).epsilon(1e-6));
	g.remove_chunk(1);
	CHECK_FALSE(g.raycast({3, 5, 7}, {0, -1, 0}, 10.0, COL_DRIVABLE).hit);
}

TEST_CASE("every car settles at rest without creeping") {
	CollisionGrid g;
	build_pad(g);
	for (int id = 0; id < CAR_COUNT; ++id) {
		Vehicle v = make(id, g);
		Vec3 p0 = v.state.pos;
		for (int i = 0; i < 600; ++i) v.step(g, DT);
		INFO("car " << std::string(car_key(id)));
		REQUIRE(finite_state(v));
		CHECK((v.state.pos - p0).flat().length() < 0.05);
		CHECK(v.state.speed() < 0.05);
		CHECK(v.state.pos.y > 0.15);
		for (int w = 0; w < 4; ++w) CHECK(v.state.wheels[w].contact);
	}
}

struct Perf {
	real t100 = -1, top = 0, brake_dist = -1, lat_g = 0;
};

static Perf measure(int id) {
	CollisionGrid g;
	build_pad(g, 3000.0);
	Perf r;
	// Launch + top speed on a long straight heading -Z.
	Vehicle v = make(id, g);
	v.state.pos = {0, v.state.pos.y, 2900};
	real t = 0;
	for (int i = 0; i < 120 * 70; ++i) {
		v.input.throttle = 1.0;
		v.step(g, DT);
		t += DT;
		real kmh = v.state.forward_speed() * 3.6;
		if (r.t100 < 0 && kmh >= 100.0) r.t100 = t;
		r.top = std::max(r.top, kmh);
		if (!finite_state(v)) break;
	}
	// Braking from 100.
	Vehicle b = make(id, g);
	b.reset({0, b.params.cg_height + 0.05, 1000}, Quat(), 100.0 / 3.6);
	for (int i = 0; i < 60; ++i) b.step(g, DT);
	real sp = b.state.forward_speed();
	b.state.vel = b.state.rot.forward() * (100.0 / 3.6);
	(void)sp;
	Vec3 start = b.state.pos;
	for (int i = 0; i < 120 * 15; ++i) {
		b.input.throttle = 0.0;
		b.input.brake = 1.0;
		b.step(g, DT);
		if (b.state.speed() < 0.3) break;
	}
	r.brake_dist = (b.state.pos - start).flat().length();

	// Skidpad: hold ~16 m/s on a circle and read lateral acceleration.
	Vehicle c = make(id, g);
	c.reset({0, c.params.cg_height + 0.05, 0}, Quat(), 16.0);
	for (int i = 0; i < 20; ++i) c.step(g, DT);
	real max_lat = 0;
	for (int i = 0; i < 120 * 14; ++i) {
		real spd = c.state.forward_speed();
		c.input.throttle = clampr((17.0 - spd) * 0.3, 0.0, 1.0);
		c.input.brake = clampr((spd - 18.0) * 0.3, 0.0, 1.0);
		// Slow steering sweep finds the grip limit whichever balance the car has.
		c.input.steer = lerpr(0.15, 1.0, clampr(i / (120.0 * 12.0), 0.0, 1.0));
		c.step(g, DT);
		if (i > 120 * 2) {
			Vec3 v = c.state.vel;
			real omega = c.state.ang_vel.y;
			max_lat = std::max(max_lat, std::fabs(v.flat().length() * omega) / GRAVITY);
		}
	}
	r.lat_g = max_lat;
	return r;
}

TEST_CASE("roster performance envelope") {
	std::printf("\n%-16s %8s %8s %9s %7s\n", "car", "0-100s", "top", "100-0 m", "lat g");
	for (int id = 0; id < CAR_COUNT; ++id) {
		Perf p = measure(id);
		std::printf("%-16s %8.2f %8.1f %9.1f %7.2f\n", car_key(id), p.t100, p.top, p.brake_dist, p.lat_g);
		INFO("car " << std::string(car_key(id)));
		CHECK(p.t100 > 2.0);
		CHECK(p.t100 < 20.0);
		CHECK(p.top > 130.0);
		CHECK(p.top < 360.0);
		CHECK(p.brake_dist > 25.0);
		CHECK(p.brake_dist < 60.0);
		CHECK(p.lat_g > 0.6);
		CHECK(p.lat_g < 1.6);
	}
}

TEST_CASE("benchmark PI table") {
	std::printf("\nSTOCK_PI := {");
	for (int id = 0; id < CAR_COUNT; ++id) {
		BenchmarkResult r = run_benchmark(make_car_params(id));
		std::printf("\"%s\": %d, ", car_key(id), r.pi);
		CHECK(r.pi >= 100);
		CHECK(r.pi <= 999);
	}
	std::printf("}\n");
}

TEST_CASE("simulation is deterministic") {
	CollisionGrid g;
	build_pad(g);
	auto run = [&]() {
		Vehicle v = make(CAR_BMW_M3_E30, g);
		for (int i = 0; i < 120 * 20; ++i) {
			real t = i * DT;
			v.input.throttle = 0.5 + 0.5 * std::sin(t * 0.7);
			v.input.steer = std::sin(t * 1.3) * 0.6;
			v.input.brake = t > 12 && t < 13 ? 1.0 : 0.0;
			v.input.handbrake = t > 6 && t < 6.5 ? 1.0 : 0.0;
			v.step(g, DT);
		}
		const VehicleState &s = v.state;
		std::vector<real> out = {s.pos.x, s.pos.y, s.pos.z, s.rot.x, s.rot.y, s.rot.z, s.rot.w, s.vel.x, s.vel.y, s.vel.z,
			s.ang_vel.x, s.ang_vel.y, s.ang_vel.z, s.engine_rpm, s.boost, (real)s.gear};
		for (const WheelState &w : s.wheels) {
			out.push_back(w.omega);
			out.push_back(w.slip_angle);
			out.push_back(w.temp);
			out.push_back(w.compression);
		}
		return out;
	};
	auto a = run();
	auto b = run();
	REQUIRE(a.size() == b.size());
	for (size_t i = 0; i < a.size(); ++i) CHECK(a[i] == b[i]); // bit-exact, not approximate
}

TEST_CASE("handbrake flick breaks the rear loose on the drift car") {
	CollisionGrid g;
	build_pad(g);
	Vehicle v = make(CAR_BMW_M3_E30, g);
	v.assists.stm = false;
	v.assists.tcs = false;
	v.assists.countersteer = 0.0;
	v.reset({0, v.params.cg_height + 0.05, 0}, Quat(), 60.0 / 3.6);
	for (int i = 0; i < 30; ++i) v.step(g, DT);
	real max_angle = 0;
	for (int i = 0; i < 120 * 3; ++i) {
		real t = i * DT;
		v.input.steer = t < 1.2 ? -0.7 : 0.4;
		v.input.handbrake = t < 0.45 ? 1.0 : 0.0;
		v.input.throttle = t > 0.3 ? 0.8 : 0.0;
		v.step(g, DT);
		max_angle = std::max(max_angle, std::fabs(v.state.drift_angle));
	}
	CHECK(max_angle > 0.35); // > 20 degrees
	CHECK(finite_state(v));
}

TEST_CASE("rewind snapshot restores state exactly") {
	CollisionGrid g;
	build_pad(g);
	Vehicle v = make(CAR_AUDI_R8, g);
	v.input.throttle = 1.0;
	for (int i = 0; i < 300; ++i) v.step(g, DT);
	std::vector<uint8_t> snap;
	v.save_state(snap);
	Vec3 p = v.state.pos;
	for (int i = 0; i < 300; ++i) v.step(g, DT);
	size_t off = 0;
	REQUIRE(v.load_state(snap.data(), snap.size(), off));
	CHECK(v.state.pos.z == p.z);
}

TEST_CASE("override ops stack and engine swaps transplant the engine") {
	VehicleParams p = make_car_params(CAR_ABARTH_500);
	real m0 = p.mass;
	CHECK(apply_override(p, "*mass", 0.9));
	CHECK(p.mass == doctest::Approx(m0 * 0.9));
	CHECK(apply_override(p, "+lift_rear", 0.5));
	CHECK_FALSE(apply_override(p, "*torque_scale", 2.0));
	CHECK_FALSE(apply_override(p, "no_such_key", 1.0));
	VehicleParams titan = make_car_params(CAR_BMW_M4);
	VehicleParams s = make_car_params(CAR_ABARTH_500);
	real mass_before = s.mass;
	CHECK(apply_override(s, "engine_swap", (real)CAR_BMW_M4));
	CHECK(s.cylinders == titan.cylinders);
	CHECK(s.redline_rpm == titan.redline_rpm);
	CHECK(s.mass > mass_before); // 3 -> 6 cylinders adds weight
	BenchmarkResult stock = run_benchmark(make_car_params(CAR_ABARTH_500));
	BenchmarkResult swapped = run_benchmark(s);
	MESSAGE("mame stock PI " << stock.pi << " swapped PI " << swapped.pi);
	CHECK(swapped.pi > stock.pi + 60);
	auto dump = dump_params(s);
	CHECK(dump.size() > 50);
}
