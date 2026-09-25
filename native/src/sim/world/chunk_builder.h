// Builds everything for one 256 m chunk: merged meshes per material group, prop instance
// lists and collision triangles. Pure C++ so it runs on worker threads.
#pragma once

#include "world.h"

#include <vector>

namespace nt {

enum WorldGroup : uint8_t {
	WG_TERRAIN = GROUP_COUNT, // 7
	WG_JUNCTION, // 8  road shader, junction markings
	WG_BUILDING, // 9  facade shader
	WG_ROOF, // 10
	WG_NEON, // 11 emissive signs (atlas)
	WG_TUNNEL, // 12 tunnel liner
	WG_TUNNEL_LIGHT, // 13 emissive strips
	WG_WATER, // 14
	WG_DECK, // 15 bridge deck underside / fascia (concrete)
	WG_SIDEWALK, // 16 city pavement / plazas
	WG_COUNT_TOTAL
};

enum PropType : uint8_t {
	PROP_TREE_PLANE = 0,
	PROP_TREE_PINE,
	PROP_TREE_PALM,
	PROP_TREE_CYPRESS,
	PROP_STREET_LAMP,
	PROP_HIGHWAY_LAMP,
	PROP_UTILITY_POLE,
	PROP_KIOSK,
	PROP_PIER, // bridge pier, scale.y = height
	PROP_CONTAINER,
	PROP_ROCK,
	PROP_AC_UNIT,
	PROP_WATER_TANK,
	PROP_TRAFFIC_LIGHT,
	PROP_CONE,
	PROP_SIGN_CURVE, // chevron curve sign
	PROP_TREE_OLIVE,
	PROP_BUSH,
	PROP_YACHT, // moored stern-to at the port quays; scale = size variety
	PROP_BENCH,
	PROP_BIN,
	PROP_BOLLARD,
	PROP_HYDRANT,
	PROP_COUNT
};

struct PropInstance {
	float x, y, z; // position
	float yaw;
	float sx, sy, sz; // scale
	float color; // 0..1 variation (hue index / tint)
};

struct ChunkOutput {
	int cx = 0, cz = 0, lod = 0;
	MeshData groups[WG_COUNT_TOTAL];
	std::vector<PropInstance> props[PROP_COUNT];
	CollisionData collision;
	// Light positions for night lighting (street lamps, neon glow) - world xyz + intensity.
	std::vector<float> lights;
	Vec3 center;
	real min_y = 1e9, max_y = -1e9;
};

struct ChunkOptions {
	int lod = 0; // 0 full .. 3 far
	bool collision = true;
	bool props = true;
	real prop_density = 1.0;
	real building_detail = 1.0;
};

void build_chunk(const World &world, int cx, int cz, const ChunkOptions &opt, ChunkOutput &out);

} // namespace nt
