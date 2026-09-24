// Surface materials: grip, rolling resistance, roughness (ride/haptics), wetness response.
#pragma once

#include "vmath.h"

namespace nt {

enum SurfaceId : uint8_t {
	SURF_ASPHALT = 0,
	SURF_ASPHALT_WORN,
	SURF_CONCRETE,
	SURF_PAINT,
	SURF_CURB,
	SURF_GRAVEL,
	SURF_DIRT,
	SURF_GRASS,
	SURF_SAND,
	SURF_SNOW,
	SURF_ICE,
	SURF_METAL,
	SURF_COBBLE,
	SURF_WALL,
	SURF_GUARDRAIL,
	SURF_BUILDING,
	SURF_WATER,
	SURF_COUNT
};

enum CollisionFlags : uint8_t {
	COL_DRIVABLE = 1, // hit by suspension rays
	COL_SOLID = 2, // hit by body hull spheres
	COL_ALL = 3,
};

struct SurfaceInfo {
	real grip; // dry friction multiplier
	real wet_grip; // multiplier when fully wet (before puddles)
	real rolling; // rolling resistance coefficient
	real bump_amp; // meters of procedural bump
	real bump_freq; // bumps per meter
	real drag; // loose-surface drag (sinking) coefficient
	real restitution; // body collision bounciness
	real scrape_friction; // body collision friction
	bool loose; // gravel/dirt style: deep slip angles still grip, kicks dust
};

inline const SurfaceInfo &surface_info(int id) {
	static const SurfaceInfo table[SURF_COUNT] = {
		/* ASPHALT      */ {1.00, 0.72, 0.012, 0.000, 0.0, 0.00, 0.15, 0.35, false},
		/* ASPHALT_WORN */ {0.94, 0.66, 0.014, 0.004, 1.3, 0.00, 0.15, 0.35, false},
		/* CONCRETE     */ {0.96, 0.70, 0.012, 0.002, 0.5, 0.00, 0.15, 0.35, false},
		/* PAINT        */ {0.88, 0.55, 0.012, 0.000, 0.0, 0.00, 0.15, 0.35, false},
		/* CURB         */ {0.90, 0.60, 0.016, 0.010, 4.0, 0.00, 0.20, 0.35, false},
		/* GRAVEL       */ {0.62, 0.55, 0.040, 0.012, 2.2, 0.35, 0.10, 0.60, true},
		/* DIRT         */ {0.68, 0.48, 0.030, 0.010, 1.6, 0.20, 0.10, 0.55, true},
		/* GRASS        */ {0.48, 0.36, 0.050, 0.014, 1.1, 0.45, 0.10, 0.60, true},
		/* SAND         */ {0.50, 0.50, 0.090, 0.008, 1.0, 1.10, 0.05, 0.70, true},
		/* SNOW         */ {0.36, 0.34, 0.040, 0.006, 1.0, 0.40, 0.05, 0.40, true},
		/* ICE          */ {0.15, 0.12, 0.010, 0.000, 0.0, 0.00, 0.10, 0.10, false},
		/* METAL        */ {0.80, 0.50, 0.012, 0.003, 0.7, 0.00, 0.20, 0.25, false},
		/* COBBLE       */ {0.86, 0.60, 0.016, 0.008, 5.5, 0.00, 0.15, 0.40, false},
		/* WALL         */ {0.80, 0.60, 0.020, 0.000, 0.0, 0.00, 0.25, 0.30, false},
		/* GUARDRAIL    */ {0.70, 0.55, 0.020, 0.000, 0.0, 0.00, 0.35, 0.18, false},
		/* BUILDING     */ {0.80, 0.60, 0.020, 0.000, 0.0, 0.00, 0.20, 0.40, false},
		/* WATER        */ {0.25, 0.25, 0.200, 0.004, 0.5, 2.00, 0.00, 0.50, true},
	};
	return table[id < SURF_COUNT ? id : 0];
}

} // namespace nt
