// The simulation world: all cars, the static collision grid, AI drivers, race progress, slipstream
// and the rewind ring. Stepping is split into a parallel phase (AI + per-car integration against
// the read-only grid) and a short serial phase (car-car contacts, progress).
#pragma once

#include "ai_driver.h"
#include "collision_grid.h"
#include "racing_line.h"
#include "traffic.h"
#include "vehicle.h"

#include <deque>
#include <functional>
#include <vector>

namespace nt {

struct RaceProgress {
	int lap = 0;
	int line_index = 0;
	real line_distance = 0.0; // meters along the line within the lap
	real total = 0.0; // lap * length + line_distance (race order key)
	real line_offset = 0.0; // lateral meters from the line centre (+ right)
	bool wrong_way = false;
	real wrong_way_time = 0.0;
	int respawn_count = 0;
	int respawn_reasons[5] = {0, 0, 0, 0, 0}; // by AIDriver::respawn_reason()
};

class WorldSim {
public:
	using ParallelFor = std::function<void(int count, const std::function<void(int)> &body)>;

	CollisionGrid grid;
	std::vector<Vehicle> cars;
	std::vector<AIDriver> ai;
	std::vector<uint8_t> is_ai;
	std::vector<RaceProgress> progress;
	RacingLine line;
	bool has_line = false;
	real wetness = 0.0;
	real ambient_temp = 20.0;
	uint64_t tick = 0;
	real time_s = 0.0;

	// Ambient traffic (free roam only). Near misses by car 0 (the player) are queued for the game.
	TrafficSystem traffic;
	bool traffic_enabled = false;
	std::vector<NearMiss> near_miss_queue;

	int add_car(const VehicleParams &p, bool ai_controlled, uint64_t seed);
	void remove_all_cars();
	// Drops every car with index >= count (race grids are appended after the player).
	void truncate_cars(int count);
	void set_line(const std::vector<TrackSample> &samples, bool closed);
	void reset_progress(int car);
	void step(real dt, const ParallelFor &pf);
	// Serial fallback (tests, headless tools).
	void step(real dt);

	// Rewind ring: one snapshot every `rewind_stride` ticks, `rewind_capacity` kept.
	int rewind_stride = 2;
	int rewind_capacity = 600; // 10 s at 120 Hz / stride 2
	bool rewind_enabled = true;
	void clear_rewind() { ring_.clear(); }
	// Restores the state `seconds` ago (clamped to what's stored). Returns seconds actually rewound.
	real rewind(real seconds, real dt);
	real rewind_available(real dt) const { return ring_.size() * rewind_stride * dt; }
	std::vector<uint8_t> snapshot() const;
	bool restore(const std::vector<uint8_t> &data);

	// Race ordering helper: indices sorted by progress (descending).
	std::vector<int> standings() const;

private:
	void pre_step();
	void post_step(real dt);
	void update_progress(int i);

	std::vector<CarSnapshot> snaps_;
	std::deque<std::vector<uint8_t>> ring_;
};

} // namespace nt
