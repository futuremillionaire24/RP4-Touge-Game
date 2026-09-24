// NTSim: Godot node that owns the simulation world and steps it on the WorkerThreadPool every
// physics tick. GDScript drives inputs and reads transforms/telemetry; nothing hot runs in script.
#pragma once

#include "sim/world_sim.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include <functional>
#include <vector>

namespace godot {

class NTSim : public Node {
	GDCLASS(NTSim, Node);

public:
	static constexpr int WHEEL_STRIDE = 16;

	NTSim();
	~NTSim() override;

	void _physics_process(double delta) override;
	void _ready() override;

	// World settings.
	void set_running(bool v) { running_ = v; }
	bool is_running() const { return running_; }
	void set_wetness(double v) { world_.wetness = v; }
	double get_wetness() const { return world_.wetness; }
	void set_ambient_temp(double v) { world_.ambient_temp = v; }
	double get_ambient_temp() const { return world_.ambient_temp; }
	void set_parallel(bool v) { parallel_ = v; }
	bool is_parallel() const { return parallel_; }
	void step(double delta);

	// Cars.
	int add_car(const String &key, const Dictionary &overrides, bool ai, int64_t seed);
	void clear_cars();
	void truncate_cars(int count);
	int car_count() const { return (int)world_.cars.size(); }
	void reset_car(int id, const Transform3D &xform, double speed);
	void set_frozen(int id, bool frozen);
	void set_assists(int id, const Dictionary &a);
	void set_input(int id, double steer, double throttle, double brake, double handbrake, double clutch);
	void shift(int id, int direction);
	void set_reverse_request(int id, bool v);
	void apply_overrides(int id, const Dictionary &overrides);
	Transform3D get_transform(int id) const;
	Vector3 get_velocity(int id) const;
	Vector3 get_angular_velocity(int id) const;
	PackedFloat32Array get_wheel_data(int id) const;
	Dictionary get_telemetry(int id) const;
	Dictionary get_car_spec(int id) const;
	Array pop_events(int id);
	PackedFloat32Array get_dents(int id) const;

	// Static collision.
	bool set_collision_chunk(int64_t chunk_id, const PackedVector3Array &faces, const PackedByteArray &surfaces, const PackedByteArray &flags);
	void remove_collision_chunk(int64_t chunk_id);
	void clear_collision();
	int collision_triangle_count() const { return world_.grid.triangle_count(); }
	Dictionary raycast(const Vector3 &from, const Vector3 &to, int mask) const;
	double ground_height(const Vector3 &pos, double max_drop) const;

	// Racing line + AI.
	void set_racing_line(const PackedVector3Array &centers, const PackedVector3Array &normals, const PackedFloat32Array &width_left,
			const PackedFloat32Array &width_right, bool closed);
	void clear_racing_line();
	PackedVector3Array get_racing_line_points() const;
	PackedFloat32Array get_speed_profile(int id) const;
	double get_racing_line_length() const { return world_.has_line ? world_.line.length() : 0.0; }
	void set_ai_enabled(int id, bool v);
	void set_ai_difficulty(int id, int difficulty);
	void set_ai_personality(int id, const Dictionary &p);
	void set_ai_speed_scale(int id, double s);
	bool is_ai(int id) const;
	void set_ai(int id, bool v);
	PackedInt32Array standings() const;
	void reset_progress(int id);

	// Rewind / snapshots.
	void set_rewind_enabled(bool v) { world_.rewind_enabled = v; }
	bool is_rewind_enabled() const { return world_.rewind_enabled; }
	double rewind(double seconds);
	double rewind_available() const;
	void clear_rewind() { world_.clear_rewind(); }
	PackedByteArray snapshot() const;
	bool restore(const PackedByteArray &data);

	// Static helpers for garage / PI.
	static Dictionary benchmark(const String &key, const Dictionary &overrides);
	static Dictionary car_params(const String &key, const Dictionary &overrides);
	static Dictionary engine_audio_profile(const String &key);
	static PackedStringArray car_keys();

	// Traffic (requires set_world).
	void set_world(const Ref<class NTWorld> &world);
	void set_traffic_enabled(bool v);
	bool is_traffic_enabled() const { return world_.traffic_enabled; }
	void set_traffic_density(double d) { world_.traffic.density = d; }
	double get_traffic_density() const { return world_.traffic.density; }
	void clear_traffic();
	// MultiMesh buffer (TRANSFORM_3D + custom data = 16 floats/instance) for one traffic model.
	PackedFloat32Array traffic_buffer(int model) const;
	int traffic_active_count() const;
	Array pop_near_misses();
	double get_sim_time() const { return world_.time_s; }

	uint64_t get_tick() const { return world_.tick; }
	double get_step_usec() const { return step_usec_; }

protected:
	static void _bind_methods();

private:
	bool valid(int id) const { return id >= 0 && id < (int)world_.cars.size(); }
	void run_group(uint32_t index);

	nt::WorldSim world_;
	Ref<RefCounted> world_ref_; // keeps the NTWorld alive while traffic reads it
	bool running_ = true;
	bool parallel_ = true;
	double step_usec_ = 0.0;
	std::vector<std::vector<Dictionary>> pending_events_;
	const std::function<void(int)> *group_body_ = nullptr;
	int group_count_ = 0;
};

} // namespace godot
