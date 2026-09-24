#include "world_sim.h"

#include <algorithm>
#include <cstring>

namespace nt {

int WorldSim::add_car(const VehicleParams &p, bool ai_controlled, uint64_t seed) {
	cars.emplace_back();
	Vehicle &v = cars.back();
	v.configure(p);
	v.state.wetness = wetness;
	v.state.ambient_temp = ambient_temp;
	ai.emplace_back();
	is_ai.push_back(ai_controlled ? 1 : 0);
	progress.emplace_back();
	int id = (int)cars.size() - 1;
	ai[id].init(has_line ? &line : nullptr, v, seed ^ (uint64_t)(id * 0x9E37));
	if (ai_controlled) {
		v.assists.abs = true;
		v.assists.tcs = true;
		v.assists.stm = true; // pro drivers catch split-grip braking moments
		v.assists.steering = STEER_SIMULATION;
		v.assists.countersteer = 0.0;
		v.assists.gearbox = GEARBOX_AUTO;
	}
	return id;
}

void WorldSim::remove_all_cars() {
	cars.clear();
	ai.clear();
	is_ai.clear();
	progress.clear();
	ring_.clear();
}

void WorldSim::truncate_cars(int count) {
	if (count < 0 || count >= (int)cars.size()) return;
	cars.resize(count);
	ai.resize(count);
	is_ai.resize(count);
	progress.resize(count);
	ring_.clear(); // snapshots no longer match the car count
}

void WorldSim::set_line(const std::vector<TrackSample> &samples, bool closed) {
	// Margin keeps a car body (half width ~0.9 m) plus tracking error on the asphalt.
	line.build(samples, closed, 1.35);
	has_line = line.size() > 3;
	for (size_t i = 0; i < cars.size(); ++i) {
		ai[i].set_line(has_line ? &line : nullptr, cars[i]);
		reset_progress((int)i);
	}
}

void WorldSim::reset_progress(int i) {
	RaceProgress &p = progress[i];
	p = RaceProgress();
	if (!has_line) return;
	p.line_index = line.nearest(cars[i].state.pos, -1);
	p.line_distance = line.progress(cars[i].state.pos, p.line_index);
	// Grid slots behind the start line count as the previous lap.
	if (line.closed() && p.line_distance > line.length() * 0.5) p.lap = -1;
	p.total = p.lap * line.length() + p.line_distance;
}

void WorldSim::update_progress(int i) {
	if (!has_line) return;
	RaceProgress &p = progress[i];
	const Vehicle &v = cars[i];
	int prev_index = p.line_index;
	real prev_dist = p.line_distance;
	p.line_index = line.nearest(v.state.pos, p.line_index, 15);
	real d = line.progress(v.state.pos, p.line_index);
	if (line.closed()) {
		real L = line.length();
		if (prev_dist > L * 0.75 && d < L * 0.25) p.lap++;
		else if (prev_dist < L * 0.25 && d > L * 0.75) p.lap--;
	}
	p.line_distance = d;
	p.total = p.lap * line.length() + d;
	Vec3 r = line.right_vector(p.line_index);
	p.line_offset = (v.state.pos - line.sample(p.line_index).center).dot(r);
	int nx = line.wrap(p.line_index + 1);
	Vec3 dir = (line.point(nx) - line.point(p.line_index)).normalized();
	bool wrong = v.state.vel.dot(dir) < -3.0;
	p.wrong_way_time = wrong ? p.wrong_way_time + 1.0 / 120.0 : 0.0;
	p.wrong_way = p.wrong_way_time > 1.5;
	(void)prev_index;
}

void WorldSim::pre_step() {
	int n = (int)cars.size();
	snaps_.resize(n);
	for (int i = 0; i < n; ++i) {
		const Vehicle &v = cars[i];
		CarSnapshot &s = snaps_[i];
		s.pos = v.state.pos;
		s.vel = v.state.vel;
		s.fwd = v.state.rot.forward();
		s.half_length = v.params.half_extents.z;
		s.half_width = v.params.half_extents.x;
		s.line_index = progress[i].line_index;
		s.line_offset = progress[i].line_offset;
		s.race_distance = progress[i].total;
		s.active = !v.frozen;
		cars[i].state.wetness = wetness;
		cars[i].state.ambient_temp = ambient_temp;
	}
	// Slipstream: a car directly ahead within 25 m cuts drag.
	for (int i = 0; i < n; ++i) {
		real best = 0.0;
		Vec3 fwd = snaps_[i].fwd;
		real speed = cars[i].state.speed();
		if (speed > 15.0) {
			for (int k = 0; k < n; ++k) {
				if (k == i || !snaps_[k].active) continue;
				Vec3 rel = snaps_[k].pos - snaps_[i].pos;
				real ahead = rel.dot(fwd);
				if (ahead < 3.0 || ahead > 25.0) continue;
				real side = (rel - fwd * ahead).length();
				if (side > 1.6) continue;
				real s = (1.0 - (ahead - 3.0) / 22.0) * (1.0 - side / 1.6);
				best = std::max(best, s);
			}
		}
		cars[i].state.slipstream = best;
	}
}

void WorldSim::post_step(real dt) {
	int n = (int)cars.size();
	// Car-car contacts, fixed order for determinism.
	for (int i = 0; i < n; ++i) {
		if (cars[i].frozen) continue;
		for (int k = i + 1; k < n; ++k) {
			if (cars[k].frozen) continue;
			resolve_vehicle_pair(cars[i], i, cars[k], k);
		}
	}
	time_s += dt;
	if (traffic_enabled && traffic.world && n > 0) {
		std::vector<TrafficSystem::Obstacle> obstacles;
		obstacles.reserve(n);
		for (int i = 0; i < n; ++i)
			if (!cars[i].frozen) obstacles.push_back({cars[i].state.pos, cars[i].state.vel, cars[i].params.half_extents.z});
		traffic.step(dt, cars[0].state.pos, time_s, obstacles);
		for (int i = 0; i < n; ++i) {
			Vehicle &v = cars[i];
			if (v.frozen) continue;
			Vec3 pos = v.state.pos, vel = v.state.vel, imp, pt;
			if (traffic.collide(pos, vel, v.params.mass, v.params.half_extents.x + 0.25, imp, pt)) {
				v.state.pos = pos;
				v.apply_impulse(imp, pt);
				real j = imp.length();
				if (j > 250.0) {
					CollisionEvent ev;
					ev.point = pt;
					ev.normal = imp / j;
					ev.impulse = j;
					ev.surface = SURF_METAL;
					ev.other_vehicle = -2; // traffic
					v.add_collision_event(ev);
					v.add_dent(pt, j);
				}
			}
		}
		NearMiss nm[4];
		int k = traffic.near_misses(cars[0].state.pos, cars[0].state.vel, cars[0].state.rot.forward(), nm, 4);
		for (int q = 0; q < k; ++q)
			if (near_miss_queue.size() < 32) near_miss_queue.push_back(nm[q]);
	}
	for (int i = 0; i < n; ++i) update_progress(i);
	// AI recovery: respawn on the line behind a fade (the game layer reads respawn_count).
	for (int i = 0; i < n; ++i) {
		if (!is_ai[i] || !ai[i].needs_respawn()) continue;
		int reason = std::clamp(ai[i].respawn_reason(), 0, 4);
		Vec3 pos;
		Quat rot;
		real speed = 0.0;
		ai[i].respawn_pose(pos, rot, speed);
		// Drop onto the real surface (banking / cuttings make the line height approximate).
		RayHit ground = grid.raycast(pos + Vec3(0, 3.0, 0), Vec3(0, -1, 0), 10.0, COL_DRIVABLE);
		if (ground.hit) pos.y = ground.point.y + cars[i].params.cg_height + 0.12;
		int lap = progress[i].lap;
		cars[i].reset(pos, rot, speed);
		ai[i].clear_respawn();
		update_progress(i);
		progress[i].lap = lap;
		progress[i].total = lap * line.length() + progress[i].line_distance;
		progress[i].respawn_count++;
		progress[i].respawn_reasons[reason]++;
	}
	tick++;
	if (rewind_enabled && tick % rewind_stride == 0) {
		ring_.push_back(snapshot());
		while ((int)ring_.size() > rewind_capacity) ring_.pop_front();
	}
	(void)dt;
}

void WorldSim::step(real dt, const ParallelFor &pf) {
	pre_step();
	pf((int)cars.size(), [&](int i) {
		Vehicle &v = cars[i];
		if (v.frozen) return;
		if (is_ai[i] && has_line) v.input = ai[i].drive(v, snaps_, i, dt);
		ai[i].wetness = wetness;
		v.step(grid, dt);
	});
	post_step(dt);
}

void WorldSim::step(real dt) {
	step(dt, [](int count, const std::function<void(int)> &body) {
		for (int i = 0; i < count; ++i) body(i);
	});
}

std::vector<uint8_t> WorldSim::snapshot() const {
	std::vector<uint8_t> out;
	uint32_t n = (uint32_t)cars.size();
	out.resize(sizeof(uint32_t) + sizeof(uint64_t));
	std::memcpy(out.data(), &n, sizeof(n));
	std::memcpy(out.data() + sizeof(n), &tick, sizeof(tick));
	for (uint32_t i = 0; i < n; ++i) {
		cars[i].save_state(out);
		AIDriver::Memory m = ai[i].memory();
		size_t off = out.size();
		out.resize(off + sizeof(m) + sizeof(RaceProgress));
		std::memcpy(out.data() + off, &m, sizeof(m));
		std::memcpy(out.data() + off + sizeof(m), &progress[i], sizeof(RaceProgress));
	}
	return out;
}

bool WorldSim::restore(const std::vector<uint8_t> &data) {
	if (data.size() < sizeof(uint32_t) + sizeof(uint64_t)) return false;
	uint32_t n;
	std::memcpy(&n, data.data(), sizeof(n));
	if (n != cars.size()) return false;
	std::memcpy(&tick, data.data() + sizeof(n), sizeof(tick));
	size_t off = sizeof(uint32_t) + sizeof(uint64_t);
	for (uint32_t i = 0; i < n; ++i) {
		if (!cars[i].load_state(data.data(), data.size(), off)) return false;
		AIDriver::Memory m;
		if (off + sizeof(m) + sizeof(RaceProgress) > data.size()) return false;
		std::memcpy(&m, data.data() + off, sizeof(m));
		ai[i].restore(m);
		std::memcpy(&progress[i], data.data() + off + sizeof(m), sizeof(RaceProgress));
		off += sizeof(m) + sizeof(RaceProgress);
	}
	return true;
}

real WorldSim::rewind(real seconds, real dt) {
	if (ring_.empty()) return 0.0;
	int steps = std::max(1, (int)std::round(seconds / (rewind_stride * dt)));
	steps = std::min(steps, (int)ring_.size());
	for (int i = 0; i < steps - 1; ++i) ring_.pop_back();
	restore(ring_.back());
	return steps * rewind_stride * dt;
}

std::vector<int> WorldSim::standings() const {
	std::vector<int> order(cars.size());
	for (size_t i = 0; i < order.size(); ++i) order[i] = (int)i;
	std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return progress[a].total > progress[b].total; });
	return order;
}

} // namespace nt
