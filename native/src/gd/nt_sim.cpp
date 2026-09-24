#include "nt_sim.h"

#include "nt_world.h"
#include "sim/benchmark.h"
#include "sim/roster.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstring>

using namespace godot;

static inline Vector3 to_gd(const nt::Vec3 &v) { return Vector3((real_t)v.x, (real_t)v.y, (real_t)v.z); }
static inline nt::Vec3 to_nt(const Vector3 &v) { return nt::Vec3(v.x, v.y, v.z); }
static inline Quaternion to_gd(const nt::Quat &q) { return Quaternion((real_t)q.x, (real_t)q.y, (real_t)q.z, (real_t)q.w); }
static inline nt::Quat to_nt(const Quaternion &q) { return nt::Quat(q.x, q.y, q.z, q.w); }

static nt::VehicleParams params_for(const String &key, const Dictionary &overrides) {
	int id = nt::car_id_from_key(key.utf8().get_data());
	if (id < 0) {
		UtilityFunctions::push_error("NTSim: unknown car key ", key);
		id = 0;
	}
	nt::VehicleParams p = nt::make_car_params(id);
	Array keys = overrides.keys();
	for (int i = 0; i < keys.size(); ++i) {
		String k = keys[i];
		double v = overrides[keys[i]];
		if (!nt::apply_override(p, k.utf8().get_data(), v)) UtilityFunctions::push_warning("NTSim: unknown override ", k);
	}
	return p;
}

NTSim::NTSim() {}
NTSim::~NTSim() {}

void NTSim::_ready() {
	if (Engine::get_singleton()->is_editor_hint()) set_physics_process(false);
}

void NTSim::_physics_process(double delta) {
	if (!running_) return;
	step(delta);
}

void NTSim::run_group(uint32_t index) {
	if (group_body_ && (int)index < group_count_) (*group_body_)((int)index);
}

void NTSim::step(double delta) {
	uint64_t t0 = Time::get_singleton()->get_ticks_usec();
	if (parallel_ && world_.cars.size() > 1) {
		world_.step(delta, [this](int count, const std::function<void(int)> &body) {
			group_body_ = &body;
			group_count_ = count;
			WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
			int64_t task = pool->add_group_task(callable_mp(this, &NTSim::run_group), count, -1, true, "NTSim step");
			pool->wait_for_group_task_completion(task);
			group_body_ = nullptr;
		});
	} else {
		world_.step(delta);
	}
	// Collect collision events for script (the sim overwrites them every tick).
	if (pending_events_.size() != world_.cars.size()) pending_events_.resize(world_.cars.size());
	for (size_t i = 0; i < world_.cars.size(); ++i) {
		const nt::VehicleState &s = world_.cars[i].state;
		// Input edges are consumed once per tick.
		world_.cars[i].input.shift_up = false;
		world_.cars[i].input.shift_down = false;
		for (int k = 0; k < s.collision_count; ++k) {
			const nt::CollisionEvent &e = s.events[k];
			Dictionary d;
			d["impulse"] = e.impulse;
			d["position"] = to_gd(e.point);
			d["normal"] = to_gd(e.normal);
			d["surface"] = e.surface;
			d["other"] = e.other_vehicle;
			if (pending_events_[i].size() < 32) pending_events_[i].push_back(d);
		}
	}
	step_usec_ = (double)(Time::get_singleton()->get_ticks_usec() - t0);
}

int NTSim::add_car(const String &key, const Dictionary &overrides, bool ai, int64_t seed) {
	int id = world_.add_car(params_for(key, overrides), ai, (uint64_t)seed);
	pending_events_.resize(world_.cars.size());
	return id;
}

void NTSim::clear_cars() {
	world_.remove_all_cars();
	pending_events_.clear();
}

void NTSim::truncate_cars(int count) {
	world_.truncate_cars(count);
	if ((int)pending_events_.size() > count) pending_events_.resize(std::max(0, count));
}

void NTSim::reset_car(int id, const Transform3D &xform, double speed) {
	ERR_FAIL_COND(!valid(id));
	nt::Vehicle &v = world_.cars[id];
	v.reset(to_nt(xform.origin), to_nt(xform.basis.get_rotation_quaternion()), speed);
	world_.reset_progress(id);
	if (world_.has_line) world_.ai[id].set_line(&world_.line, v);
	world_.ai[id].clear_respawn();
}

void NTSim::set_frozen(int id, bool frozen) {
	ERR_FAIL_COND(!valid(id));
	world_.cars[id].frozen = frozen;
}

void NTSim::set_assists(int id, const Dictionary &a) {
	ERR_FAIL_COND(!valid(id));
	nt::AssistSettings &s = world_.cars[id].assists;
	if (a.has("abs")) s.abs = a["abs"];
	if (a.has("tcs")) s.tcs = a["tcs"];
	if (a.has("stm")) s.stm = a["stm"];
	if (a.has("steering")) s.steering = (nt::SteerAssist)(int)a["steering"];
	if (a.has("gearbox")) s.gearbox = (nt::GearboxMode)(int)a["gearbox"];
	if (a.has("countersteer")) s.countersteer = (double)a["countersteer"];
	if (a.has("mechanical_damage")) s.mechanical_damage = a["mechanical_damage"];
}

void NTSim::set_input(int id, double steer, double throttle, double brake, double handbrake, double clutch) {
	ERR_FAIL_COND(!valid(id));
	nt::VehicleInput &in = world_.cars[id].input;
	in.steer = nt::clampr(steer, -1.0, 1.0);
	in.throttle = nt::saturate(throttle);
	in.brake = nt::saturate(brake);
	in.handbrake = nt::saturate(handbrake);
	in.clutch = nt::saturate(clutch);
}

void NTSim::shift(int id, int direction) {
	ERR_FAIL_COND(!valid(id));
	if (direction > 0) world_.cars[id].input.shift_up = true;
	else if (direction < 0) world_.cars[id].input.shift_down = true;
}

void NTSim::set_reverse_request(int id, bool v) {
	ERR_FAIL_COND(!valid(id));
	world_.cars[id].input.reverse_request = v;
}

void NTSim::apply_overrides(int id, const Dictionary &overrides) {
	ERR_FAIL_COND(!valid(id));
	nt::Vehicle &v = world_.cars[id];
	nt::VehicleParams p = v.params;
	Array keys = overrides.keys();
	for (int i = 0; i < keys.size(); ++i) {
		String k = keys[i];
		nt::apply_override(p, k.utf8().get_data(), (double)overrides[keys[i]]);
	}
	nt::VehicleState keep = v.state;
	v.configure(p);
	v.state = keep;
	if (world_.has_line) world_.ai[id].set_line(&world_.line, v);
}

Transform3D NTSim::get_transform(int id) const {
	ERR_FAIL_COND_V(!valid(id), Transform3D());
	const nt::VehicleState &s = world_.cars[id].state;
	return Transform3D(Basis(to_gd(s.rot)), to_gd(s.pos));
}

Vector3 NTSim::get_velocity(int id) const {
	ERR_FAIL_COND_V(!valid(id), Vector3());
	return to_gd(world_.cars[id].state.vel);
}

Vector3 NTSim::get_angular_velocity(int id) const {
	ERR_FAIL_COND_V(!valid(id), Vector3());
	return to_gd(world_.cars[id].state.ang_vel);
}

// Per wheel (WHEEL_STRIDE floats): local center xyz, steer, spin, radius, contact, slip_speed,
// slip_ratio, slip_angle, surface, load_kN, temp_C, grip_used, puddle, compression.
PackedFloat32Array NTSim::get_wheel_data(int id) const {
	PackedFloat32Array out;
	ERR_FAIL_COND_V(!valid(id), out);
	const nt::Vehicle &v = world_.cars[id];
	out.resize(4 * WHEEL_STRIDE);
	float *w = out.ptrw();
	for (int i = 0; i < 4; ++i) {
		const nt::WheelState &ws = v.state.wheels[i];
		bool front = i < 2;
		double R = front ? v.params.wheel_radius_front : v.params.wheel_radius_rear;
		double rest = front ? v.params.rest_length_front : v.params.rest_length_rear;
		const nt::Vec3 &m = v.derived.mounts[i];
		double drop = rest - ws.compression; // strut top to wheel center
		float *o = w + i * WHEEL_STRIDE;
		o[0] = (float)m.x;
		o[1] = (float)(m.y - drop);
		o[2] = (float)m.z;
		o[3] = (float)ws.steer;
		o[4] = (float)std::fmod(ws.spin, nt::TAU);
		o[5] = (float)R;
		o[6] = ws.contact ? 1.f : 0.f;
		o[7] = (float)ws.slip_speed;
		o[8] = (float)ws.slip_ratio;
		o[9] = (float)ws.slip_angle;
		o[10] = (float)ws.surface;
		o[11] = (float)(ws.load / 1000.0);
		o[12] = (float)ws.temp;
		o[13] = (float)ws.grip_used;
		o[14] = (float)ws.puddle;
		o[15] = (float)ws.compression;
	}
	return out;
}

Dictionary NTSim::get_telemetry(int id) const {
	Dictionary d;
	ERR_FAIL_COND_V(!valid(id), d);
	const nt::Vehicle &v = world_.cars[id];
	const nt::VehicleState &s = v.state;
	d["speed_kmh"] = s.forward_speed() * 3.6;
	d["speed"] = s.speed();
	d["rpm"] = s.engine_rpm;
	d["gear"] = s.gear;
	d["boost"] = s.boost;
	d["max_boost"] = v.params.max_boost;
	d["throttle"] = s.throttle_applied;
	d["brake"] = s.brake_applied;
	d["clutch"] = s.clutch_engagement;
	d["steer"] = s.steer_input_filtered;
	d["drift_angle"] = s.drift_angle;
	d["abs"] = s.abs_active;
	d["tcs"] = s.tcs_active;
	d["stm"] = s.stm_active;
	d["limiter"] = s.limiter_hit;
	d["shifting"] = s.shift_timer > 0.0;
	d["airborne"] = s.airborne_time;
	d["odometer"] = s.distance;
	d["slipstream"] = s.slipstream;
	d["engine_torque"] = s.engine_torque_out;
	d["gear_ratio"] = v.gear_ratio(s.gear) * v.params.final_drive;
	d["damage"] = Vector4((real_t)s.damage.front, (real_t)s.damage.rear, (real_t)s.damage.left, (real_t)s.damage.right);
	const nt::RaceProgress &p = world_.progress[id];
	d["lap"] = p.lap;
	d["line_index"] = p.line_index;
	d["line_distance"] = p.line_distance;
	d["progress"] = p.total;
	d["line_offset"] = p.line_offset;
	d["wrong_way"] = p.wrong_way;
	d["respawns"] = p.respawn_count;
	return d;
}

Dictionary NTSim::get_car_spec(int id) const {
	Dictionary d;
	ERR_FAIL_COND_V(!valid(id), d);
	const nt::VehicleParams &p = world_.cars[id].params;
	d["mass"] = p.mass;
	d["idle_rpm"] = p.idle_rpm;
	d["redline_rpm"] = p.redline_rpm;
	d["limiter_rpm"] = p.limiter_rpm;
	d["gear_count"] = p.gear_count;
	d["max_boost"] = p.max_boost;
	d["wheelbase"] = p.wheelbase;
	d["half_extents"] = to_gd(p.half_extents);
	d["cg_height"] = p.cg_height;
	d["layout"] = (int)p.layout;
	d["engine_kind"] = (int)p.engine_kind;
	d["max_steer"] = p.max_steer;
	d["max_torque"] = world_.cars[id].derived.max_torque;
	return d;
}

Array NTSim::pop_events(int id) {
	Array out;
	ERR_FAIL_COND_V(!valid(id), out);
	if (id < (int)pending_events_.size()) {
		for (const Dictionary &d : pending_events_[id]) out.push_back(d);
		pending_events_[id].clear();
	}
	return out;
}

// 4 floats per dent: local xyz + depth (m).
PackedFloat32Array NTSim::get_dents(int id) const {
	PackedFloat32Array out;
	ERR_FAIL_COND_V(!valid(id), out);
	const nt::DamageState &d = world_.cars[id].state.damage;
	out.resize(nt::DamageState::MAX_DENTS * 4);
	float *w = out.ptrw();
	for (int i = 0; i < nt::DamageState::MAX_DENTS; ++i) {
		w[i * 4 + 0] = (float)d.dent_pos[i].x;
		w[i * 4 + 1] = (float)d.dent_pos[i].y;
		w[i * 4 + 2] = (float)d.dent_pos[i].z;
		w[i * 4 + 3] = (float)d.dent_depth[i];
	}
	return out;
}

bool NTSim::set_collision_chunk(int64_t chunk_id, const PackedVector3Array &faces, const PackedByteArray &surfaces, const PackedByteArray &flags) {
	int tris = faces.size() / 3;
	ERR_FAIL_COND_V_MSG(surfaces.size() != 0 && surfaces.size() != tris, false, "surfaces must have one entry per triangle");
	ERR_FAIL_COND_V_MSG(flags.size() != 0 && flags.size() != tris, false, "flags must have one entry per triangle");
	world_.grid.remove_chunk(chunk_id);
	std::vector<float> pos((size_t)tris * 9);
	const Vector3 *f = faces.ptr();
	for (int i = 0; i < tris * 3; ++i) {
		pos[i * 3 + 0] = (float)f[i].x;
		pos[i * 3 + 1] = (float)f[i].y;
		pos[i * 3 + 2] = (float)f[i].z;
	}
	return world_.grid.add_chunk(chunk_id, pos.data(), surfaces.size() ? surfaces.ptr() : nullptr, flags.size() ? flags.ptr() : nullptr, tris);
}

void NTSim::remove_collision_chunk(int64_t chunk_id) { world_.grid.remove_chunk(chunk_id); }
void NTSim::clear_collision() { world_.grid.clear(); }

Dictionary NTSim::raycast(const Vector3 &from, const Vector3 &to, int mask) const {
	Dictionary d;
	Vector3 dir = to - from;
	double len = dir.length();
	if (len < 1e-6) return d;
	nt::RayHit h = world_.grid.raycast(to_nt(from), to_nt(dir / len), len, (uint8_t)mask);
	if (!h.hit) return d;
	d["position"] = to_gd(h.point);
	d["normal"] = to_gd(h.normal);
	d["surface"] = h.surface;
	d["distance"] = h.t;
	return d;
}

double NTSim::ground_height(const Vector3 &pos, double max_drop) const {
	return world_.grid.ground_height(to_nt(pos), max_drop);
}

void NTSim::set_racing_line(const PackedVector3Array &centers, const PackedVector3Array &normals, const PackedFloat32Array &wl,
		const PackedFloat32Array &wr, bool closed) {
	int n = centers.size();
	ERR_FAIL_COND(n < 4);
	std::vector<nt::TrackSample> samples(n);
	for (int i = 0; i < n; ++i) {
		nt::TrackSample &s = samples[i];
		s.center = to_nt(centers[i]);
		int a = closed ? (i - 1 + n) % n : std::max(i - 1, 0);
		int b = closed ? (i + 1) % n : std::min(i + 1, n - 1);
		s.tangent = (to_nt(centers[b]) - to_nt(centers[a])).normalized();
		s.normal = i < normals.size() ? to_nt(normals[i]).normalized() : nt::Vec3(0, 1, 0);
		s.half_width_left = i < wl.size() ? wl[i] : 4.0;
		s.half_width_right = i < wr.size() ? wr[i] : 4.0;
	}
	world_.set_line(samples, closed);
}

void NTSim::clear_racing_line() {
	world_.has_line = false;
	for (size_t i = 0; i < world_.cars.size(); ++i) world_.ai[i].set_line(nullptr, world_.cars[i]);
}

PackedVector3Array NTSim::get_racing_line_points() const {
	PackedVector3Array out;
	if (!world_.has_line) return out;
	out.resize(world_.line.size());
	for (int i = 0; i < world_.line.size(); ++i) out.set(i, to_gd(world_.line.point(i)));
	return out;
}

PackedFloat32Array NTSim::get_speed_profile(int id) const {
	PackedFloat32Array out;
	ERR_FAIL_COND_V(!valid(id), out);
	const std::vector<double> &p = world_.ai[id].profile();
	out.resize((int64_t)p.size());
	for (size_t i = 0; i < p.size(); ++i) out.set((int64_t)i, (float)p[i]);
	return out;
}

void NTSim::set_ai_enabled(int id, bool v) {
	ERR_FAIL_COND(!valid(id));
	world_.ai[id].enabled = v;
}

void NTSim::set_ai_difficulty(int id, int difficulty) {
	ERR_FAIL_COND(!valid(id));
	world_.ai[id].personality = nt::difficulty_personality(difficulty, (uint64_t)id * 131 + 7);
}

void NTSim::set_ai_personality(int id, const Dictionary &p) {
	ERR_FAIL_COND(!valid(id));
	nt::Personality &q = world_.ai[id].personality;
	if (p.has("skill")) q.skill = (double)p["skill"];
	if (p.has("aggression")) q.aggression = (double)p["aggression"];
	if (p.has("consistency")) q.consistency = (double)p["consistency"];
	if (p.has("mistake_rate")) q.mistake_rate = (double)p["mistake_rate"];
	if (p.has("patience")) q.patience = (double)p["patience"];
	if (p.has("drift_style")) q.drift_style = (bool)p["drift_style"];
}

void NTSim::set_ai_speed_scale(int id, double s) {
	ERR_FAIL_COND(!valid(id));
	world_.ai[id].speed_scale = s;
}

bool NTSim::is_ai(int id) const {
	ERR_FAIL_COND_V(!valid(id), false);
	return world_.is_ai[id] != 0;
}

void NTSim::set_ai(int id, bool v) {
	ERR_FAIL_COND(!valid(id));
	world_.is_ai[id] = v ? 1 : 0;
}

PackedInt32Array NTSim::standings() const {
	PackedInt32Array out;
	std::vector<int> s = world_.standings();
	out.resize((int64_t)s.size());
	for (size_t i = 0; i < s.size(); ++i) out.set((int64_t)i, s[i]);
	return out;
}

void NTSim::reset_progress(int id) {
	ERR_FAIL_COND(!valid(id));
	world_.reset_progress(id);
}

double NTSim::rewind(double seconds) {
	double dt = 1.0 / (double)Engine::get_singleton()->get_physics_ticks_per_second();
	return world_.rewind(seconds, dt);
}

double NTSim::rewind_available() const {
	double dt = 1.0 / (double)Engine::get_singleton()->get_physics_ticks_per_second();
	return world_.rewind_available(dt);
}

PackedByteArray NTSim::snapshot() const {
	std::vector<uint8_t> s = world_.snapshot();
	PackedByteArray out;
	out.resize((int64_t)s.size());
	if (!s.empty()) std::memcpy(out.ptrw(), s.data(), s.size());
	return out;
}

bool NTSim::restore(const PackedByteArray &data) {
	std::vector<uint8_t> s((size_t)data.size());
	if (!s.empty()) std::memcpy(s.data(), data.ptr(), s.size());
	return world_.restore(s);
}

void NTSim::set_world(const Ref<NTWorld> &world) {
	world_ref_ = world;
	if (world.is_valid() && world->is_built()) world_.traffic.init(&world->native(), 90, 0x7A11C);
}

void NTSim::set_traffic_enabled(bool v) {
	world_.traffic_enabled = v && world_.traffic.world != nullptr;
	if (!v) clear_traffic();
}

void NTSim::clear_traffic() {
	for (nt::TrafficCar &c : world_.traffic.cars) c.active = false;
}

PackedFloat32Array NTSim::traffic_buffer(int model) const {
	PackedFloat32Array out;
	int count = 0;
	for (const nt::TrafficCar &c : world_.traffic.cars)
		if (c.active && c.model == model) count++;
	out.resize(count * 16);
	float *w = out.ptrw();
	int k = 0;
	for (const nt::TrafficCar &c : world_.traffic.cars) {
		if (!c.active || c.model != model) continue;
		Basis b(to_gd(c.rot));
		float *o = w + k * 16;
		// Godot MultiMesh 3D layout: row-major 3x4 (basis rows + origin column), then custom.
		o[0] = b.rows[0].x; o[1] = b.rows[0].y; o[2] = b.rows[0].z; o[3] = (float)c.pos.x;
		o[4] = b.rows[1].x; o[5] = b.rows[1].y; o[6] = b.rows[1].z; o[7] = (float)c.pos.y;
		o[8] = b.rows[2].x; o[9] = b.rows[2].y; o[10] = b.rows[2].z; o[11] = (float)c.pos.z;
		o[12] = c.color; o[13] = c.loose ? 1.0f : 0.0f; o[14] = (float)std::min(c.speed / 30.0, 1.0); o[15] = 0.0f;
		k++;
	}
	return out;
}

int NTSim::traffic_active_count() const {
	int n = 0;
	for (const nt::TrafficCar &c : world_.traffic.cars) n += c.active ? 1 : 0;
	return n;
}

Array NTSim::pop_near_misses() {
	Array out;
	for (const nt::NearMiss &m : world_.near_miss_queue) {
		Dictionary d;
		d["clearance"] = m.clearance;
		d["rel_speed"] = m.rel_speed;
		out.push_back(d);
	}
	world_.near_miss_queue.clear();
	return out;
}

Dictionary NTSim::benchmark(const String &key, const Dictionary &overrides) {
	nt::BenchmarkResult r = nt::run_benchmark(params_for(key, overrides));
	Dictionary d;
	d["t_0_100"] = r.t_0_100;
	d["t_0_200"] = r.t_0_200;
	d["top_speed"] = r.top_speed;
	d["brake_100_0"] = r.brake_100_0;
	d["lateral_g"] = r.lateral_g;
	d["quarter_mile"] = r.quarter_mile;
	d["power_kw"] = r.power_kw;
	d["weight_kg"] = r.weight_kg;
	d["pi"] = r.pi;
	d["pi_class"] = r.pi_class;
	d["pi_class_name"] = String(nt::pi_class_name(r.pi_class));
	d["accel_score"] = r.accel_score;
	d["speed_score"] = r.speed_score;
	d["handling_score"] = r.handling_score;
	d["braking_score"] = r.braking_score;
	d["launch_score"] = r.launch_score;
	return d;
}

Dictionary NTSim::car_params(const String &key, const Dictionary &overrides) {
	Dictionary d;
	for (const auto &kv : nt::dump_params(params_for(key, overrides))) d[String(kv.first.c_str())] = kv.second;
	return d;
}

Dictionary NTSim::engine_audio_profile(const String &key) {
	int id = nt::car_id_from_key(key.utf8().get_data());
	nt::EngineAudioProfile a = nt::make_car_audio(id < 0 ? 0 : id);
	Dictionary d;
	d["cylinders"] = a.cylinders;
	d["rotors"] = a.rotors;
	d["vtec"] = a.vtec;
	d["crossover_rpm"] = a.crossover_rpm;
	d["straight_cut"] = a.straight_cut;
	d["exhaust_resonance"] = a.exhaust_resonance;
	d["roughness"] = a.roughness;
	d["growl"] = a.growl;
	d["turbo_whistle"] = a.turbo_whistle;
	d["diesel"] = a.diesel;
	d["hybrid"] = a.hybrid;
	d["uneven"] = a.uneven;
	return d;
}

PackedStringArray NTSim::car_keys() {
	PackedStringArray out;
	for (int i = 0; i < nt::CAR_COUNT; ++i) out.push_back(String(nt::car_key(i)));
	return out;
}

void NTSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_running", "running"), &NTSim::set_running);
	ClassDB::bind_method(D_METHOD("is_running"), &NTSim::is_running);
	ClassDB::bind_method(D_METHOD("set_wetness", "wetness"), &NTSim::set_wetness);
	ClassDB::bind_method(D_METHOD("get_wetness"), &NTSim::get_wetness);
	ClassDB::bind_method(D_METHOD("set_ambient_temp", "celsius"), &NTSim::set_ambient_temp);
	ClassDB::bind_method(D_METHOD("get_ambient_temp"), &NTSim::get_ambient_temp);
	ClassDB::bind_method(D_METHOD("set_parallel", "parallel"), &NTSim::set_parallel);
	ClassDB::bind_method(D_METHOD("is_parallel"), &NTSim::is_parallel);
	ClassDB::bind_method(D_METHOD("set_rewind_enabled", "enabled"), &NTSim::set_rewind_enabled);
	ClassDB::bind_method(D_METHOD("is_rewind_enabled"), &NTSim::is_rewind_enabled);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "running"), "set_running", "is_running");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "wetness"), "set_wetness", "get_wetness");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ambient_temp"), "set_ambient_temp", "get_ambient_temp");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "parallel"), "set_parallel", "is_parallel");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "rewind_enabled"), "set_rewind_enabled", "is_rewind_enabled");

	ClassDB::bind_method(D_METHOD("step", "delta"), &NTSim::step);
	ClassDB::bind_method(D_METHOD("add_car", "key", "overrides", "ai", "seed"), &NTSim::add_car);
	ClassDB::bind_method(D_METHOD("clear_cars"), &NTSim::clear_cars);
	ClassDB::bind_method(D_METHOD("truncate_cars", "count"), &NTSim::truncate_cars);
	ClassDB::bind_method(D_METHOD("car_count"), &NTSim::car_count);
	ClassDB::bind_method(D_METHOD("reset_car", "id", "transform", "speed"), &NTSim::reset_car);
	ClassDB::bind_method(D_METHOD("set_frozen", "id", "frozen"), &NTSim::set_frozen);
	ClassDB::bind_method(D_METHOD("set_assists", "id", "assists"), &NTSim::set_assists);
	ClassDB::bind_method(D_METHOD("set_input", "id", "steer", "throttle", "brake", "handbrake", "clutch"), &NTSim::set_input);
	ClassDB::bind_method(D_METHOD("shift", "id", "direction"), &NTSim::shift);
	ClassDB::bind_method(D_METHOD("set_reverse_request", "id", "value"), &NTSim::set_reverse_request);
	ClassDB::bind_method(D_METHOD("apply_overrides", "id", "overrides"), &NTSim::apply_overrides);
	ClassDB::bind_method(D_METHOD("get_transform", "id"), &NTSim::get_transform);
	ClassDB::bind_method(D_METHOD("get_velocity", "id"), &NTSim::get_velocity);
	ClassDB::bind_method(D_METHOD("get_angular_velocity", "id"), &NTSim::get_angular_velocity);
	ClassDB::bind_method(D_METHOD("get_wheel_data", "id"), &NTSim::get_wheel_data);
	ClassDB::bind_method(D_METHOD("get_telemetry", "id"), &NTSim::get_telemetry);
	ClassDB::bind_method(D_METHOD("get_car_spec", "id"), &NTSim::get_car_spec);
	ClassDB::bind_method(D_METHOD("pop_events", "id"), &NTSim::pop_events);
	ClassDB::bind_method(D_METHOD("get_dents", "id"), &NTSim::get_dents);

	ClassDB::bind_method(D_METHOD("set_collision_chunk", "chunk_id", "faces", "surfaces", "flags"), &NTSim::set_collision_chunk);
	ClassDB::bind_method(D_METHOD("remove_collision_chunk", "chunk_id"), &NTSim::remove_collision_chunk);
	ClassDB::bind_method(D_METHOD("clear_collision"), &NTSim::clear_collision);
	ClassDB::bind_method(D_METHOD("collision_triangle_count"), &NTSim::collision_triangle_count);
	ClassDB::bind_method(D_METHOD("raycast", "from", "to", "mask"), &NTSim::raycast, DEFVAL(3));
	ClassDB::bind_method(D_METHOD("ground_height", "position", "max_drop"), &NTSim::ground_height, DEFVAL(50.0));

	ClassDB::bind_method(D_METHOD("set_racing_line", "centers", "normals", "width_left", "width_right", "closed"), &NTSim::set_racing_line);
	ClassDB::bind_method(D_METHOD("clear_racing_line"), &NTSim::clear_racing_line);
	ClassDB::bind_method(D_METHOD("get_racing_line_points"), &NTSim::get_racing_line_points);
	ClassDB::bind_method(D_METHOD("get_racing_line_length"), &NTSim::get_racing_line_length);
	ClassDB::bind_method(D_METHOD("get_speed_profile", "id"), &NTSim::get_speed_profile);
	ClassDB::bind_method(D_METHOD("set_ai_enabled", "id", "enabled"), &NTSim::set_ai_enabled);
	ClassDB::bind_method(D_METHOD("set_ai_difficulty", "id", "difficulty"), &NTSim::set_ai_difficulty);
	ClassDB::bind_method(D_METHOD("set_ai_personality", "id", "personality"), &NTSim::set_ai_personality);
	ClassDB::bind_method(D_METHOD("set_ai_speed_scale", "id", "scale"), &NTSim::set_ai_speed_scale);
	ClassDB::bind_method(D_METHOD("is_ai", "id"), &NTSim::is_ai);
	ClassDB::bind_method(D_METHOD("set_ai", "id", "ai"), &NTSim::set_ai);
	ClassDB::bind_method(D_METHOD("standings"), &NTSim::standings);
	ClassDB::bind_method(D_METHOD("reset_progress", "id"), &NTSim::reset_progress);

	ClassDB::bind_method(D_METHOD("rewind", "seconds"), &NTSim::rewind);
	ClassDB::bind_method(D_METHOD("rewind_available"), &NTSim::rewind_available);
	ClassDB::bind_method(D_METHOD("clear_rewind"), &NTSim::clear_rewind);
	ClassDB::bind_method(D_METHOD("snapshot"), &NTSim::snapshot);
	ClassDB::bind_method(D_METHOD("restore", "data"), &NTSim::restore);
	ClassDB::bind_method(D_METHOD("set_world", "world"), &NTSim::set_world);
	ClassDB::bind_method(D_METHOD("set_traffic_enabled", "enabled"), &NTSim::set_traffic_enabled);
	ClassDB::bind_method(D_METHOD("is_traffic_enabled"), &NTSim::is_traffic_enabled);
	ClassDB::bind_method(D_METHOD("set_traffic_density", "density"), &NTSim::set_traffic_density);
	ClassDB::bind_method(D_METHOD("get_traffic_density"), &NTSim::get_traffic_density);
	ClassDB::bind_method(D_METHOD("clear_traffic"), &NTSim::clear_traffic);
	ClassDB::bind_method(D_METHOD("traffic_buffer", "model"), &NTSim::traffic_buffer);
	ClassDB::bind_method(D_METHOD("traffic_active_count"), &NTSim::traffic_active_count);
	ClassDB::bind_method(D_METHOD("pop_near_misses"), &NTSim::pop_near_misses);
	ClassDB::bind_method(D_METHOD("get_sim_time"), &NTSim::get_sim_time);
	ClassDB::bind_method(D_METHOD("get_tick"), &NTSim::get_tick);
	ClassDB::bind_method(D_METHOD("get_step_usec"), &NTSim::get_step_usec);
	ClassDB::bind_method(D_METHOD("run_group", "index"), &NTSim::run_group);

	ClassDB::bind_static_method("NTSim", D_METHOD("benchmark", "key", "overrides"), &NTSim::benchmark);
	ClassDB::bind_static_method("NTSim", D_METHOD("car_params", "key", "overrides"), &NTSim::car_params);
	ClassDB::bind_static_method("NTSim", D_METHOD("engine_audio_profile", "key"), &NTSim::engine_audio_profile);
	ClassDB::bind_static_method("NTSim", D_METHOD("car_keys"), &NTSim::car_keys);

	BIND_CONSTANT(WHEEL_STRIDE);
}
