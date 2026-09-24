// Vehicle simulation: raycast suspension, load-sensitive combined-slip tires with relaxation and
// heat, clutch/gearbox/differentials, turbo, aero, assists, hull collision. Pure C++, one car per
// call so all cars can be stepped in parallel against the read-only collision grid.
#pragma once

#include "collision_grid.h"
#include "vmath.h"

#include <cstdint>
#include <vector>

namespace nt {

enum DriveLayout : uint8_t { DRIVE_FR = 0, DRIVE_FF, DRIVE_MR, DRIVE_AWD, DRIVE_RR };
enum DiffType : uint8_t { DIFF_OPEN = 0, DIFF_LSD, DIFF_LOCKED };
enum EngineKind : uint8_t { ENGINE_NA = 0, ENGINE_TURBO, ENGINE_ROTARY, ENGINE_HYBRID, ENGINE_DIESEL };
enum GearboxMode : uint8_t { GEARBOX_AUTO = 0, GEARBOX_MANUAL, GEARBOX_MANUAL_CLUTCH };
enum SteerAssist : uint8_t { STEER_ASSISTED = 0, STEER_STANDARD, STEER_SIMULATION };
enum TireCompound : uint8_t { TIRE_STREET = 0, TIRE_SPORT, TIRE_SEMI_SLICK, TIRE_DRIFT, TIRE_RALLY, TIRE_SNOW, TIRE_COUNT };

enum Wheel { FL = 0, FR = 1, RL = 2, RR = 3 };

struct TireSpec {
	real grip = 1.0; // peak friction coefficient on dry asphalt
	real slide_ratio = 0.78; // sliding friction / peak friction
	real peak_slip_ratio = 0.10;
	real peak_slip_angle = 0.14; // radians
	real load_sensitivity = 0.12; // grip loss per unit of load above nominal
	real relaxation = 0.35; // meters
	real opt_temp = 85.0; // C
	real temp_window = 35.0; // C either side before grip fades
	real heat_rate = 1.0;
	real loose_bonus = 0.0; // extra grip on gravel/dirt/snow
	real snow_bonus = 0.0;
	real wet_bonus = 0.0;
	real rolling = 1.0; // rolling resistance multiplier
	static TireSpec compound(TireCompound c);
};

struct VehicleParams {
	// Mass and geometry (meters, kg). Axle positions measured from CG along -Z (front) / +Z (rear).
	real mass = 1250.0;
	real cg_height = 0.48;
	real wheelbase = 2.45;
	real weight_front = 0.53; // static fraction on front axle
	real track_front = 1.45;
	real track_rear = 1.44;
	real inertia_scale = 1.0;
	Vec3 half_extents = {0.86, 0.66, 2.15}; // body box for collision/inertia

	// Wheels / tires.
	real wheel_radius_front = 0.31;
	real wheel_radius_rear = 0.31;
	real wheel_inertia = 1.1; // kg m^2 per wheel incl. brake rotor
	real tire_width_front = 0.205;
	real tire_width_rear = 0.205;
	TireSpec tire_front;
	TireSpec tire_rear;
	real camber_front = -0.035; // radians, negative = top in
	real camber_rear = -0.02;
	real toe_front = 0.0;
	real toe_rear = 0.002;
	real tire_pressure_front = 2.2; // bar
	real tire_pressure_rear = 2.2;

	// Suspension (per corner).
	real rest_length_front = 0.34;
	real rest_length_rear = 0.34;
	real travel_front = 0.20;
	real travel_rear = 0.20;
	real spring_front = 42000.0; // N/m
	real spring_rear = 38000.0;
	real bump_front = 3200.0; // N/(m/s)
	real bump_rear = 3000.0;
	real rebound_front = 5200.0;
	real rebound_rear = 4800.0;
	real arb_front = 22000.0; // N/m of differential compression
	real arb_rear = 12000.0;
	real mount_height = 0.05; // strut top relative to CG (car local Y)

	// Steering.
	real max_steer = 0.62; // radians at the wheel
	real ackermann = 0.6;
	real steer_speed = 5.0; // rad/s at the wheel
	real caster_trail = 0.03; // self-aligning torque feel

	// Engine.
	EngineKind engine_kind = ENGINE_NA;
	Curve1D torque_curve; // rpm -> Nm at full throttle, no boost
	real idle_rpm = 900.0;
	real redline_rpm = 7600.0;
	real limiter_rpm = 7800.0;
	real engine_inertia = 0.16;
	real engine_brake = 0.018; // Nm per rpm at closed throttle
	real friction_torque = 18.0;
	real max_boost = 0.0; // bar; torque multiplier = 1 + boost * boost_gain
	real boost_gain = 0.8;
	real spool_rpm = 3200.0; // rpm where turbo produces full boost
	real spool_rate = 2.5; // 1/s
	int cylinders = 4;
	real hybrid_boost_nm = 0.0; // electric assist torque at low rpm

	// Transmission.
	int gear_count = 5;
	real gear_ratios[8] = {3.59, 2.06, 1.44, 1.10, 0.85, 0.72, 0.62, 0.55};
	real reverse_ratio = 3.4;
	real final_drive = 4.3;
	real shift_time = 0.16;
	real clutch_torque = 520.0; // Nm capacity
	real drivetrain_efficiency = 0.88;

	// Driveline.
	DriveLayout layout = DRIVE_FR;
	DiffType diff_front = DIFF_OPEN;
	DiffType diff_rear = DIFF_LSD;
	real lsd_accel = 0.45; // locking fraction of input torque on power
	real lsd_decel = 0.25; // on lift / engine braking
	real lsd_preload = 90.0; // Nm
	real awd_front_split = 0.40; // torque fraction to the front on AWD
	real center_lock = 0.35;

	// Brakes.
	real brake_torque = 2800.0; // Nm total at the pedal's max
	real brake_bias = 0.64; // front fraction
	real handbrake_torque = 2400.0;

	// Aero.
	real drag_area = 0.66; // Cd * A
	real lift_front = 0.05; // Cl * A (positive = downforce)
	real lift_rear = 0.08;
	real top_speed_limiter = 0.0; // m/s, 0 = none
};

struct VehicleInput {
	real steer = 0.0; // -1 left .. 1 right
	real throttle = 0.0; // 0..1
	real brake = 0.0; // 0..1
	real handbrake = 0.0; // 0..1
	real clutch = 0.0; // 0..1 pedal (1 = fully disengaged)
	bool shift_up = false; // edge-triggered
	bool shift_down = false;
	bool reverse_request = false; // hold brake at standstill in auto to engage reverse
};

struct AssistSettings {
	bool abs = true;
	bool tcs = true;
	bool stm = true;
	SteerAssist steering = STEER_STANDARD;
	GearboxMode gearbox = GEARBOX_AUTO;
	real countersteer = 0.5; // 0..1
	bool mechanical_damage = false;
};

struct WheelState {
	real omega = 0.0; // rad/s
	real spin = 0.0; // accumulated angle for rendering
	real compression = 0.0; // meters
	real compression_vel = 0.0;
	real steer = 0.0;
	bool contact = false;
	Vec3 contact_point;
	Vec3 contact_normal = {0, 1, 0};
	int surface = SURF_ASPHALT;
	real load = 0.0; // N
	real slip_ratio = 0.0;
	real slip_angle = 0.0; // relaxed
	real slip_speed = 0.0; // m/s of sliding at the patch
	real temp = 40.0;
	real fx = 0.0, fy = 0.0;
	real drive_torque = 0.0;
	real brake_torque = 0.0;
	real grip_used = 0.0; // 0..>1 fraction of available friction
	real puddle = 0.0;
	real wear = 0.0; // 0 new .. 1 worn
	real bump = 0.0; // filtered surface bump offset (m)
};

struct CollisionEvent {
	Vec3 point;
	Vec3 normal;
	real impulse = 0.0; // N s
	int surface = SURF_WALL;
	int other_vehicle = -1;
};

struct DamageState {
	real front = 0, rear = 0, left = 0, right = 0; // accumulated 0..1
	// Recent dents in car-local space for the deformation shader (ring buffer).
	static constexpr int MAX_DENTS = 8;
	Vec3 dent_pos[MAX_DENTS];
	real dent_depth[MAX_DENTS] = {};
	int dent_head = 0;
};

struct VehicleState {
	Vec3 pos;
	Quat rot;
	Vec3 vel;
	Vec3 ang_vel; // world space
	WheelState wheels[4];

	real engine_rpm = 900.0;
	real engine_torque_out = 0.0;
	real boost = 0.0;
	real throttle_applied = 0.0;
	real brake_applied = 0.0;
	real clutch_engagement = 1.0;
	int gear = 1; // -1 reverse, 0 neutral, 1..n
	real shift_timer = 0.0;
	int pending_gear = 1;
	bool limiter_hit = false;
	real limiter_timer = 0.0;
	real steer_input_filtered = 0.0;
	real steer_angle = 0.0;
	bool abs_active = false, tcs_active = false, stm_active = false;
	real auto_shift_cooldown = 0.0;
	real lift_timer = 0.0; // seconds since throttle lifted at high rpm (backfire)
	real drift_angle = 0.0; // signed radians between heading and velocity
	real slipstream = 0.0; // 0..1 drag reduction applied this tick
	real airborne_time = 0.0;
	real distance = 0.0; // odometer (m)
	real wetness = 0.0; // global weather input
	real ambient_temp = 20.0;
	DamageState damage;
	int collision_count = 0;
	static constexpr int MAX_EVENTS = 8;
	CollisionEvent events[MAX_EVENTS];

	real speed() const { return vel.length(); }
	real forward_speed() const { return vel.dot(rot.forward()); }
};

struct VehicleDerived {
	Vec3 inertia; // body-space principal inertia (x pitch, y yaw, z roll)
	Vec3 inv_inertia;
	Vec3 mounts[4]; // body-space suspension top positions
	real axle_front_z, axle_rear_z;
	real static_load[4];
	int driven_mask; // bit per wheel
	real max_torque; // peak engine torque incl. boost
};

// One car: params + state + per-car integration. Collisions against other cars are resolved by
// the world after the parallel phase (see resolve_vehicle_pair).
class Vehicle {
public:
	VehicleParams params;
	AssistSettings assists;
	VehicleState state;
	VehicleInput input;
	VehicleDerived derived;
	bool frozen = false; // excluded from simulation (menus, replays)

	void configure(const VehicleParams &p);
	void reset(const Vec3 &pos, const Quat &rot, real speed = 0.0);
	// Advances the car by dt (one physics tick); internally substepped.
	void step(const CollisionGrid &world, real dt);

	// Hull spheres in body space: used for static and car-car collision.
	static constexpr int HULL_SPHERES = 10;
	void hull_sphere(int i, Vec3 &local_center, real &radius) const;
	Vec3 world_point(const Vec3 &local) const { return state.pos + state.rot.rotate(local); }
	Vec3 point_velocity(const Vec3 &world_p) const { return state.vel + state.ang_vel.cross(world_p - state.pos); }
	void apply_impulse(const Vec3 &impulse, const Vec3 &world_p);
	real inverse_mass_at(const Vec3 &world_p, const Vec3 &dir) const;
	void add_collision_event(const CollisionEvent &e);
	void add_dent(const Vec3 &world_p, real impulse);

	real gear_ratio(int gear) const;
	real steer_range(real speed) const; // fraction of max_steer the stick reaches at this speed
	real engine_torque_at(real rpm, real throttle, real boost) const;
	real wheel_speed_kmh() const;

	// Serialization for rewind (plain memory copy of state).
	void save_state(std::vector<uint8_t> &out) const;
	bool load_state(const uint8_t *data, size_t size, size_t &offset);

private:
	void substep(const CollisionGrid &world, real dt);
	void update_inputs(real dt);
	void update_gearbox(real dt);
	void solve_static_collisions(const CollisionGrid &world);
	real tire_temp_factor(const WheelState &w, const TireSpec &t) const;
};

// Car vs car impulse resolution. Returns true if they touched.
bool resolve_vehicle_pair(Vehicle &a, int ia, Vehicle &b, int ib);

// Tire force helper (exposed for tests and the PI benchmark). Returns normalized force magnitude
// (fraction of mu * Fz) for combined normalized slip rho.
real tire_curve(real rho, real slide_ratio);

} // namespace nt
