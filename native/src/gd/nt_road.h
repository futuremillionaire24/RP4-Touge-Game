// NTRoad: static helpers exposing the C++ spline + road mesher to GDScript.
#pragma once

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class NTRoad : public RefCounted {
	GDCLASS(NTRoad, RefCounted);

public:
	// Catmull-Rom (centripetal) resample at uniform spacing. Returns {points, tangents}.
	static Dictionary resample(const PackedVector3Array &control, bool closed, double spacing);
	// Builds meshes + collision from a sample dictionary (see nt_road.cpp for keys).
	static Dictionary build(const Dictionary &samples, const Dictionary &options);
	// Converts mesher output arrays into an ArrayMesh; `groups` receives surface -> group mapping.
	static Ref<ArrayMesh> make_mesh(const Dictionary &build_result);

protected:
	static void _bind_methods();
};

} // namespace godot
