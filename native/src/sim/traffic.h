// Ambient traffic: kinematic cars that drive on the left (Japan) along world roads, follow the
// car ahead (IDM), stop at red lights in the city grid, pick new roads at junctions, and get
// knocked about (then fade) when the player hits them. Designed for 50-80 cars at ~0.1 ms.
#pragma once

#include "rng.h"
#include "vmath.h"
#include "world/world.h"

#include <vector>

namespace nt {

enum TrafficModel : uint8_t { TM_KEI = 0, TM_SEDAN, TM_TAXI, TM_VAN, TM_TRUCK, TM_BUS, TM_COUNT };

struct TrafficCar {
	int road = -1;
	real s = 0.0; // arc length along the road
	int dir = 1; // +1 along the road, -1 against it
	real lane = -1.8; // lateral offset (negative = left of travel direction)
	real speed = 0.0;
	real desired = 12.0;
	uint8_t model = TM_SEDAN;
	float color = 0.0f;
	Vec3 pos;
	Quat rot;
	Vec3 half = {0.85, 0.75, 2.2};
	// Knocked loose by a collision: free 2D slide with friction until despawned.
	bool loose = false;
	Vec3 vel;
	real yaw_rate = 0.0;
	real loose_time = 0.0;
	bool active = false;
	int near_miss_cooldown = 0;
};

struct NearMiss {
	int traffic = -1;
	real clearance = 0.0;
	real rel_speed = 0.0;
};

class TrafficSystem {
public:
	const World *world = nullptr;
	std::vector<TrafficCar> cars;
	int target_count = 50;
	real spawn_min = 140.0, spawn_max = 330.0, despawn = 420.0;
	real density = 1.0;

	void init(const World *w, int max_cars, uint64_t seed);
	// `obstacles` are the simulated cars (player + rivals): traffic brakes for them like for any
	// other car in its lane.
	struct Obstacle {
		Vec3 pos, vel;
		real half_length;
	};
	void step(real dt, const Vec3 &focus, real time_s, const std::vector<Obstacle> &obstacles);
	// Player/rival interaction. Returns true on contact; fills the impulse applied to the car.
	bool collide(Vec3 &car_pos, Vec3 &car_vel, real car_mass, real car_radius, Vec3 &impulse_out, Vec3 &point_out);
	// Near-miss scan for the player (call once per tick).
	int near_misses(const Vec3 &pos, const Vec3 &vel, const Vec3 &fwd, NearMiss *out, int max_out);
	// Signal state for a city junction at world time t: true = north-south green.
	static bool ns_green(real t, int junction_index);

private:
	void spawn_one(const Vec3 &focus);
	void place(TrafficCar &c);
	bool pick_next_road(TrafficCar &c);
	real gap_ahead(int idx, real &leader_speed, const std::vector<Obstacle> &obstacles) const;
	real signal_stop_distance(const TrafficCar &c, real time_s) const;
	std::vector<int> spawnable_; // roads traffic may use
	Rng rng_;
};

} // namespace nt
