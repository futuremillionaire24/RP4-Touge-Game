#include "ai_driver.h"

namespace nt {

Personality difficulty_personality(int difficulty, uint64_t seed) {
	Rng r(seed * 7919 + 17);
	Personality p;
	static const real skill[7] = {0.78, 0.83, 0.875, 0.91, 0.94, 0.965, 0.99};
	int d = (int)clampr(difficulty, 0, 6);
	p.skill = skill[d] + r.range(-0.012, 0.012);
	p.aggression = clampr(0.3 + d * 0.08 + r.range(-0.15, 0.15), 0.05, 1.0);
	p.consistency = clampr(0.65 + d * 0.05 + r.range(-0.08, 0.08), 0.4, 1.0);
	p.mistake_rate = clampr(0.05 - d * 0.007, 0.004, 0.06);
	p.patience = r.range(0.25, 0.85);
	p.drift_style = false;
	return p;
}

void AIDriver::init(const RacingLine *line, const Vehicle &car, uint64_t seed) {
	rng_.reseed(seed);
	set_line(line, car);
	offset_ = offset_target_ = 0.0;
	stuck_time_ = offtrack_time_ = reverse_time_ = 0.0;
	follow_time_ = defend_cooldown_ = mistake_time_ = handbrake_time_ = 0.0;
	respawn_ = false;
}

void AIDriver::set_line(const RacingLine *line, const Vehicle &car) {
	line_ = line;
	if (!line_ || line_->size() == 0) return;
	CarEnvelope e = estimate_envelope(car.params);
	decel_ = e.decel;
	line_->speed_profile(profile_, e.mu, e.downforce_per_v2, car.params.mass, e.accel, e.decel, e.top_speed);
	index_ = line_->nearest(car.state.pos, -1);
}

AIDriver::Memory AIDriver::memory() const {
	Memory m;
	m.index = index_;
	m.offset = offset_;
	m.offset_target = offset_target_;
	m.stuck_time = stuck_time_;
	m.offtrack_time = offtrack_time_;
	m.reverse_time = reverse_time_;
	m.follow_time = follow_time_;
	m.defend_cooldown = defend_cooldown_;
	m.mistake_time = mistake_time_;
	m.mistake_kind = mistake_kind_;
	m.handbrake_time = handbrake_time_;
	m.steer_filtered = steer_filtered_;
	m.respawn = respawn_;
	return m;
}

void AIDriver::restore(const Memory &m) {
	index_ = m.index;
	offset_ = m.offset;
	offset_target_ = m.offset_target;
	stuck_time_ = m.stuck_time;
	offtrack_time_ = m.offtrack_time;
	reverse_time_ = m.reverse_time;
	follow_time_ = m.follow_time;
	defend_cooldown_ = m.defend_cooldown;
	mistake_time_ = m.mistake_time;
	mistake_kind_ = m.mistake_kind;
	handbrake_time_ = m.handbrake_time;
	steer_filtered_ = m.steer_filtered;
	respawn_ = m.respawn;
}

void AIDriver::respawn_pose(Vec3 &pos, Quat &rot, real &speed) {
	if (!line_ || line_->size() == 0) return;
	// Repeated respawns at the same spot: place the car progressively further ahead so a bad
	// corner can't trap it in a loop.
	if (std::abs(index_ - last_respawn_index_) < 12) repeat_respawns_++;
	else repeat_respawns_ = 0;
	last_respawn_index_ = index_;
	int i = line_->index_ahead(index_, 4.0 + 25.0 * repeat_respawns_);
	index_ = i;
	int nx = line_->wrap(i + 1);
	Vec3 dir = (line_->point(nx) - line_->point(i)).normalized();
	pos = line_->sample(i).center + line_->right_vector(i) * clampr(line_->offset(i), -1.5, 1.5) + Vec3(0, 0.6, 0);
	rot = quat_look(dir, line_->sample(i).normal);
	speed = profile_.empty() ? 10.0 : std::min(profile_[i] * 0.6, 22.0);
}

VehicleInput AIDriver::drive(const Vehicle &car, const std::vector<CarSnapshot> &others, int self_index, real dt) {
	VehicleInput in;
	if (!enabled || !line_ || line_->size() < 4) {
		// Parked (grid, cutscenes): hold the brakes so slopes don't roll the car away.
		in.brake = 1.0;
		in.handbrake = 1.0;
		return in;
	}
	const VehicleState &s = car.state;
	const VehicleParams &P = car.params;
	real v = s.forward_speed();
	Vec3 fwd = s.rot.forward();

	index_ = line_->nearest(s.pos, index_, 15);
	const TrackSample &here = line_->sample(index_);
	Vec3 right_here = line_->right_vector(index_);
	real lateral_from_center = (s.pos - here.center).dot(right_here);

	// ---- Recovery: off track / stuck -------------------------------------------------------
	real limit_l = here.half_width_left + 5.0, limit_r = here.half_width_right + 5.0;
	bool offtrack = lateral_from_center < -limit_l || lateral_from_center > limit_r || (s.pos - here.center).y < -6.0;
	offtrack_time_ = offtrack ? offtrack_time_ + dt : 0.0;
	bool upside_down = s.rot.up().y < 0.2;
	if (s.speed() < 1.5 && reverse_time_ <= 0.0) stuck_time_ += dt;
	else if (s.speed() > 4.0) stuck_time_ = 0.0;
	// Progress watchdog: a car shuffling back and forth in a corner never trips the speed test,
	// but it also never gets anywhere. Only fire if speed is low and net progress stalled.
	progress_timer_ += dt;
	if (progress_timer_ > 10.0) {
		real now = line_->distance_at(index_);
		if (s.speed() < 2.0 && std::fabs(now - progress_mark_) < 6.0 && (line_->closed() || index_ < line_->size() - 20)) {
			respawn_ = true;
			respawn_reason_ = 4;
		}
		progress_mark_ = now;
		progress_timer_ = 0.0;
	}
	if (!respawn_) {
		if (offtrack_time_ > 3.0) respawn_reason_ = 1;
		else if (stuck_time_ > 6.0) respawn_reason_ = 2;
		else if (upside_down && s.speed() < 2.0) respawn_reason_ = 3;
		else respawn_reason_ = 0;
		respawn_ = respawn_reason_ != 0;
	}
	if (stuck_time_ > 1.8 && reverse_time_ <= 0.0) {
		reverse_time_ = 1.6;
		stuck_time_ = 1.9; // keep counting toward respawn if reversing doesn't help
	}
	if (reverse_time_ > 0.0) {
		reverse_time_ -= dt;
		Vec3 to_line = line_->point(line_->index_ahead(index_, 8.0)) - s.pos;
		Vec3 local = s.rot.inv_rotate(to_line);
		in.brake = 0.8;
		in.reverse_request = true;
		in.steer = clampr(-local.x * 0.4, -1.0, 1.0); // reversing: steer the opposite way
		return in;
	}

	// ---- Mistakes ------------------------------------------------------------------------
	if (mistake_time_ > 0.0) {
		mistake_time_ -= dt;
	} else {
		real rate = personality.mistake_rate * (1.3 - personality.consistency);
		if (rng_.chance(rate * dt)) {
			mistake_kind_ = rng_.irange(1, 3);
			mistake_time_ = rng_.range(0.8, 1.8);
		} else {
			mistake_kind_ = 0;
		}
	}

	// ---- Traffic awareness: overtaking, following, defending ------------------------------
	real speed_cap = 1e9;
	defend_cooldown_ = std::max(0.0, defend_cooldown_ - dt);
	real width_l = here.half_width_left - 1.2, width_r = here.half_width_right - 1.2;
	real base_offset = line_->offset(index_);
	bool blocked = false;
	real nearest_ahead = 1e9;
	for (int k = 0; k < (int)others.size(); ++k) {
		if (k == self_index || !others[k].active) continue;
		const CarSnapshot &o = others[k];
		Vec3 rel = s.rot.inv_rotate(o.pos - s.pos);
		real ahead = -rel.z; // + ahead
		real side = rel.x;
		real closing = v - o.vel.dot(fwd);
		if (ahead > 0.0 && ahead < 45.0 && std::fabs(side) < 5.5) {
			// Their line position relative to ours.
			real their_offset = o.line_offset;
			real lane_gap = std::fabs(their_offset - (base_offset + offset_));
			real need = P.half_extents.x + o.half_width + 0.5;
			real brake_zone = 3.0 + std::max(0.0, closing) * 0.9 + P.half_extents.z + o.half_length;
			if (lane_gap < need && ahead < brake_zone + 12.0) {
				nearest_ahead = std::min(nearest_ahead, ahead);
				follow_time_ += dt;
				// Pick the side with more room once patience runs out (aggressive drivers sooner).
				if (follow_time_ > personality.patience * 2.0 * (1.2 - personality.aggression) || closing > 3.0) {
					real room_left = (their_offset - o.half_width) - (-width_l);
					real room_right = width_r - (their_offset + o.half_width);
					real want_l = their_offset - need - base_offset;
					real want_r = their_offset + need - base_offset;
					if (room_right > P.half_extents.x * 2.0 + 0.4 && (room_right >= room_left || room_left < P.half_extents.x * 2.0 + 0.4)) offset_target_ = want_r;
					else if (room_left > P.half_extents.x * 2.0 + 0.4) offset_target_ = want_l;
					else blocked = true;
				} else {
					blocked = true;
				}
				if (blocked && ahead < brake_zone) {
					real o_speed = o.vel.dot(fwd);
					speed_cap = std::min(speed_cap, o_speed - 0.3 + (ahead - brake_zone * 0.6) * 0.4);
				}
			}
		}
		// Side-by-side: keep door-to-door spacing.
		if (std::fabs(rel.z) < P.half_extents.z + o.half_length + 0.5 && std::fabs(side) < P.half_extents.x + o.half_width + 1.1) {
			// Aim for one car-width of clearance from the car alongside.
			real clear = (side > 0 ? -1.0 : 1.0) * (P.half_extents.x + o.half_width + 1.1);
			offset_target_ = move_toward(offset_target_, o.line_offset - base_offset + clear, 3.0 * dt);
		}
		// Defend: a faster car right behind before a corner -> cover the inside once.
		if (ahead < 0.0 && ahead > -14.0 && std::fabs(side) < 3.5 && closing < -1.0 && defend_cooldown_ <= 0.0 &&
				personality.aggression > 0.45) {
			int corner = line_->index_ahead(index_, 60.0);
			real k_c = line_->curvature(corner);
			if (std::fabs(k_c) > 1.0 / 90.0) {
				offset_target_ = (k_c > 0 ? 1.0 : -1.0) * 1.4 - base_offset * 0.5;
				defend_cooldown_ = 6.0;
			}
		}
	}
	if (nearest_ahead > 60.0) follow_time_ = 0.0;
	// Drift back to the racing line when clear.
	if (!blocked && nearest_ahead > 25.0 && defend_cooldown_ < 4.0) offset_target_ = move_toward(offset_target_, 0.0, 0.6 * dt);
	if (mistake_kind_ == 2) offset_target_ += (index_ % 2 ? 1.0 : -1.0) * 0.9 * dt;
	real margin = P.half_extents.x + 0.3;
	real max_l = std::max(0.0, width_l - margin);
	real max_r = std::max(0.0, width_r - margin);
	offset_target_ = clampr(offset_target_, -max_l - base_offset, max_r - base_offset);
	offset_ = move_toward(offset_, offset_target_, 1.8 * dt);

	// ---- Speed target from the profile ---------------------------------------------------
	real wet_scale = 1.0 - 0.22 * wetness;
	real scale = personality.skill * speed_scale * wet_scale;
	if (mistake_kind_ == 1) scale *= 1.08; // brakes late / carries too much speed
	// Off the ideal line the corner is tighter than the profile assumed.
	scale *= 1.0 - 0.03 * std::min(std::fabs(offset_), 5.0);
	real vt = profile_[index_] * scale;
	// Feed-forward braking: deceleration needed to meet every profile point in the next stretch.
	real a_req = 0.0;
	real horizon = std::max(20.0, v * v / (2.0 * std::max(decel_, 1.0)) + v * 0.3);
	for (real d = 3.0; d <= horizon; d += 3.0) {
		real vp = profile_[line_->index_ahead(index_, d)] * scale;
		if (vp < v) a_req = std::max(a_req, (v * v - vp * vp) / (2.0 * std::max(d - v * 0.12, 1.0)));
	}
	vt = std::min(vt, speed_cap);
	if (!line_->closed() && index_ >= line_->size() - 3) vt = std::min(vt, 8.0);
	{
		// Rejoining: slow down while far off the line or pointing the wrong way.
		Vec3 tgt = line_->position_ahead(index_, 6.0, 0.0);
		Vec3 loc = s.rot.inv_rotate(tgt - s.pos);
		real heading_err = std::fabs(std::atan2(loc.x, -loc.z));
		if (heading_err > 1.4) vt = std::min(vt, 5.0);
		real off = std::fabs(lateral_from_center);
		real edge = std::max(here.half_width_left, here.half_width_right);
		if (off > edge) vt = std::min(vt, lerpr(18.0, 8.0, saturate((off - edge) / 6.0)));
	}

	// ---- Steering: pure pursuit on the offset line ---------------------------------------
	// Look-ahead shrinks in tight corners (pure pursuit cuts inside by ~L^2 / 2R).
	// Look-ahead: pure pursuit cuts inside by ~L^2 / 2R, so keep it moderate at speed and short
	// in tight corners.
	real L = clampr(3.5 + v * 0.34, 5.0, 26.0);
	real k_max = 0.0;
	for (real d = 0.0; d <= L; d += 3.0) k_max = std::max(k_max, std::fabs(line_->curvature(line_->index_ahead(index_, d))));
	if (k_max > 1e-4) L = clampr(std::min(L, 0.75 / k_max), 4.0, 38.0);
	// Human inconsistency: a slow lateral wander of the aim point (never a steering-angle
	// offset, whose effect grows with v^2 and becomes a violent weave at 200 km/h).
	real wander = (1.0 - personality.consistency) * 1.2 * std::sin(s.distance * 0.011 + self_index * 1.7);
	Vec3 target = line_->position_ahead(index_, L, offset_ + clampr(wander, -0.35, 0.35));
	Vec3 local = s.rot.inv_rotate(target - s.pos);
	real alpha = std::atan2(local.x, -local.z);
	real delta = std::atan(2.0 * P.wheelbase * std::sin(alpha) / std::max(L, 1.0));
	// Spun round / facing away from the line: pure pursuit's sin(alpha) collapses near 180 degrees,
	// so turn at full lock toward the target at walking pace instead.
	bool spun = std::fabs(alpha) > 1.4;
	if (spun) delta = signr(alpha) * P.max_steer;
	// Countersteer when sliding.
	if (std::fabs(s.drift_angle) > 0.12 && v > 5.0) delta += s.drift_angle * 0.7;
	real range = std::max(0.05, car.steer_range(s.speed()));
	real steer = clampr(delta / (P.max_steer * range), -1.0, 1.0);
	steer_filtered_ += (steer - steer_filtered_) * exp_blend(18.0, dt);
	in.steer = steer_filtered_;

	// ---- Throttle / brake -----------------------------------------------------------------
	real err = vt - v;
	real brake_ff = a_req / std::max(decel_, 1.0);
	if (brake_ff > 0.16 || err < -0.8) {
		in.throttle = 0.0;
		in.brake = clampr(std::max(brake_ff * 1.15, -err * 0.25), 0.0, 1.0);
	} else if (brake_ff > 0.06) {
		in.throttle = 0.0; // lift and coast into the braking zone
	} else if (err > 0.0) {
		in.throttle = clampr(0.35 + err * 0.3, 0.0, 1.0);
		// Feather the throttle while sliding.
		if (std::fabs(s.drift_angle) > 0.2 && !personality.drift_style) in.throttle *= 0.6;
	} else {
		in.throttle = 0.2;
	}
	if (v < 0.5 && vt > 1.0) in.throttle = std::max(in.throttle, 0.8);

	// ---- Drift style: handbrake flick into tight hairpins ---------------------------------
	handbrake_time_ = std::max(0.0, handbrake_time_ - dt);
	if (personality.drift_style && v > 11.0) {
		int entry = line_->index_ahead(index_, v * 0.6);
		if (std::fabs(line_->curvature(entry)) > 1.0 / 22.0 && handbrake_time_ <= 0.0 && std::fabs(s.drift_angle) < 0.15) handbrake_time_ = 0.28;
	}
	if (handbrake_time_ > 0.0) {
		in.handbrake = 1.0;
		in.throttle = std::max(in.throttle, 0.4);
	}
	return in;
}

} // namespace nt
