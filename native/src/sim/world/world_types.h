// World description: districts, road definitions, processed road samples, intersections and
// points of interest. Produced by world_layout.cpp, consumed by the chunk builder / game.
#pragma once

#include "../road_mesher.h"
#include "../vmath.h"

#include <string>
#include <vector>

namespace nt {

enum District : uint8_t {
	DIST_WILD = 0,
	DIST_CITY, // Neon Shibuya
	DIST_EXPRESSWAY, // Shuto loop
	DIST_DAIKOKU, // Festival hub
	DIST_DOCKS, // Bayshore docks
	DIST_RURAL, // Satoyama
	DIST_COAST, // Coastal road
	DIST_TOUGE, // Mt. Akina-style pass
	DIST_COUNT
};

enum RoadKind : uint8_t {
	RK_STREET = 0, // city 2-lane
	RK_AVENUE, // city 4-lane
	RK_EXPRESSWAY, // elevated 2+2
	RK_RAMP, // expressway ramps / spiral
	RK_RURAL, // 2-lane country road
	RK_FARM, // dirt farm track
	RK_TOUGE, // narrow mountain pass
	RK_COAST, // coastal 2-lane
	RK_DOCK, // concrete dock road
	RK_PARKING, // parking area apron
	RK_COUNT
};

enum HeightMode : uint8_t {
	HM_TERRAIN = 0, // follow smoothed terrain (grade limited)
	HM_EXPLICIT, // control point y is absolute
	HM_CLIMB, // linear climb from first to last control y along arc length
};

enum SampleType : uint8_t { ST_GROUND = 0, ST_BRIDGE, ST_TUNNEL };

struct RoadDef {
	int id = 0;
	std::string name;
	RoadKind kind = RK_STREET;
	District district = DIST_CITY;
	std::vector<Vec3> ctrl;
	bool closed = false;
	HeightMode height_mode = HM_TERRAIN;
	real max_grade = 0.10;
	real smooth_window = 50.0; // meters of height smoothing for HM_TERRAIN
	real trim_start = 0.0; // meters removed at the ends (intersection clearance)
	real trim_end = 0.0;
	real speed_limit = 40.0; // km/h (signage, traffic)
};

struct RoadSampleX { // processed sample (extends RoadSample for world use)
	RoadSample rs;
	uint8_t type = ST_GROUND;
	real terrain_y = 0.0;
	District district = DIST_CITY;
};

struct Road {
	RoadDef def;
	std::vector<RoadSampleX> samples;
	real length = 0.0;
	Vec3 bmin, bmax;
};

struct RouteSample {
	Vec3 center, tangent, up;
	real width_left = 4.0, width_right = 4.0;
};

// Axis-aligned or rotated rectangular junction patch (city crossings, docks, PA aprons).
struct Intersection {
	Vec3 center;
	real half_x = 7.0, half_z = 7.0;
	real yaw = 0.0;
	uint8_t style = 0; // 0 plain, 1 zebra crossings, 2 scramble crossing, 3 parking bays, 4 dock
	uint8_t surface = SURF_ASPHALT;
	District district = DIST_CITY;
};

enum PoiType : uint8_t {
	POI_FESTIVAL = 0, POI_GARAGE, POI_EVENT_START, POI_DRIFT_ZONE, POI_SPEED_TRAP, POI_SPEED_ZONE,
	POI_DANGER_SIGN, POI_OMAMORI, POI_BARN, POI_LANDMARK, POI_FAST_TRAVEL, POI_TRAIN_LINE, POI_SPAWN,
};

struct Poi {
	PoiType type;
	std::string id;
	Vec3 pos;
	real yaw = 0.0;
	real radius = 10.0;
	int road = -1;
	real road_s = 0.0; // arc length on `road`
	std::string data; // free-form (event id, landmark kind)
};

// City block (for buildings): polygon quad between streets.
struct Block {
	Vec3 min, max; // axis-aligned in city space
	District district = DIST_CITY;
	uint8_t kind = 0; // 0 dense commercial, 1 residential, 2 park, 3 dock yard, 4 plaza
	real density = 1.0;
};

inline const char *district_name(District d) {
	static const char *n[DIST_COUNT] = {"Wilds", "Neon Shibuya", "Shuto Expressway", "Daikoku PA", "Bayshore Docks", "Satoyama", "Coastal Road", "Mt. Akina Touge"};
	return n[d < DIST_COUNT ? d : 0];
}

} // namespace nt
