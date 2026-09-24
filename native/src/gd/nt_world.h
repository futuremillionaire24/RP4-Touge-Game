// NTWorld: the generated open world exposed to Godot. build() once (≈1 s, call from a worker
// thread), then build_chunk() from worker threads as the player moves; all reads are const.
#pragma once

#include "sim/world/chunk_builder.h"
#include "sim/world/world.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <atomic>

namespace godot {

class NTWorld : public RefCounted {
	GDCLASS(NTWorld, RefCounted);

public:
	void build(int64_t seed);
	// Real map from a tools/mapbake blob (res://assets/map/riviera.bin). Returns "" or an error.
	String build_from_bake(const PackedByteArray &data);
	bool is_built() const { return built_.load(); }
	bool is_baked() const { return world_.baked; }
	Array routes() const;

	Dictionary build_chunk(int cx, int cz, int lod, bool collision, bool props, double prop_density) const;
	static Ref<ArrayMesh> make_mesh(const Dictionary &chunk);

	double height_at(double x, double z) const;
	Vector3 normal_at(double x, double z) const;
	int district_at(double x, double z) const;
	String district_name(int d) const;
	bool is_sea(double x, double z) const;
	Dictionary nearest_road(const Vector3 &p, double max_dist) const;
	PackedStringArray road_names() const;
	Dictionary road_samples(const String &name) const;
	Array pois() const;
	Vector2i chunk_of(const Vector3 &p) const;
	int chunks_x() const { return world_.chunks_x(); }
	int chunks_z() const { return world_.chunks_z(); }
	double chunk_size() const { return nt::World::CHUNK; }
	Rect2 bounds() const;
	Ref<Image> minimap(int size) const;
	const nt::World &native() const { return world_; }

protected:
	static void _bind_methods();

private:
	nt::World world_;
	std::atomic<bool> built_{false};
};

} // namespace godot
