#include "traffic.h"

#include <algorithm>

namespace nt {

static bool traffic_kind(RoadKind k) {
	return k == RK_STREET || k == RK_AVENUE || k == RK_EXPRESSWAY || k == RK_RURAL || k == RK_COAST || k == RK_DOCK;
}

void TrafficSystem::init(const World *w, int max_cars, uint64_t seed) {
	world = w;
	rng_.reseed(seed);
	cars.assign(max_cars, TrafficCar());
	spawnable_.clear();
	if (!world) return;
	for (int i = 0; i < (int)world->roads.size(); ++i)
		if (traffic_kind(world->roads[i].def.kind)) spawnable_.push_back(i);
}

bool TrafficSystem::ns_green(real t, int junction_index) {
	real phase = std::fmod(t + junction_index * 3.7, 30.0);
	return phase < 13.0; // 0-13 N-S green, 13-15 amber/all-red, 15-28 E-W green, 28-30 all red
}

static int lanes_per_dir(const RoadSample &s) { return std::max(1, (int)s.lanes / 2); }

void TrafficSystem::place(TrafficCar &c) {
	const Road &r = world->roads[c.road];
	const auto &smp = r.samples;
	int n = (int)smp.size();
	// Binary search the sample by arc length.
	int lo = 0, hi = n - 1;
	while (hi - lo > 1) {
		int mid = (lo + hi) / 2;
		if (smp[mid].rs.distance <= c.s) lo = mid;
		else hi = mid;
	}
	real seg = std::max(smp[hi].rs.distance - smp[lo].rs.distance, 1e-6);
	real t = clampr((c.s - smp[lo].rs.distance) / seg, 0.0, 1.0);
	Vec3 center = lerp(smp[lo].rs.center, smp[hi].rs.center, t);
	Vec3 tangent = lerp(smp[lo].rs.tangent, smp[hi].rs.tangent, t).normalized() * (real)c.dir;
	Vec3 up = lerp(smp[lo].rs.up, smp[hi].rs.up, t).normalized();
	Vec3 right = tangent.cross(up).normalized();
	c.pos = center + right * c.lane + up * (c.half.y + 0.02);
	c.rot = quat_look(tangent, up);
}

void TrafficSystem::spawn_one(const Vec3 &focus) {
	if (spawnable_.empty()) return;
	for (int attempt = 0; attempt < 24; ++attempt) {
		int ri = spawnable_[rng_.irange(0, (int)spawnable_.size() - 1)];
		const Road &r = world->roads[ri];
		// Quick reject by bounds.
		real reach = spawn_max + 50.0;
		if (focus.x < r.bmin.x - reach || focus.x > r.bmax.x + reach || focus.z < r.bmin.z - reach || focus.z > r.bmax.z + reach) continue;
		int si = rng_.irange(0, (int)r.samples.size() - 1);
		const RoadSampleX &sx = r.samples[si];
		if (sx.type == ST_TUNNEL && rng_.chance(0.5)) continue;
		real d = distance(sx.rs.center.flat(), focus.flat());
		if (d < spawn_min || d > spawn_max) continue;
		TrafficCar c;
		c.road = ri;
		c.s = sx.rs.distance;
		c.dir = rng_.chance(0.5) ? 1 : -1;
		int lpd = lanes_per_dir(sx.rs);
		real w = std::min(sx.rs.width_left, sx.rs.width_right);
		real lane_w = w / lpd;
		int k = rng_.irange(0, lpd - 1);
		// Japan drives on the left: travel lanes are left of the travel direction.
		c.lane = -(k + 0.5) * lane_w;
		real r_model = rng_.next();
		c.model = r_model < 0.28 ? TM_KEI : r_model < 0.58 ? TM_SEDAN : r_model < 0.72 ? TM_TAXI : r_model < 0.86 ? TM_VAN : r_model < 0.96 ? TM_TRUCK : TM_BUS;
		if (r.def.kind == RK_DOCK && rng_.chance(0.6)) c.model = TM_TRUCK;
		switch (c.model) {
			case TM_KEI: c.half = {0.74, 0.8, 1.7}; break;
			case TM_VAN: c.half = {0.85, 0.98, 2.35}; break;
			case TM_TRUCK: c.half = {1.05, 1.4, 3.8}; break;
			case TM_BUS: c.half = {1.25, 1.5, 5.5}; break;
			default: c.half = {0.86, 0.72, 2.3}; break;
		}
		real limit = r.def.speed_limit / 3.6;
		c.desired = limit * rng_.range(0.9, 1.25) * (c.model == TM_TRUCK || c.model == TM_BUS ? 0.85 : 1.0);
		c.speed = c.desired * 0.8;
		c.color = (float)rng_.next();
		c.active = true;
		place(c);
		// Don't spawn on top of another car.
		bool clash = false;
		for (const TrafficCar &o : cars)
			if (o.active && (o.pos - c.pos).length_sq() < 100.0) clash = true;
		if (clash) continue;
		for (TrafficCar &slot : cars) {
			if (!slot.active) {
				slot = c;
				return;
			}
		}
		return;
	}
}

bool TrafficSystem::pick_next_road(TrafficCar &c) {
	const Road &r = world->roads[c.road];
	Vec3 end = c.dir > 0 ? r.samples.back().rs.center : r.samples.front().rs.center;
	int candidates[16];
	bool at_start[16];
	int count = 0;
	for (int ri : spawnable_) {
		if (ri == c.road) continue;
		const Road &o = world->roads[ri];
		real ds = distance(o.samples.front().rs.center, end), de = distance(o.samples.back().rs.center, end);
		if (ds < 24.0 && count < 16) {
			candidates[count] = ri;
			at_start[count++] = true;
		} else if (de < 24.0 && count < 16) {
			candidates[count] = ri;
			at_start[count++] = false;
		}
	}
	if (count == 0) return false;
	int k = rng_.irange(0, count - 1);
	c.road = candidates[k];
	const Road &n = world->roads[c.road];
	c.dir = at_start[k] ? 1 : -1;
	c.s = at_start[k] ? 0.0 : n.length;
	int lpd = lanes_per_dir(n.samples[at_start[k] ? 0 : n.samples.size() - 1].rs);
	real w = std::min(n.samples.front().rs.width_left, n.samples.front().rs.width_right);
	c.lane = -0.5 * (w / lpd) - (lpd > 1 && c.lane < -(w / lpd) ? w / lpd : 0.0);
	c.desired = n.def.speed_limit / 3.6 * rng_.range(0.9, 1.25);
	return true;
}

real TrafficSystem::gap_ahead(int idx, real &leader_speed, const std::vector<Obstacle> &obstacles) const {
	const TrafficCar &c = cars[idx];
	Vec3 fwd = c.rot.forward();
	real best = 1e9;
	leader_speed = c.desired;
	for (const Obstacle &o : obstacles) {
		Vec3 d = o.pos - c.pos;
		real ahead = d.dot(fwd);
		if (ahead <= 0.0 || ahead > 80.0) continue;
		real side = (d - fwd * ahead).flat().length();
		if (side > 2.2) continue; // a little wider than a lane: give the player room
		real gap = ahead - c.half.z - o.half_length;
		if (gap < best) {
			best = gap;
			leader_speed = std::max(0.0, o.vel.dot(fwd));
		}
	}
	for (int k = 0; k < (int)cars.size(); ++k) {
		if (k == idx || !cars[k].active) continue;
		const TrafficCar &o = cars[k];
		Vec3 d = o.pos - c.pos;
		real ahead = d.dot(fwd);
		if (ahead <= 0.0 || ahead > 80.0) continue;
		real side = (d - fwd * ahead).length();
		if (side > 1.6) continue;
		real gap = ahead - c.half.z - o.half.z;
		if (gap < best) {
			best = gap;
			leader_speed = o.loose ? 0.0 : o.speed;
		}
	}
	return best;
}

// Distance to the stop line if the light ahead is red (city grid only), else 1e9.
real TrafficSystem::signal_stop_distance(const TrafficCar &c, real time_s) const {
	const Road &r = world->roads[c.road];
	if (r.def.kind != RK_STREET && r.def.kind != RK_AVENUE) return 1e9;
	real to_end = c.dir > 0 ? r.length - c.s : c.s;
	if (to_end > 35.0) return 1e9;
	Vec3 end = c.dir > 0 ? r.samples.back().rs.center : r.samples.front().rs.center;
	// Find the junction this road ends at.
	int best = -1;
	real best_d = 30.0;
	for (int j = 0; j < (int)world->junctions.size(); ++j) {
		const Intersection &it = world->junctions[j];
		if (it.style != 1 && it.style != 2) continue;
		real d = distance(it.center.flat(), end.flat());
		if (d < best_d) {
			best_d = d;
			best = j;
		}
	}
	if (best < 0) return 1e9;
	Vec3 t = r.samples.front().rs.tangent;
	bool ns_road = std::fabs(t.z) > std::fabs(t.x);
	bool green = ns_green(time_s, best) == ns_road;
	// Amber / all-red windows count as red.
	real phase = std::fmod(time_s + best * 3.7, 30.0);
	bool clearing = (phase >= 13.0 && phase < 15.0) || phase >= 28.0;
	if (green && !clearing) return 1e9;
	return std::max(0.0, to_end - 3.0);
}

void TrafficSystem::step(real dt, const Vec3 &focus, real time_s, const std::vector<Obstacle> &obstacles) {
	if (!world) return;
	int active = 0;
	for (TrafficCar &c : cars) {
		if (!c.active) continue;
		if (distance(c.pos.flat(), focus.flat()) > despawn || (c.loose && c.loose_time > 12.0)) {
			c.active = false;
			continue;
		}
		active++;
	}
	int want = (int)(target_count * density);
	for (int k = 0; k < 3 && active < want; ++k, ++active) spawn_one(focus);

	for (int i = 0; i < (int)cars.size(); ++i) {
		TrafficCar &c = cars[i];
		if (!c.active) continue;
		if (c.loose) {
			// Knocked car: slides to a stop with tyre friction, spinning down.
			c.loose_time += dt;
			real sp = c.vel.flat().length();
			if (sp > 0.01) c.vel -= c.vel.flat() / sp * std::min(sp, 7.0 * dt);
			c.yaw_rate *= std::exp(-1.5 * dt);
			c.pos += c.vel.flat() * dt;
			c.rot = Quat::from_axis_angle({0, 1, 0}, c.yaw_rate * dt) * c.rot;
			c.rot = c.rot.normalized();
			real gy = world->height(c.pos.x, c.pos.z);
			NearestRoad nr = world->nearest_road(c.pos, 8.0);
			if (nr.road >= 0) gy = world->roads[nr.road].samples[nr.sample].rs.center.y;
			c.pos.y = gy + c.half.y + 0.02;
			continue;
		}
		// IDM car following + red lights.
		real leader_v;
		real gap = gap_ahead(i, leader_v, obstacles);
		real stop = signal_stop_distance(c, time_s);
		if (stop < gap) {
			gap = stop;
			leader_v = 0.0;
		}
		const real a_max = 1.6, b = 2.4, s0 = 3.0, T = 1.4;
		real dv = c.speed - leader_v;
		real s_star = s0 + c.speed * T + c.speed * dv / (2.0 * std::sqrt(a_max * b));
		real acc = a_max * (1.0 - std::pow(c.speed / std::max(c.desired, 0.1), 4.0) - (gap < 1e8 ? sqr(std::max(s_star, 0.0) / std::max(gap, 0.3)) : 0.0));
		acc = clampr(acc, -8.0, a_max);
		c.speed = std::max(0.0, c.speed + acc * dt);
		c.s += c.speed * dt * c.dir;
		const Road &r = world->roads[c.road];
		if (c.s > r.length || c.s < 0.0) {
			if (!pick_next_road(c)) {
				c.active = false;
				continue;
			}
		}
		place(c);
		if (c.near_miss_cooldown > 0) c.near_miss_cooldown--;
	}
}

bool TrafficSystem::collide(Vec3 &car_pos, Vec3 &car_vel, real car_mass, real car_radius, Vec3 &impulse_out, Vec3 &point_out) {
	bool hit = false;
	impulse_out = Vec3();
	for (TrafficCar &c : cars) {
		if (!c.active) continue;
		Vec3 d = car_pos - c.pos;
		if (d.flat().length_sq() > sqr(c.half.z + car_radius + 3.0)) continue;
		// Traffic body as three spheres along its length.
		Vec3 fwd = c.rot.forward();
		for (real k : {-0.66, 0.0, 0.66}) {
			Vec3 sc = c.pos + fwd * (k * (c.half.z - c.half.x));
			Vec3 dd = (car_pos - sc).flat();
			real rr = c.half.x + 0.15 + car_radius;
			real dist = dd.length();
			if (dist >= rr || dist < 1e-6) continue;
			Vec3 n = dd / dist;
			Vec3 tv = c.loose ? c.vel : fwd * c.speed;
			real vn = (car_vel - tv).dot(n);
			// Separate.
			car_pos += n * (rr - dist) * 0.6;
			if (vn < 0.0) {
				const real m_t = c.model == TM_TRUCK || c.model == TM_BUS ? 6000.0 : 1200.0;
				real j = -(1.1) * vn / (1.0 / car_mass + 1.0 / m_t);
				car_vel += n * (j / car_mass);
				impulse_out += n * j;
				// Contact at the struck car's CG height: bumper-to-bumper hits shouldn't roll it.
				point_out = sc + n * (c.half.x + 0.15);
				point_out.y = car_pos.y;
				if (!c.loose) {
					c.loose = true;
					c.vel = fwd * c.speed;
					c.loose_time = 0.0;
				}
				c.vel -= n * (j / m_t);
				c.yaw_rate += clampr(j / m_t * 0.8 * (k == 0.0 ? 0.3 : signr(k)), -3.0, 3.0);
				hit = true;
			}
		}
	}
	return hit;
}

int TrafficSystem::near_misses(const Vec3 &pos, const Vec3 &vel, const Vec3 &fwd, NearMiss *out, int max_out) {
	int n = 0;
	real speed = vel.length();
	if (speed < 12.0) return 0;
	for (int i = 0; i < (int)cars.size() && n < max_out; ++i) {
		TrafficCar &c = cars[i];
		if (!c.active || c.loose || c.near_miss_cooldown > 0) continue;
		Vec3 d = c.pos - pos;
		if (d.flat().length_sq() > 64.0) continue;
		real along = d.dot(fwd);
		if (std::fabs(along) > 1.0) continue; // alongside right now
		real side = std::fabs((d - fwd * along).flat().length());
		real clearance = side - c.half.x - 0.9;
		Vec3 tv = c.rot.forward() * c.speed;
		real rel = (vel - tv).length();
		if (clearance > 0.05 && clearance < 1.6 && rel > 11.0) {
			out[n].traffic = i;
			out[n].clearance = clearance;
			out[n].rel_speed = rel;
			n++;
			c.near_miss_cooldown = 240;
		}
	}
	return n;
}

} // namespace nt
