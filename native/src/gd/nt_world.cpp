#include "nt_world.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <cstring>

using namespace godot;

static inline Vector3 gv(const nt::Vec3 &v) { return Vector3((real_t)v.x, (real_t)v.y, (real_t)v.z); }

void NTWorld::build(int64_t seed) {
	world_.build((uint64_t)seed);
	built_.store(true);
}

static Dictionary mesh_group_dict(const nt::MeshData &m, int group) {
	Dictionary gd;
	int vc = m.vertex_count();
	gd["group"] = group;
	gd["vertex_count"] = vc;
	if (vc == 0) return gd;
	PackedVector3Array pos, nor;
	PackedVector2Array uv, uv2;
	PackedColorArray col;
	PackedInt32Array idx;
	pos.resize(vc);
	nor.resize(vc);
	uv.resize(vc);
	uv2.resize(vc);
	col.resize(vc);
	std::memcpy(pos.ptrw(), m.positions.data(), sizeof(float) * 3 * vc);
	std::memcpy(nor.ptrw(), m.normals.data(), sizeof(float) * 3 * vc);
	std::memcpy(uv.ptrw(), m.uvs.data(), sizeof(float) * 2 * vc);
	std::memcpy(uv2.ptrw(), m.uv2s.data(), sizeof(float) * 2 * vc);
	std::memcpy(col.ptrw(), m.colors.data(), sizeof(float) * 4 * vc);
	idx.resize((int64_t)m.indices.size());
	std::memcpy(idx.ptrw(), m.indices.data(), sizeof(int32_t) * m.indices.size());
	gd["positions"] = pos;
	gd["normals"] = nor;
	gd["uvs"] = uv;
	gd["uv2s"] = uv2;
	gd["colors"] = col;
	gd["indices"] = idx;
	return gd;
}

Dictionary NTWorld::build_chunk(int cx, int cz, int lod, bool collision, bool props, double prop_density) const {
	Dictionary d;
	if (!built_.load()) return d;
	nt::ChunkOptions opt;
	opt.lod = lod;
	opt.collision = collision;
	opt.props = props;
	opt.prop_density = prop_density;
	nt::ChunkOutput out;
	nt::build_chunk(world_, cx, cz, opt, out);
	Array groups;
	for (int g = 0; g < nt::WG_COUNT_TOTAL; ++g) groups.push_back(mesh_group_dict(out.groups[g], g));
	d["groups"] = groups;
	Dictionary pd;
	for (int t = 0; t < nt::PROP_COUNT; ++t) {
		const auto &v = out.props[t];
		if (v.empty()) continue;
		PackedFloat32Array arr;
		arr.resize((int64_t)v.size() * 8);
		std::memcpy(arr.ptrw(), v.data(), sizeof(nt::PropInstance) * v.size());
		pd[t] = arr;
	}
	d["props"] = pd;
	if (collision) {
		int tris = out.collision.tri_count();
		PackedVector3Array faces;
		faces.resize(tris * 3);
		Vector3 *fw = faces.ptrw();
		const float *p = out.collision.positions.data();
		for (int i = 0; i < tris * 3; ++i) fw[i] = Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]);
		PackedByteArray surf, flags;
		surf.resize(tris);
		flags.resize(tris);
		if (tris) {
			std::memcpy(surf.ptrw(), out.collision.surfaces.data(), tris);
			std::memcpy(flags.ptrw(), out.collision.flags.data(), tris);
		}
		d["collision_faces"] = faces;
		d["collision_surfaces"] = surf;
		d["collision_flags"] = flags;
	}
	PackedFloat32Array lights;
	lights.resize((int64_t)out.lights.size());
	if (!out.lights.empty()) std::memcpy(lights.ptrw(), out.lights.data(), sizeof(float) * out.lights.size());
	d["lights"] = lights;
	d["cx"] = cx;
	d["cz"] = cz;
	d["lod"] = lod;
	d["center"] = gv(out.center);
	d["min_y"] = out.min_y;
	d["max_y"] = out.max_y;
	return d;
}

Ref<ArrayMesh> NTWorld::make_mesh(const Dictionary &chunk) {
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	Array groups = chunk.get("groups", Array());
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

double NTWorld::height_at(double x, double z) const { return world_.height(x, z); }

Vector3 NTWorld::normal_at(double x, double z) const { return gv(world_.terrain.normal(x, z)); }

int NTWorld::district_at(double x, double z) const { return (int)world_.district_at(x, z); }

String NTWorld::district_name(int d) const { return String(nt::district_name((nt::District)d)); }

bool NTWorld::is_sea(double x, double z) const { return world_.is_sea(x, z); }

Dictionary NTWorld::nearest_road(const Vector3 &p, double max_dist) const {
	Dictionary d;
	nt::NearestRoad nr = world_.nearest_road(nt::Vec3(p.x, p.y, p.z), max_dist);
	if (nr.road < 0) return d;
	const nt::Road &r = world_.roads[nr.road];
	const nt::RoadSampleX &s = r.samples[nr.sample];
	d["road"] = String(r.def.name.c_str());
	d["kind"] = (int)r.def.kind;
	d["sample"] = nr.sample;
	d["distance"] = nr.distance;
	d["lateral"] = nr.lateral;
	d["s"] = nr.s;
	d["position"] = gv(s.rs.center);
	d["tangent"] = gv(s.rs.tangent);
	d["type"] = (int)s.type;
	d["speed_limit"] = r.def.speed_limit;
	d["district"] = (int)s.district;
	return d;
}

PackedStringArray NTWorld::road_names() const {
	PackedStringArray out;
	for (const nt::Road &r : world_.roads) out.push_back(String(r.def.name.c_str()));
	return out;
}

Dictionary NTWorld::road_samples(const String &name) const {
	Dictionary d;
	int ri = world_.road_by_name(name.utf8().get_data());
	if (ri < 0) return d;
	const nt::Road &r = world_.roads[ri];
	int n = (int)r.samples.size();
	PackedVector3Array centers, tangents, ups;
	PackedFloat32Array wl, wr, dist;
	PackedByteArray types;
	centers.resize(n);
	tangents.resize(n);
	ups.resize(n);
	wl.resize(n);
	wr.resize(n);
	dist.resize(n);
	types.resize(n);
	for (int i = 0; i < n; ++i) {
		const nt::RoadSample &s = r.samples[i].rs;
		centers.set(i, gv(s.center));
		tangents.set(i, gv(s.tangent));
		ups.set(i, gv(s.up));
		wl.set(i, (float)s.width_left);
		wr.set(i, (float)s.width_right);
		dist.set(i, (float)s.distance);
		types.set(i, r.samples[i].type);
	}
	d["centers"] = centers;
	d["tangents"] = tangents;
	d["ups"] = ups;
	d["width_left"] = wl;
	d["width_right"] = wr;
	d["distance"] = dist;
	d["types"] = types;
	d["closed"] = r.def.closed;
	d["kind"] = (int)r.def.kind;
	d["length"] = r.length;
	d["district"] = (int)r.def.district;
	d["speed_limit"] = r.def.speed_limit;
	return d;
}

Array NTWorld::pois() const {
	Array out;
	for (const nt::Poi &p : world_.pois) {
		Dictionary d;
		d["type"] = (int)p.type;
		d["id"] = String(p.id.c_str());
		d["position"] = gv(p.pos);
		d["yaw"] = p.yaw;
		d["radius"] = p.radius;
		d["road"] = p.road >= 0 ? String(world_.roads[p.road].def.name.c_str()) : String();
		d["road_s"] = p.road_s;
		d["data"] = String(p.data.c_str());
		out.push_back(d);
	}
	return out;
}

Vector2i NTWorld::chunk_of(const Vector3 &p) const {
	return Vector2i((int)std::floor((p.x - world_.min_x()) / nt::World::CHUNK), (int)std::floor((p.z - world_.min_z()) / nt::World::CHUNK));
}

Rect2 NTWorld::bounds() const {
	return Rect2((real_t)world_.terrain.min_x(), (real_t)world_.terrain.min_z(), (real_t)(world_.terrain.max_x() - world_.terrain.min_x()),
			(real_t)(world_.terrain.max_z() - world_.terrain.min_z()));
}

// Stylised top-down map: shaded terrain, sea, districts tinted, roads drawn by kind.
Ref<Image> NTWorld::minimap(int size) const {
	Ref<Image> img = Image::create(size, size, false, Image::FORMAT_RGBA8);
	if (!built_.load()) return img;
	double x0 = world_.terrain.min_x(), z0 = world_.terrain.min_z();
	double span = std::max(world_.terrain.max_x() - x0, world_.terrain.max_z() - z0);
	double px = span / size;
	for (int j = 0; j < size; ++j)
		for (int i = 0; i < size; ++i) {
			double x = x0 + (i + 0.5) * px, z = z0 + (j + 0.5) * px;
			Color c;
			if (world_.is_sea(x, z)) {
				c = Color(0.03, 0.06, 0.13, 1.0);
			} else {
				double h = world_.height(x, z);
				nt::Vec3 n = world_.terrain.normal(x, z);
				double shade = 0.55 + 0.45 * std::max(0.0, n.dot(nt::Vec3(-0.5, 0.8, -0.3).normalized()));
				double t = std::min(h / 650.0, 1.0);
				c = Color(0.07 + 0.1 * t, 0.09 + 0.07 * t, 0.12 + 0.08 * t, 1.0) * shade;
				nt::District d = world_.district_at(x, z);
				if (d == nt::DIST_CITY) c = c.lerp(Color(0.2, 0.06, 0.2), 0.35);
				else if (d == nt::DIST_DOCKS || d == nt::DIST_DAIKOKU) c = c.lerp(Color(0.05, 0.15, 0.22), 0.35);
				c.a = 1.0;
			}
			img->set_pixel(i, j, c);
		}
	for (const nt::Road &r : world_.roads) {
		Color col;
		int thick = 1;
		switch (r.def.kind) {
			case nt::RK_EXPRESSWAY: col = Color(1.0, 0.25, 0.55); thick = 2; break;
			case nt::RK_RAMP: col = Color(0.9, 0.3, 0.6); break;
			case nt::RK_AVENUE: col = Color(0.95, 0.95, 1.0); thick = 2; break;
			case nt::RK_TOUGE: col = Color(1.0, 0.8, 0.2); thick = 2; break;
			case nt::RK_FARM: col = Color(0.6, 0.5, 0.35); break;
			default: col = Color(0.8, 0.82, 0.88); break;
		}
		for (const nt::RoadSampleX &s : r.samples) {
			int i = (int)((s.rs.center.x - x0) / px), j = (int)((s.rs.center.z - z0) / px);
			for (int dy = 0; dy < thick; ++dy)
				for (int dx = 0; dx < thick; ++dx)
					if (i + dx >= 0 && i + dx < size && j + dy >= 0 && j + dy < size) img->set_pixel(i + dx, j + dy, col);
		}
	}
	return img;
}

void NTWorld::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "seed"), &NTWorld::build);
	ClassDB::bind_method(D_METHOD("is_built"), &NTWorld::is_built);
	ClassDB::bind_method(D_METHOD("build_chunk", "cx", "cz", "lod", "collision", "props", "prop_density"), &NTWorld::build_chunk);
	ClassDB::bind_static_method("NTWorld", D_METHOD("make_mesh", "chunk"), &NTWorld::make_mesh);
	ClassDB::bind_method(D_METHOD("height_at", "x", "z"), &NTWorld::height_at);
	ClassDB::bind_method(D_METHOD("normal_at", "x", "z"), &NTWorld::normal_at);
	ClassDB::bind_method(D_METHOD("district_at", "x", "z"), &NTWorld::district_at);
	ClassDB::bind_method(D_METHOD("district_name", "district"), &NTWorld::district_name);
	ClassDB::bind_method(D_METHOD("is_sea", "x", "z"), &NTWorld::is_sea);
	ClassDB::bind_method(D_METHOD("nearest_road", "position", "max_dist"), &NTWorld::nearest_road, DEFVAL(60.0));
	ClassDB::bind_method(D_METHOD("road_names"), &NTWorld::road_names);
	ClassDB::bind_method(D_METHOD("road_samples", "name"), &NTWorld::road_samples);
	ClassDB::bind_method(D_METHOD("pois"), &NTWorld::pois);
	ClassDB::bind_method(D_METHOD("chunk_of", "position"), &NTWorld::chunk_of);
	ClassDB::bind_method(D_METHOD("chunks_x"), &NTWorld::chunks_x);
	ClassDB::bind_method(D_METHOD("chunks_z"), &NTWorld::chunks_z);
	ClassDB::bind_method(D_METHOD("chunk_size"), &NTWorld::chunk_size);
	ClassDB::bind_method(D_METHOD("bounds"), &NTWorld::bounds);
	ClassDB::bind_method(D_METHOD("minimap", "size"), &NTWorld::minimap);
}
