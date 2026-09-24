// Builds render meshes + collision triangles for a road from spline samples. Output is plain
// arrays so the same code serves the Godot binding and headless tools/tests.
#pragma once

#include "surface.h"
#include "vmath.h"

#include <vector>

namespace nt {

enum BarrierKind : uint8_t { BARRIER_NONE = 0, BARRIER_GUARDRAIL, BARRIER_WALL, BARRIER_TIREWALL, BARRIER_FENCE };

// Material groups: one Godot surface each.
enum MeshGroup : uint8_t {
	GROUP_ROAD = 0, // asphalt, lane markings drawn in shader from UV
	GROUP_SHOULDER, // gravel/grass/dirt verge
	GROUP_CURB, // red/white rumble strips
	GROUP_RAIL, // steel guardrail beam
	GROUP_WALL, // concrete wall / tunnel liner
	GROUP_POST, // barrier posts
	GROUP_TIREWALL,
	GROUP_COUNT
};

struct RoadSample {
	Vec3 center;
	Vec3 tangent; // normalized, direction of travel
	Vec3 up = {0, 1, 0}; // road surface normal (banking)
	real width_left = 4.0; // asphalt half width to the left
	real width_right = 4.0;
	real shoulder_left = 1.5;
	real shoulder_right = 1.5;
	uint8_t road_surface = SURF_ASPHALT;
	uint8_t shoulder_surface = SURF_GRAVEL;
	uint8_t barrier_left = BARRIER_NONE;
	uint8_t barrier_right = BARRIER_NONE;
	bool curb_left = false;
	bool curb_right = false;
	uint8_t lanes = 2; // for the marking shader (UV2.x)
	uint8_t marking = 1; // 0 none, 1 center dashed, 2 center solid double, 3 highway lanes, 4 touge (edge lines only)
	real distance = 0.0; // cumulative arc length
};

struct MeshData {
	std::vector<float> positions; // xyz
	std::vector<float> normals; // xyz
	std::vector<float> uvs; // uv
	std::vector<float> uv2s; // uv2 (x: lane count / marking packed, y: across-road 0..1)
	std::vector<float> colors; // rgba (vertex AO in r, curb pattern g, wear b, puddle bias a)
	std::vector<int32_t> indices;
	int vertex_count() const { return (int)positions.size() / 3; }
	void add_vertex(const Vec3 &p, const Vec3 &n, real u, real v, real u2, real v2, real r = 1, real g = 0, real b = 0, real a = 0);
	void add_quad(int a, int b, int c, int d); // a-b-c-d counter-clockwise from the visible side
	void clear();
};

struct CollisionData {
	std::vector<float> positions; // 9 floats per triangle
	std::vector<uint8_t> surfaces;
	std::vector<uint8_t> flags;
	void add_tri(const Vec3 &a, const Vec3 &b, const Vec3 &c, uint8_t surface, uint8_t flags);
	int tri_count() const { return (int)surfaces.size(); }
	void clear();
};

struct RoadMeshOutput {
	MeshData groups[GROUP_COUNT];
	CollisionData collision;
	void clear();
};

struct RoadBuildOptions {
	real uv_length = 12.0; // meters of road per texture repeat along V
	real curb_width = 0.9;
	real curb_height = 0.06;
	real shoulder_drop = 0.10; // verge sits slightly lower than asphalt
	real rail_height = 0.75;
	real wall_height = 1.1;
	real post_spacing = 4.0;
	bool closed = false;
	bool collision = true;
	bool render = true;
	int range_begin = 0; // sample range (for chunked building)
	int range_end = -1;
};

void build_road(const std::vector<RoadSample> &samples, const RoadBuildOptions &opt, RoadMeshOutput &out);

} // namespace nt
