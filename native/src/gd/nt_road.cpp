#include "nt_road.h"

#include "sim/road_mesher.h"
#include "sim/spline.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

using namespace godot;

static inline nt::Vec3 v3(const Vector3 &v) { return nt::Vec3(v.x, v.y, v.z); }
static inline Vector3 gv(const nt::Vec3 &v) { return Vector3((real_t)v.x, (real_t)v.y, (real_t)v.z); }

Dictionary NTRoad::resample(const PackedVector3Array &control, bool closed, double spacing) {
	std::vector<nt::Vec3> ctrl;
	ctrl.reserve(control.size());
	for (int i = 0; i < control.size(); ++i) ctrl.push_back(v3(control[i]));
	nt::Spline sp(ctrl, closed);
	std::vector<nt::Vec3> pts, tan;
	sp.resample(spacing, pts, tan);
	PackedVector3Array p, t;
	p.resize((int64_t)pts.size());
	t.resize((int64_t)tan.size());
	for (size_t i = 0; i < pts.size(); ++i) {
		p.set((int64_t)i, gv(pts[i]));
		t.set((int64_t)i, gv(tan[i]));
	}
	Dictionary d;
	d["points"] = p;
	d["tangents"] = t;
	return d;
}

template <typename T, typename A>
static T at_or(const A &arr, int i, T def) {
	return i < arr.size() ? (T)arr[i] : def;
}

// Sample keys (all per-sample arrays, optional except "centers"):
//   centers PackedVector3Array, ups PackedVector3Array,
//   width_left / width_right / shoulder_left / shoulder_right PackedFloat32Array,
//   road_surface / shoulder_surface / barrier_left / barrier_right / curb_left / curb_right /
//   lanes / marking PackedByteArray.
// Scalar defaults for any missing array come from `options` under the same key.
Dictionary NTRoad::build(const Dictionary &s, const Dictionary &options) {
	PackedVector3Array centers = s.get("centers", PackedVector3Array());
	PackedVector3Array ups = s.get("ups", PackedVector3Array());
	PackedFloat32Array wl = s.get("width_left", PackedFloat32Array());
	PackedFloat32Array wr = s.get("width_right", PackedFloat32Array());
	PackedFloat32Array sl = s.get("shoulder_left", PackedFloat32Array());
	PackedFloat32Array sr = s.get("shoulder_right", PackedFloat32Array());
	PackedByteArray rs = s.get("road_surface", PackedByteArray());
	PackedByteArray ss = s.get("shoulder_surface", PackedByteArray());
	PackedByteArray bl = s.get("barrier_left", PackedByteArray());
	PackedByteArray br = s.get("barrier_right", PackedByteArray());
	PackedByteArray cl = s.get("curb_left", PackedByteArray());
	PackedByteArray cr = s.get("curb_right", PackedByteArray());
	PackedByteArray ln = s.get("lanes", PackedByteArray());
	PackedByteArray mk = s.get("marking", PackedByteArray());

	bool closed = options.get("closed", false);
	int n = centers.size();
	std::vector<nt::RoadSample> samples(n);
	double dist = 0.0;
	for (int i = 0; i < n; ++i) {
		nt::RoadSample &r = samples[i];
		r.center = v3(centers[i]);
		int a = closed ? (i - 1 + n) % n : std::max(i - 1, 0);
		int b = closed ? (i + 1) % n : std::min(i + 1, n - 1);
		r.tangent = (v3(centers[b]) - v3(centers[a])).normalized();
		r.up = i < ups.size() ? v3(ups[i]).normalized() : nt::Vec3(0, 1, 0);
		r.width_left = at_or<double>(wl, i, (double)options.get("width_left", 4.0));
		r.width_right = at_or<double>(wr, i, (double)options.get("width_right", 4.0));
		r.shoulder_left = at_or<double>(sl, i, (double)options.get("shoulder_left", 1.5));
		r.shoulder_right = at_or<double>(sr, i, (double)options.get("shoulder_right", 1.5));
		r.road_surface = at_or<uint8_t>(rs, i, (uint8_t)(int)options.get("road_surface", 0));
		r.shoulder_surface = at_or<uint8_t>(ss, i, (uint8_t)(int)options.get("shoulder_surface", (int)nt::SURF_GRAVEL));
		r.barrier_left = at_or<uint8_t>(bl, i, (uint8_t)(int)options.get("barrier_left", 0));
		r.barrier_right = at_or<uint8_t>(br, i, (uint8_t)(int)options.get("barrier_right", 0));
		r.curb_left = at_or<uint8_t>(cl, i, (uint8_t)(int)options.get("curb_left", 0)) != 0;
		r.curb_right = at_or<uint8_t>(cr, i, (uint8_t)(int)options.get("curb_right", 0)) != 0;
		r.lanes = at_or<uint8_t>(ln, i, (uint8_t)(int)options.get("lanes", 2));
		r.marking = at_or<uint8_t>(mk, i, (uint8_t)(int)options.get("marking", 1));
		if (i > 0) dist += nt::distance(samples[i - 1].center, r.center);
		r.distance = dist + (double)options.get("distance_offset", 0.0);
	}

	nt::RoadBuildOptions o;
	o.closed = closed;
	o.uv_length = options.get("uv_length", 12.0);
	o.curb_width = options.get("curb_width", 0.9);
	o.rail_height = options.get("rail_height", 0.75);
	o.wall_height = options.get("wall_height", 1.1);
	o.shoulder_drop = options.get("shoulder_drop", 0.10);
	o.collision = options.get("collision", true);
	o.render = options.get("render", true);
	o.range_begin = options.get("range_begin", 0);
	o.range_end = options.get("range_end", -1);

	nt::RoadMeshOutput out;
	nt::build_road(samples, o, out);

	Dictionary result;
	Array groups;
	for (int g = 0; g < nt::GROUP_COUNT; ++g) {
		const nt::MeshData &m = out.groups[g];
		Dictionary gd;
		int vc = m.vertex_count();
		gd["group"] = g;
		gd["vertex_count"] = vc;
		if (vc > 0) {
			PackedVector3Array pos, nor;
			PackedVector2Array uv, uv2;
			PackedColorArray col;
			PackedInt32Array idx;
			pos.resize(vc);
			nor.resize(vc);
			uv.resize(vc);
			uv2.resize(vc);
			col.resize(vc);
			Vector3 *pw = pos.ptrw();
			Vector3 *nw = nor.ptrw();
			Vector2 *uw = uv.ptrw();
			Vector2 *u2w = uv2.ptrw();
			Color *cw = col.ptrw();
			for (int i = 0; i < vc; ++i) {
				pw[i] = Vector3(m.positions[i * 3], m.positions[i * 3 + 1], m.positions[i * 3 + 2]);
				nw[i] = Vector3(m.normals[i * 3], m.normals[i * 3 + 1], m.normals[i * 3 + 2]);
				uw[i] = Vector2(m.uvs[i * 2], m.uvs[i * 2 + 1]);
				u2w[i] = Vector2(m.uv2s[i * 2], m.uv2s[i * 2 + 1]);
				cw[i] = Color(m.colors[i * 4], m.colors[i * 4 + 1], m.colors[i * 4 + 2], m.colors[i * 4 + 3]);
			}
			idx.resize((int64_t)m.indices.size());
			int32_t *iw = idx.ptrw();
			for (size_t i = 0; i < m.indices.size(); ++i) iw[i] = m.indices[i];
			gd["positions"] = pos;
			gd["normals"] = nor;
			gd["uvs"] = uv;
			gd["uv2s"] = uv2;
			gd["colors"] = col;
			gd["indices"] = idx;
		}
		groups.push_back(gd);
	}
	result["groups"] = groups;

	int tris = out.collision.tri_count();
	PackedVector3Array faces;
	faces.resize(tris * 3);
	Vector3 *fw = faces.ptrw();
	for (int i = 0; i < tris * 3; ++i) {
		const float *p = &out.collision.positions[i * 3];
		fw[i] = Vector3(p[0], p[1], p[2]);
	}
	PackedByteArray surf, flags;
	surf.resize(tris);
	flags.resize(tris);
	for (int i = 0; i < tris; ++i) {
		surf.set(i, out.collision.surfaces[i]);
		flags.set(i, out.collision.flags[i]);
	}
	result["collision_faces"] = faces;
	result["collision_surfaces"] = surf;
	result["collision_flags"] = flags;
	result["length"] = dist;
	return result;
}

Ref<ArrayMesh> NTRoad::make_mesh(const Dictionary &build_result) {
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	Array groups = build_result.get("groups", Array());
	PackedInt32Array surface_groups;
	for (int g = 0; g < groups.size(); ++g) {
		Dictionary gd = groups[g];
		if ((int)gd.get("vertex_count", 0) == 0) continue;
		Array arrays;
		arrays.resize(Mesh::ARRAY_MAX);
		arrays[Mesh::ARRAY_VERTEX] = gd["positions"];
		arrays[Mesh::ARRAY_NORMAL] = gd["normals"];
		arrays[Mesh::ARRAY_TEX_UV] = gd["uvs"];
		arrays[Mesh::ARRAY_TEX_UV2] = gd["uv2s"];
		arrays[Mesh::ARRAY_COLOR] = gd["colors"];
		arrays[Mesh::ARRAY_INDEX] = gd["indices"];
		mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
		surface_groups.push_back((int)gd["group"]);
	}
	mesh->set_meta("surface_groups", surface_groups);
	return mesh;
}

void NTRoad::_bind_methods() {
	ClassDB::bind_static_method("NTRoad", D_METHOD("resample", "control", "closed", "spacing"), &NTRoad::resample);
	ClassDB::bind_static_method("NTRoad", D_METHOD("build", "samples", "options"), &NTRoad::build);
	ClassDB::bind_static_method("NTRoad", D_METHOD("make_mesh", "build_result"), &NTRoad::make_mesh);
}
