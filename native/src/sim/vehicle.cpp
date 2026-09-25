#include "vehicle.h"

#include "rng.h"

#include <cstring>

namespace nt {

static constexpr int CHASSIS_SUBSTEPS = 2; // 120 Hz tick -> 240 Hz chassis
static constexpr real MIN_SLIP_SPEED = 1.5;

TireSpec TireSpec::compound(TireCompound c) {
	TireSpec t;
	switch (c) {
		case TIRE_STREET:
			t.grip = 1.02; t.slide_ratio = 0.86; t.peak_slip_ratio = 0.12; t.peak_slip_angle = 0.16;
			t.opt_temp = 70; t.temp_window = 45; t.heat_rate = 0.9; t.wet_bonus = 0.04; t.rolling = 1.0;
			break;
		case TIRE_SPORT:
			t.grip = 1.14; t.slide_ratio = 0.85; t.peak_slip_ratio = 0.11; t.peak_slip_angle = 0.14;
			t.opt_temp = 82; t.temp_window = 38; t.heat_rate = 1.0; t.rolling = 1.0;
			break;
		case TIRE_SEMI_SLICK:
			t.grip = 1.25; t.slide_ratio = 0.82; t.peak_slip_ratio = 0.10; t.peak_slip_angle = 0.12;
			t.opt_temp = 92; t.temp_window = 28; t.heat_rate = 1.15; t.wet_bonus = -0.10; t.rolling = 0.95;
			break;
		case TIRE_DRIFT:
			t.grip = 1.05; t.slide_ratio = 0.92; t.peak_slip_ratio = 0.14; t.peak_slip_angle = 0.18;
			t.opt_temp = 95; t.temp_window = 45; t.heat_rate = 1.3; t.rolling = 1.0;
			break;
		case TIRE_RALLY:
			t.grip = 0.98; t.slide_ratio = 0.88; t.peak_slip_ratio = 0.15; t.peak_slip_angle = 0.20;
			t.opt_temp = 70; t.temp_window = 50; t.heat_rate = 0.85; t.loose_bonus = 0.28; t.wet_bonus = 0.06; t.rolling = 1.1;
			break;
		case TIRE_SNOW:
			t.grip = 0.92; t.slide_ratio = 0.88; t.peak_slip_ratio = 0.16; t.peak_slip_angle = 0.20;
			t.opt_temp = 40; t.temp_window = 60; t.heat_rate = 0.7; t.loose_bonus = 0.12; t.snow_bonus = 0.75; t.wet_bonus = 0.10; t.rolling = 1.15;
			break;
		default:
			break;
	}
	return t;
}

real tire_curve(real rho, real slide_ratio) {
	real s = clampr(slide_ratio, 0.3, 0.98);
	real C = 2.0 * (PI - std::asin(s)) / PI;
	real B = std::tan(PI / (2.0 * C));
	return std::sin(C * std::atan(B * rho));
}

void Vehicle::configure(const VehicleParams &p) {
	params = p;
	const Vec3 &h = params.half_extents;
	real m = params.mass;
	// Box inertia with a concentration factor (engines/passengers sit near the middle).
	real lx = h.x * 2.0, ly = h.y * 2.0, lz = h.z * 2.0;
	real k = 0.85 * params.inertia_scale;
	derived.inertia = Vec3(m / 12.0 * (ly * ly + lz * lz) * k, m / 12.0 * (lx * lx + lz * lz) * k, m / 12.0 * (lx * lx + ly * ly) * k);
	derived.inv_inertia = Vec3(1.0 / derived.inertia.x, 1.0 / derived.inertia.y, 1.0 / derived.inertia.z);

	real a = params.wheelbase * (1.0 - params.weight_front); // CG -> front axle
	real b = params.wheelbase * params.weight_front; // CG -> rear axle
	derived.axle_front_z = -a;
	derived.axle_rear_z = b;
	real wf = m * GRAVITY * params.weight_front * 0.5;
	real wr = m * GRAVITY * (1.0 - params.weight_front) * 0.5;
	// Strut tops sit where the static spring compression holds the CG at cg_height (+ ride
	// height tweak from mount_height, 0.05 = stock).
	real ride = params.mount_height - 0.05;
	real mh_f = params.rest_length_front + params.wheel_radius_front - wf / params.spring_front - params.cg_height - ride;
	real mh_r = params.rest_length_rear + params.wheel_radius_rear - wr / params.spring_rear - params.cg_height - ride;
	derived.mounts[FL] = Vec3(-params.track_front * 0.5, mh_f, -a);
	derived.mounts[FR] = Vec3(params.track_front * 0.5, mh_f, -a);
	derived.mounts[RL] = Vec3(-params.track_rear * 0.5, mh_r, b);
	derived.mounts[RR] = Vec3(params.track_rear * 0.5, mh_r, b);
	derived.static_load[FL] = derived.static_load[FR] = wf;
	derived.static_load[RL] = derived.static_load[RR] = wr;

	switch (params.layout) {
		case DRIVE_FF: derived.driven_mask = (1 << FL) | (1 << FR); break;
		case DRIVE_AWD: derived.driven_mask = 0xF; break;
		default: derived.driven_mask = (1 << RL) | (1 << RR); break;
	}
	real peak = params.torque_curve.max_y();
	derived.max_torque = peak * (1.0 + params.max_boost * params.boost_gain) + params.hybrid_boost_nm;
}

void Vehicle::reset(const Vec3 &pos, const Quat &rot, real speed) {
	VehicleState s;
	s.pos = pos;
	s.rot = rot.normalized();
	s.vel = s.rot.forward() * speed;
	s.ang_vel = Vec3();
	for (int i = 0; i < 4; ++i) {
		WheelState &w = s.wheels[i];
		real R = i < 2 ? params.wheel_radius_front : params.wheel_radius_rear;
		w.omega = speed / R;
		w.compression = derived.static_load[i] / (i < 2 ? params.spring_front : params.spring_rear);
		// Tires start near the bottom of their window (warmed on the way to the event).
		const TireSpec &ts = i < 2 ? params.tire_front : params.tire_rear;
		w.temp = std::max(s.ambient_temp + 10.0, ts.opt_temp - ts.temp_window * 0.5);
	}
	s.gear = speed > 1.0 ? 1 : 1;
	s.pending_gear = s.gear;
	s.engine_rpm = params.idle_rpm;
	s.wetness = state.wetness;
	s.ambient_temp = state.ambient_temp;
	if (speed > 1.0) {
		// Pick the gear that puts rpm in the power band.
		for (int g = 1; g <= params.gear_count; ++g) {
			real rpm = speed / params.wheel_radius_rear * gear_ratio(g) * params.final_drive * 60.0 / TAU;
			s.gear = g;
			if (rpm < params.redline_rpm * 0.8) break;
		}
		s.pending_gear = s.gear;
		s.engine_rpm = std::max(params.idle_rpm, speed / params.wheel_radius_rear * gear_ratio(s.gear) * params.final_drive * 60.0 / TAU);
	}
	state = s;
	input = VehicleInput();
}

real Vehicle::gear_ratio(int gear) const {
	if (gear < 0) return -params.reverse_ratio;
	if (gear == 0) return 0.0;
	int g = std::min(gear, std::min(params.gear_count, 10));
	return params.gear_ratios[g - 1];
}

real Vehicle::engine_torque_at(real rpm, real throttle, real boost) const {
	real base = params.torque_curve.eval(rpm);
	real boosted = base * (1.0 + boost * params.boost_gain);
	if (params.hybrid_boost_nm > 0.0) {
		if (params.hybrid_power_kw > 0.0) {
			// E-motors: full torque low down, then their rated power all the way up the rev range.
			real w = std::max(rpm, 500.0) * TAU / 60.0;
			boosted += std::min(params.hybrid_boost_nm, params.hybrid_power_kw * 1000.0 / w);
		} else {
			// Electric motor fills the bottom end, fading out by 5000 rpm.
			boosted += params.hybrid_boost_nm * (1.0 - smoothstep(1500.0, 5000.0, rpm));
		}
	}
	real power_loss = 1.0;
	if (assists.mechanical_damage) power_loss = 1.0 - 0.35 * saturate(state.damage.front);
	real drive = boosted * throttle * power_loss;
	// Closed-throttle engine braking + internal friction grow with rpm.
	real drag = params.friction_torque * (0.3 + 0.7 * rpm / params.redline_rpm);
	real brake = params.engine_brake * rpm * (1.0 - throttle);
	if (params.engine_kind == ENGINE_DIESEL) brake *= 1.25;
	if (params.engine_kind == ENGINE_ROTARY) brake *= 0.7;
	return drive - drag - brake;
}

real Vehicle::wheel_speed_kmh() const { return state.forward_speed() * 3.6; }

void Vehicle::hull_sphere(int i, Vec3 &c, real &r) const {
	const Vec3 &h = params.half_extents;
	real ground_clear = params.cg_height - 0.13; // lowest point of hull relative to CG
	if (i < 8) {
		r = std::min(h.x * 0.45, h.y * 0.55);
		r = std::max(r, 0.28);
		real y = -ground_clear + r;
		real x = (i % 2 == 0 ? -1.0 : 1.0) * (h.x - r);
		int row = i / 2; // 0 front .. 3 rear
		real z = lerpr(-h.z + r, h.z - r, row / 3.0);
		c = Vec3(x, y, z);
	} else {
		// Roof spheres: as wide as the cabin but never reaching below the floor pan.
		r = std::min({h.x * 0.62, h.y * 0.8, (h.y + ground_clear) * 0.5 - 0.02});
		real z = (i == 8 ? -1.0 : 1.0) * h.z * 0.3;
		c = Vec3(0.0, h.y - r, z);
	}
}

real Vehicle::inverse_mass_at(const Vec3 &p, const Vec3 &n) const {
	Vec3 r = p - state.pos;
	Vec3 rn = r.cross(n);
	Vec3 rn_b = state.rot.inv_rotate(rn);
	Vec3 ii = rn_b.mul(derived.inv_inertia);
	return 1.0 / params.mass + rn_b.dot(ii);
}

void Vehicle::apply_impulse(const Vec3 &j, const Vec3 &p) {
	state.vel += j / params.mass;
	Vec3 r = p - state.pos;
	Vec3 t_b = state.rot.inv_rotate(r.cross(j));
	Vec3 dw_b = t_b.mul(derived.inv_inertia);
	state.ang_vel += state.rot.rotate(dw_b);
}

void Vehicle::add_collision_event(const CollisionEvent &e) {
	if (state.collision_count < VehicleState::MAX_EVENTS) {
		state.events[state.collision_count++] = e;
	} else {
		int weakest = 0;
		for (int i = 1; i < VehicleState::MAX_EVENTS; ++i)
			if (state.events[i].impulse < state.events[weakest].impulse) weakest = i;
		if (state.events[weakest].impulse < e.impulse) state.events[weakest] = e;
	}
}

void Vehicle::add_dent(const Vec3 &world_p, real impulse) {
	if (impulse < 1800.0) return;
	Vec3 local = state.rot.inv_rotate(world_p - state.pos);
	DamageState &d = state.damage;
	real amount = clampr(impulse / 60000.0, 0.0, 0.25);
	const Vec3 &h = params.half_extents;
	if (local.z < -h.z * 0.45) d.front = saturate(d.front + amount);
	else if (local.z > h.z * 0.45) d.rear = saturate(d.rear + amount);
	else if (local.x < 0) d.left = saturate(d.left + amount);
	else d.right = saturate(d.right + amount);
	// Merge with an existing dent nearby, else push a new one.
	for (int i = 0; i < DamageState::MAX_DENTS; ++i) {
		if (d.dent_depth[i] > 0.0 && (d.dent_pos[i] - local).length() < 0.35) {
			d.dent_depth[i] = std::min(0.14, d.dent_depth[i] + clampr(impulse / 90000.0, 0.0, 0.06));
			return;
		}
	}
	d.dent_pos[d.dent_head] = local;
	d.dent_depth[d.dent_head] = clampr(impulse / 70000.0, 0.01, 0.10);
	d.dent_head = (d.dent_head + 1) % DamageState::MAX_DENTS;
}

real Vehicle::steer_range(real speed) const {
	switch (assists.steering) {
		case STEER_ASSISTED: return lerpr(1.0, 0.22, smoothstep(4.0, 45.0, speed));
		case STEER_STANDARD: return lerpr(1.0, 0.34, smoothstep(5.0, 50.0, speed));
		default: return lerpr(1.0, 0.55, smoothstep(8.0, 60.0, speed));
	}
}

void Vehicle::update_inputs(real dt) {
	VehicleState &s = state;
	real speed = s.speed();
	real fwd_speed = s.forward_speed();

	// Drift angle: heading vs velocity, positive when sliding with the tail out to the left.
	if (speed > 2.0) {
		Vec3 v_local = s.rot.inv_rotate(s.vel);
		s.drift_angle = std::atan2(v_local.x, -v_local.z);
	} else {
		s.drift_angle = 0.0;
	}

	// Steering: speed-sensitive range, dynamically relaxed during slides for countersteer authority
	real drift_k = smoothstep(0.04, 0.22, std::fabs(s.drift_angle));
	real steer_k = lerpr(steer_range(speed), 1.0, drift_k);
	real target = input.steer * params.max_steer * steer_k;

	if (assists.steering != STEER_SIMULATION || assists.countersteer > 0.0) {
		real cs = assists.countersteer * (assists.steering == STEER_SIMULATION ? 0.5 : 1.0);
		if (speed > 4.0 && fwd_speed > 0.0) {
			// Steer toward the velocity vector: the self-aligning torque a real rack would feed back.
			real beta = clampr(s.drift_angle, -params.max_steer, params.max_steer);
			target += beta * cs * smoothstep(0.03, 0.18, std::fabs(beta));
		}
	}
	target = clampr(target, -params.max_steer, params.max_steer);
	real rate = params.steer_speed * (std::fabs(target) < std::fabs(s.steer_angle) ? 1.8 : 1.1);
	s.steer_angle = move_toward(s.steer_angle, target, rate * dt);
	s.steer_input_filtered = s.steer_angle / params.max_steer;

	// Ackermann: inner wheel turns more.
	real sa = s.steer_angle;
	if (std::fabs(sa) > 1e-4) {
		real L = params.wheelbase, T = params.track_front;
		real R = L / std::tan(std::fabs(sa));
		real inner = std::atan(L / std::max(R - T * 0.5, 0.2));
		real outer = std::atan(L / (R + T * 0.5));
		real ai = lerpr(std::fabs(sa), inner, params.ackermann);
		real ao = lerpr(std::fabs(sa), outer, params.ackermann);
		if (sa > 0) { // right turn: right wheel inner
			s.wheels[FR].steer = ai;
			s.wheels[FL].steer = ao;
		} else {
			s.wheels[FL].steer = -ai;
			s.wheels[FR].steer = -ao;
		}
	} else {
		s.wheels[FL].steer = s.wheels[FR].steer = 0.0;
	}
	s.wheels[FL].steer += params.toe_front;
	s.wheels[FR].steer -= params.toe_front;
	s.wheels[RL].steer = params.toe_rear;
	s.wheels[RR].steer = -params.toe_rear;
}

void Vehicle::update_gearbox(real dt) {
	VehicleState &s = state;
	real fwd = s.forward_speed();
	bool automatic = assists.gearbox == GEARBOX_AUTO;

	if (s.shift_timer > 0.0) {
		real before = s.shift_timer;
		s.shift_timer -= dt;
		// Gear engages halfway through the shift.
		if (before > params.shift_time * 0.5 && s.shift_timer <= params.shift_time * 0.5) s.gear = s.pending_gear;
		if (s.shift_timer <= 0.0) {
			s.shift_timer = 0.0;
			s.gear = s.pending_gear;
		}
		return;
	}
	s.auto_shift_cooldown = std::max(0.0, s.auto_shift_cooldown - dt);

	auto begin_shift = [&](int g) {
		if (g == s.gear) return;
		s.pending_gear = g;
		s.shift_timer = params.shift_time;
		s.auto_shift_cooldown = params.shift_time + 0.35;
	};

	if (!automatic) {
		if (input.shift_up && s.gear < params.gear_count) begin_shift(s.gear < 0 ? 0 : s.gear + 1);
		else if (input.shift_down && s.gear > -1) begin_shift(s.gear - 1);
		return;
	}

	// Automatic: reverse on held brake at standstill, forward on throttle.
	if (s.gear >= 1 && std::fabs(fwd) < 0.8 && input.brake > 0.6 && input.throttle < 0.05) {
		if (input.reverse_request) begin_shift(-1);
		return;
	}
	if (s.gear == -1) {
		if (input.throttle > 0.1 && std::fabs(fwd) < 1.0) begin_shift(1);
		return;
	}
	if (s.gear == 0) {
		begin_shift(1);
		return;
	}
	if (s.auto_shift_cooldown > 0.0) return;

	real rpm = s.engine_rpm;
	real thr = input.throttle;
	real up_rpm = params.redline_rpm * lerpr(0.62, 0.975, smoothstep(0.1, 0.9, thr));
	// Wheel-speed based rpm avoids upshifting mid burnout (engine rpm flares with wheelspin).
	real R = (derived.driven_mask & (1 << RL)) ? params.wheel_radius_rear : params.wheel_radius_front;
	real ground_rpm = std::fabs(fwd) / R * gear_ratio(s.gear) * params.final_drive * 60.0 / TAU;
	if (s.gear < params.gear_count && rpm > up_rpm && ground_rpm > up_rpm * 0.88) {
		begin_shift(s.gear + 1);
		return;
	}
	if (s.gear > 1) {
		real lower_rpm = std::fabs(fwd) / R * gear_ratio(s.gear - 1) * params.final_drive * 60.0 / TAU;
		real down_rpm = params.redline_rpm * lerpr(0.30, 0.62, thr);
		if (input.brake > 0.3) down_rpm = params.redline_rpm * 0.55; // hold revs into corners
		if (rpm < down_rpm && lower_rpm < params.redline_rpm * 0.9) begin_shift(s.gear - 1);
	}
}

real Vehicle::tire_temp_factor(const WheelState &w, const TireSpec &t) const {
	real off = std::fabs(w.temp - t.opt_temp);
	real over = std::max(0.0, off - t.temp_window * 0.35);
	return 1.0 - 0.12 * smoothstep(0.0, t.temp_window, over);
}

void Vehicle::step(const CollisionGrid &world, real dt) {
	if (frozen) return;
	state.collision_count = 0;
	update_inputs(dt);
	update_gearbox(dt);
	real h = dt / CHASSIS_SUBSTEPS;
	for (int i = 0; i < CHASSIS_SUBSTEPS; ++i) {
		substep(world, h);
		solve_static_collisions(world);
	}
	state.distance += state.speed() * dt;
}

void Vehicle::substep(const CollisionGrid &world, real h) {
	VehicleState &s = state;
	const VehicleParams &P = params;
	Vec3 up = s.rot.up();
	Vec3 fwd = s.rot.forward();
	Vec3 right = s.rot.right();
	real speed = s.speed();

	// ---- Driver inputs after assists / gear logic ---------------------------------------------
	bool automatic = assists.gearbox == GEARBOX_AUTO;
	real throttle = input.throttle;
	real brake = input.brake;
	if (automatic && s.gear == -1) std::swap(throttle, brake);
	real clutch_pedal = input.clutch;

	// Rev limiter: fuel cut bounce.
	s.limiter_timer = std::max(0.0, s.limiter_timer - h);
	if (s.engine_rpm >= P.limiter_rpm) s.limiter_timer = 0.07;
	s.limiter_hit = s.limiter_timer > 0.0;
	if (s.limiter_hit) throttle = 0.0;

	// Shift: throttle cut on upshift, blip on downshift, clutch disengaged.
	real shift_clutch = 1.0;
	if (s.shift_timer > 0.0) {
		shift_clutch = 0.0;
		if (s.pending_gear > s.gear || s.pending_gear == 0) throttle = 0.0;
		else throttle = std::max(throttle, 0.55);
	}

	// TCS: trim throttle when driven wheels overspin.
	s.tcs_active = false;
	if (assists.tcs && speed > 0.5 && s.gear != 0) {
		real worst = 0.0;
		for (int i = 0; i < 4; ++i)
			if (derived.driven_mask & (1 << i)) worst = std::max(worst, s.wheels[i].slip_ratio * signr(s.forward_speed() + 0.01));
		real pk = P.tire_rear.peak_slip_ratio;
		if (worst > pk * 1.35) {
			throttle *= clampr(1.0 - (worst - pk * 1.35) * 4.0, 0.15, 1.0);
			s.tcs_active = true;
		}
	}

	// STM: yaw stability from yaw-rate error (reacts in tenths of a second at 250 km/h, long
	// before a large slip angle builds) plus a slip-angle backstop. Oversteer: brake the outer
	// front, trim throttle, relieve the rear brakes.
	s.stm_active = false;
	real stm_brake[4] = {0, 0, 0, 0};
	real stm_rear_relief = 1.0;
	if (assists.stm && speed > 8.0) {
		real yaw = s.ang_vel.dot(up);
		// Reference yaw from the steering (bicycle model with mild understeer), grip-limited.
		real v_f = std::max(std::fabs(s.forward_speed()), 1.0);
		real yaw_ref = -v_f * std::tan(s.steer_angle) / (P.wheelbase * (1.0 + sqr(v_f / 45.0) * 0.4));
		real yaw_cap = GRAVITY * 1.1 / v_f;
		yaw_ref = clampr(yaw_ref, -yaw_cap, yaw_cap);
		real err = yaw - yaw_ref; // + = yawing left more than asked
		real beta = s.drift_angle;
		real over = std::max(std::fabs(err) - 0.04, 0.0) * 4.0 + std::max(std::fabs(beta) - 0.1, 0.0) * 3.0;
		if (over > 0.0 && signr(err) == signr(beta == 0.0 ? err : beta)) {
			real amount = saturate(over);
			// Yawing left too much (err > 0) -> brake the front right, and vice versa.
			int outer = err > 0 ? FR : FL;
			stm_brake[outer] = amount * P.brake_torque * 0.4;
			throttle *= 1.0 - 0.7 * amount;
			stm_rear_relief = 1.0 - 0.6 * amount;
			s.stm_active = true;
		}
	}
	s.throttle_applied = throttle;
	s.brake_applied = brake;

	// ---- Suspension raycasts -----------------------------------------------------------------
	Vec3 total_force(0, -P.mass * GRAVITY, 0);
	Vec3 total_torque;
	real susp_force[4] = {0, 0, 0, 0};
	Vec3 contact_p[4];
	int grounded = 0;

	for (int i = 0; i < 4; ++i) {
		WheelState &w = s.wheels[i];
		bool front = i < 2;
		real R = front ? P.wheel_radius_front : P.wheel_radius_rear;
		real rest = front ? P.rest_length_front : P.rest_length_rear;
		real travel = front ? P.travel_front : P.travel_rear;
		Vec3 mount = world_point(derived.mounts[i]);
		real ray_len = rest + R;
		RayHit hit = world.raycast(mount, -up, ray_len + 0.05, COL_DRIVABLE);
		real prev = w.compression;
		if (hit.hit && hit.t <= ray_len) {
			const SurfaceInfo &si = surface_info(hit.surface);
			real bump = 0.0;
			if (si.bump_amp > 0.0) {
				bump = si.bump_amp * (value_noise(hit.point.x * si.bump_freq, hit.point.z * si.bump_freq) - 0.5) * 2.0;
			}
			// Tyre enveloping: the carcass swallows short, sharp bumps. Low-pass the bump input
			// (~6 Hz) so damper velocity doesn't spike to kilonewtons on grass at 200+ km/h.
			w.bump += (bump - w.bump) * exp_blend(38.0, h);
			real comp = ray_len - hit.t + w.bump;
			w.contact = comp > 0.0;
			w.compression = std::max(0.0, comp);
			w.contact_normal = hit.normal.dot(up) < 0.0 ? -hit.normal : hit.normal;
			w.contact_point = hit.point;
			w.surface = hit.surface;
			(void)travel;
		} else {
			w.contact = false;
			w.compression = move_toward(w.compression, 0.0, 2.0 * h);
		}
		w.compression_vel = (w.compression - prev) / h;
		if (w.contact) grounded++;
		contact_p[i] = w.contact ? w.contact_point : mount - up * ray_len;
	}

	real arb_f = (s.wheels[FL].compression - s.wheels[FR].compression) * P.arb_front;
	real arb_r = (s.wheels[RL].compression - s.wheels[RR].compression) * P.arb_rear;
	for (int i = 0; i < 4; ++i) {
		WheelState &w = s.wheels[i];
		if (!w.contact) {
			w.load = 0.0;
			continue;
		}
		bool front = i < 2;
		real k = front ? P.spring_front : P.spring_rear;
		real travel = front ? P.travel_front : P.travel_rear;
		real v = w.compression_vel;
		real damp = v > 0.0 ? (front ? P.bump_front : P.bump_rear) * v : (front ? P.rebound_front : P.rebound_rear) * v;
		real f = k * w.compression + damp;
		// Progressive bump stop in the last 15% of travel, hard stop beyond.
		real bs_start = travel * 0.85;
		if (w.compression > bs_start) {
			real e = w.compression - bs_start;
			f += 600000.0 * e * e + 250000.0 * e * 0.2;
			if (v > 0.0) f += 9000.0 * v;
		}
		real arb = front ? arb_f : arb_r;
		f += (i % 2 == 0) ? arb : -arb;
		f = std::max(0.0, f);
		susp_force[i] = f;
		w.load = f * std::max(0.2, w.contact_normal.dot(up));
		Vec3 F = up * f;
		total_force += F;
		total_torque += (contact_p[i] - s.pos).cross(F);
	}

	// ---- Drivetrain --------------------------------------------------------------------------
	real ratio = gear_ratio(s.gear) * P.final_drive;
	real I_e = P.engine_inertia;
	real omega_e = s.engine_rpm * TAU / 60.0;

	// Turbo spool.
	if (P.max_boost > 0.0) {
		real target = P.max_boost * throttle * smoothstep(P.spool_rpm * 0.45, P.spool_rpm, s.engine_rpm);
		real k = target > s.boost ? P.spool_rate : P.spool_rate * 3.5;
		s.boost += (target - s.boost) * exp_blend(k, h);
	} else {
		s.boost = 0.0;
	}

	// Idle controller keeps the engine alive.
	real engine_t = engine_torque_at(s.engine_rpm, throttle, s.boost);
	if (s.engine_rpm < P.idle_rpm * 1.1) engine_t += clampr((P.idle_rpm * 1.1 - s.engine_rpm) * 0.25, 0.0, 70.0);
	s.engine_torque_out = engine_t;

	// Driven wheel speed on the gearbox side.
	int n_driven = 0;
	real omega_sum = 0.0;
	real front_avg = (s.wheels[FL].omega + s.wheels[FR].omega) * 0.5;
	real rear_avg = (s.wheels[RL].omega + s.wheels[RR].omega) * 0.5;
	real omega_ds;
	if (P.layout == DRIVE_AWD) {
		omega_ds = front_avg * P.awd_front_split + rear_avg * (1.0 - P.awd_front_split);
		n_driven = 4;
	} else {
		for (int i = 0; i < 4; ++i)
			if (derived.driven_mask & (1 << i)) {
				omega_sum += s.wheels[i].omega;
				n_driven++;
			}
		omega_ds = omega_sum / std::max(1, n_driven);
	}

	// Clutch engagement: pedal, shift, auto-clutch launch and anti-stall.
	real engage = (1.0 - clutch_pedal) * shift_clutch;
	if (s.gear == 0) engage = 0.0;
	real idle_w = P.idle_rpm * TAU / 60.0;
	if (assists.gearbox != GEARBOX_MANUAL_CLUTCH || clutch_pedal < 0.01) {
		// Auto clutch slips at low wheel speed so launches don't stall and rpm rises into the band.
		real locked_rpm = std::fabs(omega_ds * ratio) * 60.0 / TAU;
		real launch_rpm = P.idle_rpm + (P.redline_rpm * 0.45 - P.idle_rpm) * throttle;
		if (locked_rpm < launch_rpm) {
			// No creep: with the throttle closed the auto clutch opens fully near standstill.
			// Below idle speed in gear the clutch only closes with throttle (like a DCT/auto), else a
			// short first gear plus big idle torque feeds back into a slow creep.
			real pedal = smoothstep(0.02, 0.12, throttle);
			real slip_engage = smoothstep(P.idle_rpm * 0.9, launch_rpm, s.engine_rpm) * 0.85 * pedal;
			engage = std::min(engage, std::max(slip_engage, locked_rpm / std::max(launch_rpm, 1.0) * pedal));
		}
	}
	s.clutch_engagement = engage;

	real I_w = P.wheel_inertia;
	real clutch_t = 0.0;
	if (engage > 0.0 && std::fabs(ratio) > 1e-6) {
		real delta = omega_e - omega_ds * ratio;
		real denom = h * (1.0 / I_e + ratio * ratio / (I_w * std::max(1, n_driven)));
		real want = 0.6 * delta / denom;
		real cap = P.clutch_torque * engage;
		real launch_rpm = P.idle_rpm + (P.redline_rpm * 0.45 - P.idle_rpm) * throttle;
		if (s.engine_rpm < launch_rpm && throttle > 0.08) {
			cap = std::min(cap, std::max(0.0, engine_t * 0.90));
		}
		clutch_t = clampr(want, -cap, cap);
	}
	real diff_in = clutch_t * ratio * P.drivetrain_efficiency;
	bool on_power = diff_in * signr(omega_ds + 1e-3) >= 0.0;

	real drive_t[4] = {0, 0, 0, 0};
	auto split_axle = [&](int l, int r, real T, DiffType type) {
		real wl = s.wheels[l].omega, wr = s.wheels[r].omega;
		real lock_cap;
		if (type == DIFF_OPEN) lock_cap = 0.0;
		else if (type == DIFF_LOCKED) lock_cap = 1e9;
		else lock_cap = P.lsd_preload + (on_power ? P.lsd_accel : P.lsd_decel) * std::fabs(T);
		real want = 0.5 * I_w / h * (wl - wr);
		real lock = clampr(want, -lock_cap, lock_cap);
		drive_t[l] += T * 0.5 - lock * 0.5;
		drive_t[r] += T * 0.5 + lock * 0.5;
	};
	switch (P.layout) {
		case DRIVE_FF: split_axle(FL, FR, diff_in, P.diff_front); break;
		case DRIVE_AWD: {
			real tf = diff_in * P.awd_front_split;
			real tr = diff_in - tf;
			real cap = P.center_lock * std::fabs(diff_in) + 40.0;
			real lock = clampr(0.5 * I_w * 2.0 / h * (front_avg - rear_avg), -cap, cap);
			tf -= lock * 0.5;
			tr += lock * 0.5;
			split_axle(FL, FR, tf, P.diff_front);
			split_axle(RL, RR, tr, P.diff_rear);
			break;
		}
		default: split_axle(RL, RR, diff_in, P.diff_rear); break;
	}

	// Engine speed integrates its own torque minus what the clutch passes.
	omega_e += (engine_t - clutch_t) / I_e * h;
	omega_e = std::max(omega_e, idle_w * 0.55);
	s.engine_rpm = omega_e * 60.0 / TAU;
	if (s.engine_rpm > P.limiter_rpm + 250.0) s.engine_rpm = P.limiter_rpm + 250.0;

	// ---- Brakes ------------------------------------------------------------------------------
	real brake_t[4];
	real bf = brake * P.brake_torque * P.brake_bias * 0.5;
	real br = brake * P.brake_torque * (1.0 - P.brake_bias) * 0.5;
	brake_t[FL] = bf + stm_brake[FL];
	brake_t[FR] = bf + stm_brake[FR];
	// EBD: rear service-brake torque follows the rear tyres' current load so they keep lateral
	// grip in reserve (always on in every modern car, independent of the ABS assist). The
	// handbrake bypasses it on purpose.
	// Straight-line braking uses ~90% of rear grip; cornering load pulls it back toward 50%.
	real a_lat = speed * std::fabs(s.ang_vel.dot(up));
	real ebd_share = lerpr(0.9, 0.5, saturate(a_lat / 6.0));
	for (int i : {RL, RR}) {
		const WheelState &w = s.wheels[i];
		real cap = ebd_share * P.tire_rear.grip * std::max(w.load, 0.0) * P.wheel_radius_rear;
		real service = std::min(br, cap) * stm_rear_relief;
		brake_t[i] = service + input.handbrake * P.handbrake_torque * 0.5 + stm_brake[i];
	}

	// ---- Tires -------------------------------------------------------------------------------
	s.abs_active = false;
	real wet = s.wetness;
	for (int i = 0; i < 4; ++i) {
		WheelState &w = s.wheels[i];
		bool front = i < 2;
		const TireSpec &T = front ? P.tire_front : P.tire_rear;
		real R = front ? P.wheel_radius_front : P.wheel_radius_rear;
		bool driven = (derived.driven_mask & (1 << i)) != 0;
		real I_eff = I_w;
		if (driven && engage > 0.5 && std::fabs(ratio) > 1e-6) I_eff += I_e * ratio * ratio * engage / std::max(1, n_driven) * 0.5;

		real Tb = brake_t[i];
		w.drive_torque = drive_t[i];

		if (!w.contact || w.load <= 0.0) {
			// Free spinning wheel: drive and brake only.
			real om = w.omega + drive_t[i] / I_eff * h;
			om = move_toward(om, 0.0, (Tb + 2.0) / I_eff * h);
			w.omega = om;
			w.fx = w.fy = 0.0;
			w.slip_speed = 0.0;
			w.grip_used = 0.0;
			w.brake_torque = Tb;
			w.spin += w.omega * h;
			continue;
		}

		// Contact frame on the ground plane.
		Vec3 n = w.contact_normal;
		Quat steer_q = Quat::from_axis_angle(up, -w.steer);
		Vec3 wf = steer_q.rotate(fwd);
		Vec3 f = project_on_plane(wf, n).normalized();
		Vec3 r = f.cross(n);
		Vec3 vp = point_velocity(contact_p[i]);
		real vx = vp.dot(f);
		real vy = vp.dot(r);

		// Relaxed slip angle (lateral carcass deflection lags the steady-state slip).
		real denom = std::max(std::fabs(vx), MIN_SLIP_SPEED);
		real alpha_ss = std::atan2(vy, denom);
		const SurfaceInfo &si = surface_info(w.surface);
		real relax = T.relaxation * (si.loose ? 1.6 : 1.0);
		real rate = (std::fabs(vx) + 0.5 * std::fabs(vy) + 0.8) / relax;
		w.slip_angle = alpha_ss + (w.slip_angle - alpha_ss) * std::exp(-rate * h);

		// Friction available at this patch.
		w.puddle = puddle_mask(w.contact_point.x, w.contact_point.z, wet);
		real surf_grip = lerpr(si.grip, si.wet_grip + T.wet_bonus, wet);
		if (si.loose) surf_grip += T.loose_bonus * si.grip;
		if (w.surface == SURF_SNOW || w.surface == SURF_ICE) surf_grip += T.snow_bonus * 0.3;
		real aqua = w.puddle * smoothstep(14.0, 32.0, std::fabs(vx)) * 0.65;
		surf_grip *= 1.0 - aqua;
		real Fz = w.load;
		real Fz0 = derived.static_load[i];
		real load_factor = clampr(1.0 - T.load_sensitivity * (Fz / Fz0 - 1.0), 0.55, 1.25);
		real width = front ? P.tire_width_front : P.tire_width_rear;
		real width_factor = 1.0 + (width - 0.205) * 0.9;
		real camber = front ? P.camber_front : P.camber_rear;
		real camber_factor = 1.0 - 1.8 * sqr(camber + 0.03);
		real pressure = front ? P.tire_pressure_front : P.tire_pressure_rear;
		real pressure_factor = 1.0 - 0.10 * sqr(pressure - 2.1);
		real mu = T.grip * surf_grip * load_factor * width_factor * camber_factor * pressure_factor *
				tire_temp_factor(w, T) * (1.0 - 0.12 * w.wear);
		mu = std::max(mu, 0.05);

		real pk_x = T.peak_slip_ratio * (si.loose ? 1.5 : 1.0);
		real pk_y = T.peak_slip_angle * (si.loose ? 1.45 : 1.0);
		real slide = si.loose ? std::max(T.slide_ratio, 0.9) : T.slide_ratio;
		real tan_pk_y = std::tan(pk_y);

		auto forces = [&](real omega, real &fx, real &fy, real &rho_out) {
			real kappa = (omega * R - vx) / denom;
			real sx = kappa / pk_x;
			real sy = std::tan(w.slip_angle) / tan_pk_y;
			real rho = std::sqrt(sx * sx + sy * sy);
			rho_out = rho;
			if (rho < 1e-9) {
				fx = fy = 0.0;
				return;
			}
			real F = mu * Fz * tire_curve(rho, slide);
			fx = F * (sx / rho) * 1.05;
			fy = -F * (sy / rho);
		};

		// ABS: modulate service brake torque when the wheel approaches lock (handbrake bypasses ABS for drift entry).
		bool is_handbraking = (i == RL || i == RR) && (input.handbrake > 0.05);
		if (assists.abs && !is_handbraking && Tb > 0.0 && std::fabs(vx) > 2.0) {
			real kappa = (w.omega * R - vx) / denom;
			if (kappa * signr(vx) < -pk_x * 1.1) {
				Tb *= 0.35;
				s.abs_active = true;
			}
		}
		w.brake_torque = Tb;

		// Implicit wheel spin update: linearize tire force around current omega.
		real fx0, fy0, rho0, fx1, fy1, rho1;
		real d_om = std::max(0.05, std::fabs(w.omega) * 1e-3);
		forces(w.omega, fx0, fy0, rho0);
		forces(w.omega + d_om, fx1, fy1, rho1);
		real dFdw = std::max(0.0, (fx1 - fx0) / d_om);
		// Backward Euler: I dw = h (T - R Fx(w + dw))  =>  dw = h (T - R Fx0) / (I + h R dFx/dw).
		real I_imp = I_eff + h * R * dFdw;
		real om = w.omega + h * (drive_t[i] - fx0 * R) / I_imp;
		// Brake torque can stop the wheel but never reverse it.
		real rolling = T.rolling * si.rolling * Fz * R;
		real brake_dw = (Tb + rolling * 0.25) * h / I_imp;
		om = move_toward(om, 0.0, brake_dw);
		w.omega = om;

		real fx, fy, rho;
		forces(w.omega, fx, fy, rho);
		// Rolling resistance and loose-surface sinkage drag.
		fx -= signr(vx) * (si.rolling * T.rolling * Fz + si.drag * Fz * 0.08 * smoothstep(0.0, 5.0, std::fabs(vx)));

		// Low-speed lateral and longitudinal damping keeps parked cars from creeping on slopes.
		if (std::fabs(vx) < 2.0) {
			real lat_hold = -vy * P.mass * 0.25 / h * 0.1;
			real cap = mu * Fz;
			fy = clampr(lerpr(lat_hold, fy, std::fabs(vx) / 2.0), -cap, cap);
		}
		if (Tb > 40.0 && std::fabs(vx) < 0.25 && throttle < 0.05) {
			real long_hold = -vx * P.mass * 0.25 / h * 0.2;
			real cap = mu * Fz;
			fx = clampr(long_hold, -cap, cap);
		}

		w.fx = fx;
		w.fy = fy;
		w.slip_ratio = (w.omega * R - vx) / denom;
		w.slip_speed = std::sqrt(sqr(w.omega * R - vx) + sqr(vy));
		w.grip_used = rho <= 1.0 ? rho : 1.0 + (rho - 1.0) * 0.25;

		// Tire temperature: sliding power heats, airflow cools.
		real slide_power = std::fabs(fx * (w.omega * R - vx)) + std::fabs(fy * vy);
		real heat = slide_power * 1.1e-4 * T.heat_rate + Fz * std::fabs(vx) * 2.0e-6;
		real cool = (w.temp - s.ambient_temp) * (0.018 + 0.0022 * std::fabs(vx)) * (1.0 + wet * 1.5);
		w.temp += (heat - cool) * h;
		w.wear = std::min(1.0, w.wear + slide_power * 2.0e-10);

		Vec3 F = f * fx + r * fy;
		total_force += F;
		total_torque += (contact_p[i] - s.pos).cross(F);
		w.spin += w.omega * h;
	}

	// ---- Aero --------------------------------------------------------------------------------
	real v_fwd = s.vel.dot(fwd);
	real drag_k = 0.5 * AIR_DENSITY * P.drag_area * (1.0 - 0.38 * s.slipstream);
	total_force += s.vel * (-drag_k * speed);
	real q = 0.5 * AIR_DENSITY * v_fwd * v_fwd;
	Vec3 df_front = -up * (q * P.lift_front);
	Vec3 df_rear = -up * (q * P.lift_rear);
	Vec3 p_front = world_point({0, 0, derived.axle_front_z});
	Vec3 p_rear = world_point({0, 0, derived.axle_rear_z});
	total_force += df_front + df_rear;
	total_torque += (p_front - s.pos).cross(df_front) + (p_rear - s.pos).cross(df_rear);

	if (P.top_speed_limiter > 0.0 && v_fwd > P.top_speed_limiter) total_force -= fwd * (P.mass * (v_fwd - P.top_speed_limiter) * 2.0);

	// ---- Integrate ---------------------------------------------------------------------------
	s.vel += total_force / P.mass * h;
	Vec3 w_b = s.rot.inv_rotate(s.ang_vel);
	Vec3 t_b = s.rot.inv_rotate(total_torque);
	Vec3 Iw = w_b.mul(derived.inertia);
	Vec3 dw = (t_b - w_b.cross(Iw)).mul(derived.inv_inertia);
	w_b += dw * h;
	// Drift snap-recovery damping: prevents violent pendulum tank-slappers upon counter-steer exit
	// when yaw rate opposes drift angle (car snapping back towards center).
	if (grounded >= 2 && speed > 4.0) {
		if (s.drift_angle * w_b.y < 0.0) {
			real snap_intensity = clampr(std::fabs(w_b.y) * 0.45, 0.0, 1.0);
			w_b.y *= 1.0 - (2.4 * snap_intensity) * h;
		}
	}
	// Tiny angular damping for numerical calm (air + bushings).
	w_b *= 1.0 - 0.15 * h;
	s.ang_vel = s.rot.rotate(w_b);
	s.pos += s.vel * h;
	s.rot = s.rot.integrated(s.ang_vel, h);

	if (grounded == 0) s.airborne_time += h;
	else s.airborne_time = 0.0;
	(void)right;
	(void)susp_force;
}

void Vehicle::solve_static_collisions(const CollisionGrid &world) {
	VehicleState &s = state;
	SphereContact contacts[6];
	for (int i = 0; i < HULL_SPHERES; ++i) {
		Vec3 lc;
		real r;
		hull_sphere(i, lc, r);
		Vec3 c = world_point(lc);
		int n = world.sphere_contacts(c, r, COL_SOLID, contacts, 6);
		for (int k = 0; k < n; ++k) {
			const SphereContact &ct = contacts[k];
			const SurfaceInfo &si = surface_info(ct.surface);
			Vec3 p = ct.point;
			Vec3 nrm = ct.normal;
			Vec3 vp = point_velocity(p);
			real vn = vp.dot(nrm);
			// Positional correction (split impulse style).
			if (ct.depth > 0.005) s.pos += nrm * ((ct.depth - 0.005) * 0.85);
			if (vn >= 0.0) continue;
			real inv_m = inverse_mass_at(p, nrm);
			real e = si.restitution * smoothstep(1.0, 6.0, -vn);
			real j = -(1.0 + e) * vn / inv_m;
			apply_impulse(nrm * j, p);
			// Friction (scrape).
			Vec3 vt = project_on_plane(point_velocity(p), nrm);
			real vt_len = vt.length();
			if (vt_len > 1e-4) {
				Vec3 tdir = vt / vt_len;
				real jt_max = vt_len / inverse_mass_at(p, tdir);
				real jt = std::min(si.scrape_friction * j, jt_max);
				apply_impulse(tdir * -jt, p);
			}
			if (j > 300.0) {
				CollisionEvent ev;
				ev.point = p;
				ev.normal = nrm;
				ev.impulse = j;
				ev.surface = ct.surface;
				add_collision_event(ev);
				add_dent(p, j);
			}
		}
	}
}

bool resolve_vehicle_pair(Vehicle &a, int ia, Vehicle &b, int ib) {
	const real bound_a = a.params.half_extents.length() + 0.2;
	const real bound_b = b.params.half_extents.length() + 0.2;
	if ((a.state.pos - b.state.pos).length_sq() > sqr(bound_a + bound_b)) return false;
	bool touched = false;
	Vec3 ca[Vehicle::HULL_SPHERES], cb[Vehicle::HULL_SPHERES];
	real ra[Vehicle::HULL_SPHERES], rb[Vehicle::HULL_SPHERES];
	for (int i = 0; i < Vehicle::HULL_SPHERES; ++i) {
		Vec3 l;
		a.hull_sphere(i, l, ra[i]);
		ca[i] = a.world_point(l);
		b.hull_sphere(i, l, rb[i]);
		cb[i] = b.world_point(l);
	}
	real total_j = 0.0;
	Vec3 event_p, event_n;
	for (int i = 0; i < Vehicle::HULL_SPHERES; ++i) {
		for (int k = 0; k < Vehicle::HULL_SPHERES; ++k) {
			Vec3 d = ca[i] - cb[k];
			real dist2 = d.length_sq();
			real rr = ra[i] + rb[k];
			if (dist2 >= rr * rr || dist2 < 1e-12) continue;
			real dist = std::sqrt(dist2);
			Vec3 n = d / dist; // from b to a
			real depth = rr - dist;
			Vec3 p = cb[k] + n * rb[k];
			real ma = a.params.mass, mb = b.params.mass;
			real wa = mb / (ma + mb), wb = ma / (ma + mb);
			a.state.pos += n * (depth * 0.5 * wa);
			b.state.pos -= n * (depth * 0.5 * wb);
			real vn = (a.point_velocity(p) - b.point_velocity(p)).dot(n);
			touched = true;
			if (vn >= 0.0) continue;
			real inv = a.inverse_mass_at(p, n) + b.inverse_mass_at(p, n);
			real j = -(1.0 + 0.2) * vn / inv;
			a.apply_impulse(n * j, p);
			b.apply_impulse(n * -j, p);
			// Side-by-side rubbing friction.
			Vec3 vt = project_on_plane(a.point_velocity(p) - b.point_velocity(p), n);
			real vt_len = vt.length();
			if (vt_len > 1e-4) {
				Vec3 td = vt / vt_len;
				real jt = std::min(0.25 * j, vt_len / (a.inverse_mass_at(p, td) + b.inverse_mass_at(p, td)));
				a.apply_impulse(td * -jt, p);
				b.apply_impulse(td * jt, p);
			}
			if (j > total_j) {
				event_p = p;
				event_n = n;
			}
			total_j += j;
		}
	}
	if (total_j > 250.0) {
		CollisionEvent ea;
		ea.point = event_p;
		ea.normal = event_n;
		ea.impulse = total_j;
		ea.surface = SURF_METAL;
		ea.other_vehicle = ib;
		a.add_collision_event(ea);
		a.add_dent(event_p, total_j);
		CollisionEvent eb = ea;
		eb.normal = -event_n;
		eb.other_vehicle = ia;
		b.add_collision_event(eb);
		b.add_dent(event_p, total_j);
	}
	return touched;
}

void Vehicle::save_state(std::vector<uint8_t> &out) const {
	size_t off = out.size();
	out.resize(off + sizeof(VehicleState));
	std::memcpy(out.data() + off, &state, sizeof(VehicleState));
}

bool Vehicle::load_state(const uint8_t *data, size_t size, size_t &offset) {
	if (offset + sizeof(VehicleState) > size) return false;
	std::memcpy(&state, data + offset, sizeof(VehicleState));
	offset += sizeof(VehicleState);
	return true;
}

} // namespace nt
