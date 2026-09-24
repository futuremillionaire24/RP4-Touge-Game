// AI racer: produces VehicleInput from the same physics as the player (no grip cheats).
#pragma once

#include "racing_line.h"
#include "rng.h"
#include "vehicle.h"

#include <vector>

namespace nt {

struct Personality {
	real skill = 0.95; // fraction of the theoretical speed profile used
	real aggression = 0.5; // overtake eagerness / defending
	real consistency = 0.8; // 1 = no noise
	real mistake_rate = 0.02; // mistakes per second (before consistency)
	real patience = 0.5; // how long it follows before trying a pass
	bool drift_style = false; // flicks the handbrake into hairpins
};

// Read-only view of another car, captured before the parallel AI phase.
struct CarSnapshot {
	Vec3 pos;
	Vec3 vel;
	Vec3 fwd;
	real half_length = 2.2;
	real half_width = 0.9;
	int line_index = 0;
	real line_offset = 0.0;
	real race_distance = 0.0;
	bool active = true;
};

class AIDriver {
public:
	Personality personality;
	real speed_scale = 1.0; // rubber band / difficulty multiplier set by the race manager
	real wetness = 0.0;
	bool enabled = true;

	void init(const RacingLine *line, const Vehicle &car, uint64_t seed);
	void set_line(const RacingLine *line, const Vehicle &car);
	// Computes inputs for this tick. `self_index` excludes itself from `others`.
	VehicleInput drive(const Vehicle &car, const std::vector<CarSnapshot> &others, int self_index, real dt);

	int line_index() const { return index_; }
	real line_offset() const { return offset_; }
	bool needs_respawn() const { return respawn_; }
	int respawn_reason() const { return respawn_reason_; } // 1 off track, 2 stuck, 3 upside down, 4 no progress
	void clear_respawn() {
		respawn_ = false;
		stuck_time_ = offtrack_time_ = reverse_time_ = 0.0;
		progress_timer_ = 0.0;
		progress_mark_ = -1e9;
	}
	// Best respawn transform on the line near the current index.
	void respawn_pose(Vec3 &pos, Quat &rot, real &speed);
	const std::vector<real> &profile() const { return profile_; }

	// Serialized with the rewind ring.
	struct Memory {
		int index = 0;
		real offset = 0.0, offset_target = 0.0;
		real stuck_time = 0.0, offtrack_time = 0.0, reverse_time = 0.0;
		real follow_time = 0.0, defend_cooldown = 0.0;
		real mistake_time = 0.0;
		int mistake_kind = 0;
		real handbrake_time = 0.0;
		real steer_filtered = 0.0;
		bool respawn = false;
	};
	Memory memory() const;
	void restore(const Memory &m);

private:
	const RacingLine *line_ = nullptr;
	std::vector<real> profile_;
	real decel_ = 8.0;
	Rng rng_;
	int index_ = 0;
	real offset_ = 0.0, offset_target_ = 0.0;
	real stuck_time_ = 0.0, offtrack_time_ = 0.0, reverse_time_ = 0.0;
	real follow_time_ = 0.0, defend_cooldown_ = 0.0;
	real mistake_time_ = 0.0;
	int mistake_kind_ = 0;
	real handbrake_time_ = 0.0;
	real steer_filtered_ = 0.0;
	bool respawn_ = false;
	int respawn_reason_ = 0;
	real progress_timer_ = 0.0;
	real progress_mark_ = -1e9;
	int last_respawn_index_ = -1000;
	int repeat_respawns_ = 0;
};

// Difficulty 0 (Novice) .. 6 (Unbeatable) -> base personality skill.
Personality difficulty_personality(int difficulty, uint64_t seed);

} // namespace nt
