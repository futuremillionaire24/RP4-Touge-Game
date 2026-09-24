#include "world.h"

#include "../rng.h"
#include "../spline.h"

#include <algorithm>
#include <thread>
#include <unordered_map>

namespace nt {

// ---------------------------------------------------------------------------------------------
// Terrain function

static real region_weight(real x, real z, real x0, real z0, real x1, real z1, real blend) {
	real dx = std::max({x0 - x, 0.0, x - x1});
	real dz = std::max({z0 - z, 0.0, z - z1});
	real d = std::sqrt(dx * dx + dz * dz);
	return 1.0 - smoothstep(0.0, blend, d);
}

static const Vec3 TOUGE_PASS(-3300, 0, -250);

static real coast_z(real x) { return 2150.0 + 250.0 * std::sin(x / 800.0) + 120.0 * std::sin(x / 300.0 + 1.0); }

bool World::is_sea(real x, real z) const {
	if (baked) return land_at(x, z) == LAND_SEA;
	return z > coast_z(x) || x > 3450.0 + 120.0 * std::sin(z / 400.0);
}

real World::base_height(real x, real z, uint8_t &material) const {
	material = 0;
	if (baked) {
		// Real terrain (bicubic from the 8 m bake) + metre-scale relief the DEM can't resolve,
		// stronger on rocky/scrub hillsides than in town or on the beach.
		real h = bake_height(x, z);
		uint8_t lc = land_at(x, z);
		// Sea (incl. the harbours, whose DEM sits at quay height): seabed below the water plane,
		// deepening away from the quays.
		if (lc == LAND_SEA) {
			int seaN = 0;
			for (int k = 0; k < 8; ++k) {
				real a = k * (TAU / 8.0);
				seaN += land_at(x + std::cos(a) * 24.0, z + std::sin(a) * 24.0) == LAND_SEA ? 1 : 0;
			}
			return std::min(h, -1.5 - 5.0 * (seaN / 8.0)) + (material = 3, 0.0);
		}
		real rough = lc == LAND_ROCK ? 1.4 : (lc == LAND_SCRUB || lc == LAND_FOREST) ? 0.8 : lc == LAND_FARM ? 0.3 : 0.1;
		if (h > 1.0) h += rough * (fbm2(x / 23.0 + 5.0, z / 23.0 - 3.0, 3) - 0.5) * 2.0;
		switch (lc) {
			case LAND_ROCK: material = 2; break;
			case LAND_SAND: case LAND_SEA: case LAND_WATER: material = 3; break;
			case LAND_FARM: material = 4; break;
			case LAND_URBAN: case LAND_PORT: material = 5; break;
			case LAND_FOREST: material = 1; break;
			default: material = 0; break;
		}
		return h;
	}
	// Rolling countryside.
	real h = 9.0 + 12.0 * (fbm2(x / 700.0 + 13.0, z / 700.0 - 7.0, 4) - 0.5) * 2.0;
	// Satoyama hills (north-west).
	real dh = distance(Vec3(x, 0, z), Vec3(-2200, 0, -1900));
	h += 48.0 * std::exp(-sqr(dh / 950.0)) * (0.6 + 0.8 * fbm2(x / 400.0, z / 400.0, 3));
	// Mt. Akina: sharp peak with ridges; the touge climbs its east/south face.
	real dm = distance(Vec3(x, 0, z), Vec3(-3800, 0, -500));
	real mountain = 660.0 * std::exp(-std::pow(dm / 950.0, 1.6));
	real ridge = 1.0 - std::fabs(fbm2(x / 520.0 + 3.0, z / 520.0 + 9.0, 4) * 2.0 - 1.0);
	mountain += 90.0 * ridge * smoothstep(0.0, 400.0, mountain);
	h += mountain;
	// Flattened city and docks.
	real wc = region_weight(x, z, -950, -800, 950, 800, 450.0);
	h = lerpr(h, 6.0 + 1.5 * (fbm2(x / 300.0, z / 300.0, 2) - 0.5), wc);
	real wd = region_weight(x, z, 1650, -650, 3350, 1300, 260.0);
	h = lerpr(h, 3.2, wd);
	if (wc > 0.5 || wd > 0.5) material = 5;

	// Sea: beaches blend down to the water, then depth.
	real cz = coast_z(x);
	real sea_x = 3450.0 + 120.0 * std::sin(z / 400.0);
	real dist_sea = std::min(cz - z, sea_x - x); // >0 inland
	if (dist_sea < 140.0) {
		real t = smoothstep(140.0, 0.0, dist_sea);
		// Cliffs stay high where the mountain meets the sea.
		real cliff = smoothstep(60.0, 160.0, h);
		real beach = lerpr(h, 1.2, t * (1.0 - cliff * 0.85));
		if (dist_sea < 0.0) beach = lerpr(1.0, -18.0, smoothstep(0.0, 260.0, -dist_sea)) * (1.0 - cliff) + (h - 40.0) * cliff * smoothstep(0.0, 40.0, -dist_sea);
		h = std::min(h, beach);
		if (dist_sea < 40.0 && cliff < 0.4) material = 3;
	}
	if (material == 0) {
		real slope_proxy = mountain > 200.0 ? smoothstep(0.55, 0.75, ridge) : 0.0;
		// Bare rock only on ridges and the very top; alpine meadow elsewhere.
		if (h > 600.0 || slope_proxy > 0.55) material = 2;
		else if (dh < 900.0 && h < 45.0 && fbm2(x / 90.0, z / 90.0, 2) > 0.5) material = 4; // paddies
	}
	return h;
}

District World::district_at(real x, real z) const {
	if (baked) {
		if (bake_dist_.empty()) return (District)0;
		int i = std::clamp((int)((x - bake_x0_) / dist_cell_), 0, dist_w_ - 1);
		int j = std::clamp((int)((z - bake_z0_) / dist_cell_), 0, dist_h_ - 1);
		return (District)bake_dist_[(size_t)j * dist_w_ + i];
	}
	if (x > -1000 && x < 1000 && z > -850 && z < 850) return DIST_CITY;
	if (x > 2050 && x < 2700 && z > -650 && z < 0) return DIST_DAIKOKU;
	if (x > 1600 && x < 3400 && z > -100 && z < 1350) return DIST_DOCKS;
	if (distance(Vec3(x, 0, z), Vec3(-3700, 0, -500)) < 1700.0) return DIST_TOUGE;
	if (z > coast_z(x) - 500.0) return DIST_COAST;
	if (x < -900 && z < -700) return DIST_RURAL;
	return DIST_WILD;
}

// ---------------------------------------------------------------------------------------------
// Build

void World::build(uint64_t s) {
	seed = s;
	terrain.init(-5200.0, -3200.0, 9000.0, 6200.0, 4.0);
	const int rows = terrain.height();
	// Terrain fill dominates build time: split row bands across all cores.
	unsigned threads = std::max(1u, std::min(8u, std::thread::hardware_concurrency()));
	std::vector<std::thread> pool;
	int band = (rows + (int)threads - 1) / (int)threads;
	for (unsigned t = 0; t < threads; ++t) {
		int r0 = (int)t * band, r1 = std::min(rows, r0 + band);
		if (r0 >= r1) break;
		pool.emplace_back([this, r0, r1] { terrain.fill_rows(r0, r1, [this](real x, real z, uint8_t &m) { return base_height(x, z, m); }); });
	}
	for (auto &th : pool) th.join();
	roads.clear();
	junctions.clear();
	blocks.clear();
	pois.clear();
	defs_.clear();
	layout_roads();
	for (RoadDef &d : defs_) {
		Road r;
		r.def = d;
		process_road(r); // geometry + heights
		if (r.samples.size() >= 2) roads.push_back(std::move(r));
	}
	weld_endpoints();
	for (Road &r : roads) process_road(r); // classification + furniture on final heights
	open_merges();
	carve_roads();
	layout_pois();
}

void World::add_road(RoadDef def) {
	def.id = (int)defs_.size();
	defs_.push_back(std::move(def));
}

std::vector<RouteSample> World::compose_route(const std::vector<std::string> &names) const {
	std::vector<RouteSample> out;
	for (const std::string &entry : names) {
		bool rev = !entry.empty() && entry[0] == '~';
		int ri = road_by_name(rev ? entry.substr(1) : entry);
		if (ri < 0) continue;
		const Road &r = roads[ri];
		int n = (int)r.samples.size();
		int k0 = 0;
		auto sample_at = [&](int k) -> const RoadSample & { return r.samples[rev ? n - 1 - k : k].rs; };
		if (!out.empty()) {
			const Vec3 last = out.back().center;
			while (k0 < n - 1 && distance(sample_at(k0).center, last) < 3.0) ++k0;
			const Vec3 first = sample_at(k0).center;
			real gap = distance(last, first);
			if (gap > 4.5) {
				int steps = (int)(gap / 3.0);
				real w = std::min(out.back().width_left, out.back().width_right) + 2.0;
				for (int s = 1; s < steps; ++s) {
					RouteSample rs;
					rs.center = lerp(last, first, (real)s / steps);
					rs.tangent = (first - last).normalized();
					rs.up = Vec3(0, 1, 0);
					rs.width_left = rs.width_right = w;
					out.push_back(rs);
				}
			}
		}
		for (int k = k0; k < n; ++k) {
			const RoadSample &s = sample_at(k);
			RouteSample rs;
			rs.center = s.center;
			rs.tangent = rev ? -s.tangent : s.tangent;
			rs.up = s.up;
			rs.width_left = rev ? s.width_right : s.width_left;
			rs.width_right = rev ? s.width_left : s.width_right;
			out.push_back(rs);
		}
	}
	return out;
}

int World::road_by_name(const std::string &name) const {
	for (size_t i = 0; i < roads.size(); ++i)
		if (roads[i].def.name == name) return (int)i;
	return -1;
}

// ---------------------------------------------------------------------------------------------
// Layout

static RoadDef rd(const char *name, RoadKind k, District d, std::vector<Vec3> ctrl, HeightMode hm = HM_TERRAIN, bool closed = false) {
	RoadDef r;
	r.name = name;
	r.kind = k;
	r.district = d;
	r.ctrl = std::move(ctrl);
	r.height_mode = hm;
	r.closed = closed;
	switch (k) {
		case RK_STREET: r.speed_limit = 40; r.max_grade = 0.08; break;
		case RK_AVENUE: r.speed_limit = 50; r.max_grade = 0.06; break;
		case RK_EXPRESSWAY: r.speed_limit = 80; r.max_grade = 0.06; r.smooth_window = 120; break;
		case RK_RAMP: r.speed_limit = 40; r.max_grade = 0.08; break;
		case RK_RURAL: r.speed_limit = 50; r.max_grade = 0.10; r.smooth_window = 70; break;
		case RK_FARM: r.speed_limit = 30; r.max_grade = 0.12; r.smooth_window = 30; break;
		case RK_TOUGE: r.speed_limit = 40; r.max_grade = 0.13; r.smooth_window = 40; break;
		case RK_COAST: r.speed_limit = 50; r.max_grade = 0.10; r.smooth_window = 90; break;
		case RK_DOCK: r.speed_limit = 40; r.max_grade = 0.04; break;
		default: break;
	}
	return r;
}

static real half_width_of(RoadKind k) {
	switch (k) {
		case RK_AVENUE: return 7.0;
		case RK_EXPRESSWAY: return 7.5;
		case RK_STREET: return 4.5;
		case RK_RAMP: return 4.2;
		case RK_RURAL: return 3.6;
		case RK_FARM: return 2.6;
		case RK_TOUGE: return 3.3;
		case RK_COAST: return 3.7;
		case RK_DOCK: return 6.5;
		default: return 5.0;
	}
}

void World::layout_roads() {
	uint8_t m;
	auto H = [&](real x, real z) { return base_height(x, z, m); };

	// ---- Neon Shibuya grid: avenues + streets split at every crossing ----------------------
	const std::vector<real> xs = {-780, -585, -390, -195, 0, 195, 390, 585, 780};
	const std::vector<real> zs = {-650, -487, -325, -162, 0, 162, 325, 487, 650};
	auto is_avenue_x = [](int i) { return i % 2 == 0; };
	auto hw_x = [&](int i) { return half_width_of(is_avenue_x(i) ? RK_AVENUE : RK_STREET); };
	auto hw_z = [&](int j) { return half_width_of(is_avenue_x(j) ? RK_AVENUE : RK_STREET); };
	for (size_t i = 0; i < xs.size(); ++i) {
		for (size_t j = 0; j < zs.size(); ++j) {
			Intersection it;
			it.center = Vec3(xs[i], H(xs[i], zs[j]) + 0.3, zs[j]);
			it.half_x = hw_x((int)i);
			it.half_z = hw_z((int)j);
			it.style = (xs[i] == 0 && zs[j] == 0) ? 2 : 1;
			junctions.push_back(it);
		}
	}
	char buf[64];
	for (size_t i = 0; i < xs.size(); ++i) { // north-south
		for (size_t j = 0; j + 1 < zs.size(); ++j) {
			real z0 = zs[j] + hw_z((int)j), z1 = zs[j + 1] - hw_z((int)j + 1);
			std::snprintf(buf, sizeof(buf), "city_ns_%d_%d", (int)i, (int)j);
			RoadDef r = rd(buf, is_avenue_x((int)i) ? RK_AVENUE : RK_STREET, DIST_CITY,
					{Vec3(xs[i], H(xs[i], zs[j]) + 0.3, z0), Vec3(xs[i], H(xs[i], zs[j + 1]) + 0.3, z1)}, HM_EXPLICIT);
			add_road(r);
		}
	}
	for (size_t j = 0; j < zs.size(); ++j) { // east-west
		for (size_t i = 0; i + 1 < xs.size(); ++i) {
			real x0 = xs[i] + hw_x((int)i), x1 = xs[i + 1] - hw_x((int)i + 1);
			std::snprintf(buf, sizeof(buf), "city_ew_%d_%d", (int)j, (int)i);
			RoadDef r = rd(buf, is_avenue_x((int)j) ? RK_AVENUE : RK_STREET, DIST_CITY,
					{Vec3(x0, H(xs[i], zs[j]) + 0.3, zs[j]), Vec3(x1, H(xs[i + 1], zs[j]) + 0.3, zs[j])}, HM_EXPLICIT);
			add_road(r);
		}
	}
	// City blocks between streets.
	for (size_t i = 0; i + 1 < xs.size(); ++i)
		for (size_t j = 0; j + 1 < zs.size(); ++j) {
			Block b;
			b.min = Vec3(xs[i] + hw_x((int)i) + 3.5, 0, zs[j] + hw_z((int)j) + 3.5);
			b.max = Vec3(xs[i + 1] - hw_x((int)i + 1) - 3.5, 0, zs[j + 1] - hw_z((int)j + 1) - 3.5);
			real cd = std::max(std::fabs((xs[i] + xs[i + 1]) * 0.5), std::fabs((zs[j] + zs[j + 1]) * 0.5));
			b.kind = cd < 420 ? 0 : (hash01((int)i, (int)j, 5) < 0.12 ? 2 : 1);
			b.density = cd < 420 ? 1.0 : 0.7;
			b.min.y = b.max.y = H((b.min.x + b.max.x) * 0.5, (b.min.z + b.max.z) * 0.5);
			blocks.push_back(b);
		}

	// ---- Shuto Expressway loop (elevated, with a tunnel on the west side) ------------------
	{
		RoadDef r = rd("shuto_loop", RK_EXPRESSWAY, DIST_EXPRESSWAY,
				{Vec3(-1050, 22, -930), Vec3(-300, 23, -990), Vec3(450, 22, -980), Vec3(1100, 21, -900), Vec3(1380, 20, -350),
						Vec3(1420, 19, 300), Vec3(1150, 20, 930), Vec3(400, 22, 1030), Vec3(-400, 22, 1010), Vec3(-1100, 20, 940),
						Vec3(-1420, 6, 500), Vec3(-1470, -8, -50), Vec3(-1400, 6, -560)},
				HM_EXPLICIT, true);
		add_road(r);
		// Bayshore spur to Daikoku and the docks.
		add_road(rd("wangan_spur", RK_EXPRESSWAY, DIST_EXPRESSWAY,
				{Vec3(1420, 19, 300) + Vec3(40, 0, 0), Vec3(1800, 20, 250), Vec3(2150, 21, 120), Vec3(2600, 22, 60), Vec3(3150, 22, -150), Vec3(3300, 22, -700), Vec3(3000, 22, -1300), Vec3(2000, 22, -1400), Vec3(1250, 21, -1150)},
				HM_EXPLICIT));
		// Ramps down to the city avenues.
		add_road(rd("ramp_east", RK_RAMP, DIST_EXPRESSWAY, {Vec3(1395, 19.5, -120), Vec3(1200, 14, -40), Vec3(950, 7.5, 0), Vec3(787, H(787, 0) + 0.3, 0)}, HM_EXPLICIT));
		add_road(rd("ramp_north", RK_RAMP, DIST_EXPRESSWAY, {Vec3(20, 23, -985), Vec3(10, 15, -900), Vec3(0, 8, -780), Vec3(0, H(0, -657) + 0.3, -657)}, HM_EXPLICIT));
		add_road(rd("ramp_south", RK_RAMP, DIST_EXPRESSWAY, {Vec3(0, 22, 1022), Vec3(-10, 15, 930), Vec3(0, 8, 790), Vec3(0, H(0, 657) + 0.3, 657)}, HM_EXPLICIT));
	}

	// ---- Daikoku PA: spiral down from the spur into the Festival apron ---------------------
	{
		std::vector<Vec3> spiral;
		Vec3 c(2380, 0, -330);
		real r0 = 95.0;
		spiral.push_back(Vec3(2600, 22, 60) + Vec3(-30, 0, -40));
		for (int k = 0; k <= 14; ++k) {
			real a = PI * 0.5 + k * (TAU * 1.5 / 14.0);
			real y = lerpr(21.0, 4.6, k / 14.0);
			spiral.push_back(c + Vec3(std::cos(a) * r0, y, std::sin(a) * r0));
		}
		spiral.push_back(Vec3(2380, 4.2, -200));
		add_road(rd("daikoku_spiral", RK_RAMP, DIST_DAIKOKU, spiral, HM_EXPLICIT));
		Intersection apron;
		apron.center = Vec3(2380, 4.0, -330);
		apron.half_x = 130.0;
		apron.half_z = 80.0;
		apron.style = 3;
		apron.district = DIST_DAIKOKU;
		junctions.push_back(apron);
		add_road(rd("daikoku_exit", RK_DOCK, DIST_DAIKOKU, {Vec3(2380, 4.0, -245), Vec3(2380, 3.6, -120), Vec3(2300, 3.4, 60), Vec3(2300, 3.4, 93)}, HM_EXPLICIT));
	}

	// ---- Bayshore docks grid ------------------------------------------------------------
	{
		const std::vector<real> dx = {1850, 2300, 2750, 3200};
		const std::vector<real> dz = {100, 550, 1000};
		real hw = half_width_of(RK_DOCK);
		for (real x : dx)
			for (real z : dz) {
				Intersection it;
				it.center = Vec3(x, 3.5, z);
				it.half_x = it.half_z = hw;
				it.style = 4;
				it.surface = SURF_CONCRETE;
				it.district = DIST_DOCKS;
				junctions.push_back(it);
			}
		for (size_t i = 0; i < dx.size(); ++i)
			for (size_t j = 0; j + 1 < dz.size(); ++j) {
				std::snprintf(buf, sizeof(buf), "dock_ns_%d_%d", (int)i, (int)j);
				add_road(rd(buf, RK_DOCK, DIST_DOCKS, {Vec3(dx[i], 3.5, dz[j] + hw), Vec3(dx[i], 3.5, dz[j + 1] - hw)}, HM_EXPLICIT));
			}
		for (size_t j = 0; j < dz.size(); ++j)
			for (size_t i = 0; i + 1 < dx.size(); ++i) {
				std::snprintf(buf, sizeof(buf), "dock_ew_%d_%d", (int)j, (int)i);
				add_road(rd(buf, RK_DOCK, DIST_DOCKS, {Vec3(dx[i] + hw, 3.5, dz[j]), Vec3(dx[i + 1] - hw, 3.5, dz[j])}, HM_EXPLICIT));
			}
		for (size_t i = 0; i + 1 < dx.size(); ++i)
			for (size_t j = 0; j + 1 < dz.size(); ++j) {
				Block b;
				b.min = Vec3(dx[i] + hw + 4, 3.3, dz[j] + hw + 4);
				b.max = Vec3(dx[i + 1] - hw - 4, 3.3, dz[j + 1] - hw - 4);
				b.kind = 3;
				b.district = DIST_DOCKS;
				blocks.push_back(b);
			}
		// City east avenue to the docks.
		add_road(rd("dock_link", RK_AVENUE, DIST_DOCKS, {Vec3(787, H(787, 325) + 0.3, 325), Vec3(1150, 5, 330), Vec3(1500, 4, 250), Vec3(1843, 3.5, 100)}, HM_EXPLICIT));
	}

	// ---- Coastal road: docks -> cliffs -> mountain base ----------------------------------
	{
		std::vector<Vec3> c;
		c.push_back(Vec3(1850, 3.5, 1006.5));
		c.push_back(Vec3(1780, 0, 1300));
		for (real x = 1500; x >= -2700; x -= 380) c.push_back(Vec3(x, 0, coast_z(x) - 170.0 - 60.0 * std::sin(x / 500.0)));
		c.push_back(Vec3(-2950, 0, 1450));
		c.push_back(Vec3(-3150, 0, 1150));
		add_road(rd("coast_road", RK_COAST, DIST_COAST, c));
		// City south avenue to the coast (Route 1).
		add_road(rd("route1", RK_AVENUE, DIST_COAST, {Vec3(0, H(0, 657) + 0.3, 657), Vec3(30, 0, 1050), Vec3(-20, 0, 1500), Vec3(20, 0, coast_z(20) - 185)}, HM_TERRAIN));
	}

	// ---- Mt. Akina touge: 12 hairpins up the south face, fast sweepers down the north ---
	// The pass crosses a saddle ~560 m from the peak (~480 m altitude), not the summit itself: a
	// ~10% average grade over the ascent, like a real mountain pass.
	make_touge(Vec3(-3150, 0, 1150), TOUGE_PASS, 12, 300.0, seed * 31 + 7, "touge_ascent", false);
	make_touge(TOUGE_PASS, Vec3(-3000, 0, -1700), 5, 420.0, seed * 31 + 11, "touge_descent", true);

	// ---- Satoyama rural roads + farm tracks ----------------------------------------------
	add_road(rd("rural_main", RK_RURAL, DIST_RURAL,
			{Vec3(-3000, 0, -1700), Vec3(-2600, 0, -2150), Vec3(-2000, 0, -2250), Vec3(-1500, 0, -1900), Vec3(-1250, 0, -1350), Vec3(-900, 0, -1000), Vec3(-780, H(-780, -657) + 0.3, -657)}));
	add_road(rd("mountain_road", RK_RURAL, DIST_WILD,
			{Vec3(-787, H(-787, 0) + 0.3, 0), Vec3(-1150, 0, 60), Vec3(-1700, 0, 350), Vec3(-2300, 0, 650), Vec3(-2800, 0, 950), Vec3(-3150, 0, 1150)}));
	add_road(rd("farm_loop", RK_FARM, DIST_RURAL,
			{Vec3(-2450, 0, -1550), Vec3(-2000, 0, -1300), Vec3(-1700, 0, -1650), Vec3(-1900, 0, -2050), Vec3(-2300, 0, -1950)}, HM_TERRAIN, true));
}

void World::make_touge(const Vec3 &base, const Vec3 &summit, int hairpins, real leg_len, uint64_t s, const char *name, bool fast) {
	Rng rng(s);
	Vec3 D = (summit - base).flat();
	real L = D.length();
	D = D / L;
	Vec3 P = D.cross(Vec3(0, 1, 0)).normalized();
	real A = leg_len * 0.5;
	std::vector<real> radii(hairpins);
	real arc_advance = 0.0;
	for (int k = 0; k < hairpins; ++k) {
		radii[k] = fast ? rng.range(28.0, 45.0) : rng.range(13.0, 19.0);
		arc_advance += 2.0 * radii[k];
	}
	// Diagonal legs climb toward the summit; each hairpin is an exact 180-degree arc curving uphill,
	// tangent to both legs, so the spline through dense points never overshoots or kinks.
	real adv = std::max(20.0, (L - arc_advance) / (hairpins + 1));
	std::vector<Vec3> c;
	c.push_back(base);
	Vec3 p = base;
	real d = 0.0;
	real side = 1.0;
	for (int k = 0; k <= hairpins; ++k) {
		bool last = k == hairpins;
		Vec3 leg_end = last ? summit : base + D * (d + adv) + P * (side * A);
		// Leg points every ~50 m with a gentle S-bend for character.
		real leg_len_m = distance(p.flat(), leg_end.flat());
		int pts = std::max(2, (int)(leg_len_m / 50.0));
		real bend = rng.range(-10.0, 10.0);
		for (int q = 1; q <= pts; ++q) {
			real t = (real)q / pts;
			Vec3 pt = lerp(p, leg_end, t) + D * (bend * std::sin(t * PI) * (q < pts ? 1.0 : 0.0));
			c.push_back(pt);
		}
		if (last) break;
		d += adv;
		real r = radii[k];
		Vec3 centre = leg_end + D * r;
		for (int a = 1; a <= 8; ++a) {
			real th = PI * a / 8.0;
			c.push_back(centre - D * (r * std::cos(th)) + P * (side * r * std::sin(th)));
		}
		p = leg_end + D * (2.0 * r);
		d += 2.0 * r;
		side = -side;
	}
	RoadDef r = rd(name, RK_TOUGE, DIST_TOUGE, c, HM_TERRAIN);
	add_road(r);
}

// ---------------------------------------------------------------------------------------------
// Road processing

// Two passes. First call (no samples yet): resample and compute heights only, then return, so
// endpoints can be welded. Second call: classify ground/bridge/tunnel and add furniture using the
// final (welded) heights.
void World::process_road(Road &r) {
	const RoadDef &d = r.def;
	std::vector<Vec3> pts, tan;
	uint8_t m;
	if (!r.samples.empty()) {
		int n = (int)r.samples.size();
		pts.resize(n);
		tan.resize(n);
		std::vector<real> ys(n), base(n);
		for (int i = 0; i < n; ++i) {
			pts[i] = r.samples[i].rs.center;
			tan[i] = r.samples[i].rs.tangent;
			ys[i] = pts[i].y;
			base[i] = r.samples[i].terrain_y;
		}
		classify_and_furnish(r, pts, tan, ys, base);
		return;
	}
	Spline sp(d.ctrl, d.closed);
	sp.resample(3.0, pts, tan);
	int n = (int)pts.size();
	if (n < 2) return;
	std::vector<real> ys(n), base(n);
	for (int i = 0; i < n; ++i) base[i] = base_height(pts[i].x, pts[i].z, m);
	if (d.height_mode == HM_EXPLICIT) {
		for (int i = 0; i < n; ++i) ys[i] = pts[i].y;
	} else {
		// Smoothed terrain with a grade limit (forward + backward passes).
		int win = std::max(1, (int)(d.smooth_window / 3.0));
		for (int i = 0; i < n; ++i) {
			real acc = 0.0;
			int cnt = 0;
			for (int k = -win; k <= win; ++k) {
				int j = d.closed ? ((i + k) % n + n) % n : std::clamp(i + k, 0, n - 1);
				acc += base[j];
				cnt++;
			}
			ys[i] = std::max(acc / cnt, 1.5) + 0.35;
		}
		real g = d.max_grade * 3.0;
		for (int pass = 0; pass < 2; ++pass) {
			for (int i = 1; i < n; ++i) ys[i] = clampr(ys[i], ys[i - 1] - g, ys[i - 1] + g);
			for (int i = n - 2; i >= 0; --i) ys[i] = clampr(ys[i], ys[i + 1] - g, ys[i + 1] + g);
		}
	}
	// Geometry pass: store centres/tangents/terrain only.
	r.samples.resize(n);
	for (int i = 0; i < n; ++i) {
		r.samples[i].rs.center = Vec3(pts[i].x, ys[i], pts[i].z);
		r.samples[i].rs.tangent = tan[i];
		r.samples[i].terrain_y = base[i];
	}
}

void World::classify_and_furnish(Road &r, const std::vector<Vec3> &pts, const std::vector<Vec3> &tan, const std::vector<real> &ys,
		const std::vector<real> &base) {
	const RoadDef &d = r.def;
	int n = (int)pts.size();
	uint8_t m;
	// Classify ground / bridge / tunnel with 30 m hysteresis.
	std::vector<uint8_t> type(n, ST_GROUND);
	for (int i = 0; i < n; ++i) {
		real diff = ys[i] - base[i];
		if (baked) {
			// Real map: structures come from OpenStreetMap; untagged roads high above the ground
			// (viaduct approaches) still get a deck.
			if (d.tunnel) type[i] = ST_TUNNEL;
			else if (d.bridge || diff > 5.0 || (is_sea(pts[i].x, pts[i].z) && diff > 0.5)) type[i] = ST_BRIDGE;
			continue;
		}
		// Shallow cover becomes a deep cutting with retaining walls; only real mountains get bored.
		if (diff > 3.5) type[i] = ST_BRIDGE;
		else if (diff < -12.0) type[i] = ST_TUNNEL;
		if (is_sea(pts[i].x, pts[i].z) && diff > 0.5) type[i] = ST_BRIDGE;
	}
	for (int t : {ST_BRIDGE, ST_TUNNEL}) {
		// Close short gaps and drop short runs.
		for (int i = 0; i < n;) {
			if (type[i] != t) { ++i; continue; }
			int j = i;
			while (j < n && type[j] == t) ++j;
			int k = j;
			while (k < n && type[k] != t && k - j < 8) ++k;
			if (k < n && type[k] == t && k - j < 8)
				for (int q = j; q < k; ++q) type[q] = (uint8_t)t;
			i = j;
		}
		if (baked && t == ST_TUNNEL) continue; // mapped tunnels keep their exact extent
		int min_run = t == ST_TUNNEL ? 20 : 6; // tunnels shorter than 60 m become cuttings
		for (int i = 0; i < n;) {
			if (type[i] != t) { ++i; continue; }
			int j = i;
			while (j < n && type[j] == t) ++j;
			if (j - i < min_run)
				for (int q = i; q < j; ++q) type[q] = ST_GROUND;
			i = j;
		}
	}

	real hw = half_width_of(d.kind);
	r.samples.resize(n);
	real dist = 0.0;
	r.bmin = Vec3(1e9, 1e9, 1e9);
	r.bmax = Vec3(-1e9, -1e9, -1e9);
	for (int i = 0; i < n; ++i) {
		RoadSampleX &sx = r.samples[i];
		RoadSample &s = sx.rs;
		s.center = Vec3(pts[i].x, ys[i], pts[i].z);
		s.tangent = tan[i];
		if (i > 0) dist += distance(r.samples[i - 1].rs.center, s.center);
		s.distance = dist;
		sx.type = type[i];
		sx.terrain_y = base[i];
		sx.district = d.district;
		s.width_left = s.width_right = hw;
		s.shoulder_left = s.shoulder_right = 1.5;
		s.road_surface = SURF_ASPHALT;
		s.shoulder_surface = SURF_GRAVEL;
		s.barrier_left = s.barrier_right = BARRIER_NONE;
		s.lanes = 2;
		s.marking = 1;
		Vec3 right = s.tangent.cross(Vec3(0, 1, 0)).normalized();
		real side_l = base_height(pts[i].x - right.x * (hw + 10), pts[i].z - right.z * (hw + 10), m);
		real side_r = base_height(pts[i].x + right.x * (hw + 10), pts[i].z + right.z * (hw + 10), m);
		switch (d.kind) {
			case RK_STREET:
				s.shoulder_left = s.shoulder_right = 3.2;
				s.shoulder_surface = SURF_CONCRETE;
				s.curb_left = s.curb_right = true;
				break;
			case RK_AVENUE:
				s.lanes = 4;
				s.marking = 3;
				s.shoulder_left = s.shoulder_right = 4.0;
				s.shoulder_surface = SURF_CONCRETE;
				s.curb_left = s.curb_right = true;
				break;
			case RK_EXPRESSWAY:
				s.lanes = 4;
				s.marking = 3;
				s.shoulder_left = s.shoulder_right = 1.2;
				s.shoulder_surface = SURF_CONCRETE;
				s.barrier_left = s.barrier_right = BARRIER_WALL;
				break;
			case RK_RAMP:
				s.lanes = 1;
				s.marking = 5;
				s.shoulder_left = s.shoulder_right = 0.8;
				s.shoulder_surface = SURF_CONCRETE;
				s.barrier_left = s.barrier_right = BARRIER_WALL;
				break;
			case RK_RURAL:
			case RK_COAST:
				s.shoulder_left = s.shoulder_right = 1.4;
				s.shoulder_surface = SURF_GRASS;
				if (ys[i] - side_l > 2.0) s.barrier_left = BARRIER_GUARDRAIL;
				if (ys[i] - side_r > 2.0) s.barrier_right = BARRIER_GUARDRAIL;
				if (d.kind == RK_COAST) {
					// Sea side always guarded; the cliff side gets a retaining wall in cuttings.
					if (is_sea(pts[i].x + right.x * 120, pts[i].z + right.z * 120)) s.barrier_right = BARRIER_GUARDRAIL;
					if (is_sea(pts[i].x - right.x * 120, pts[i].z - right.z * 120)) s.barrier_left = BARRIER_GUARDRAIL;
				}
				if (side_l - ys[i] > 4.0) s.barrier_left = BARRIER_WALL;
				if (side_r - ys[i] > 4.0) s.barrier_right = BARRIER_WALL;
				break;
			case RK_FARM:
				s.lanes = 1;
				s.marking = 0;
				s.road_surface = SURF_DIRT;
				s.shoulder_left = s.shoulder_right = 1.0;
				s.shoulder_surface = SURF_GRASS;
				break;
			case RK_TOUGE:
				s.marking = 4;
				s.shoulder_left = s.shoulder_right = 0.9;
				s.shoulder_surface = SURF_GRAVEL;
				// Valley side: guardrail. Mountain side: concrete retaining wall where cut.
				s.barrier_left = side_l > ys[i] + 3.0 ? BARRIER_WALL : (side_l < ys[i] - 1.5 ? BARRIER_GUARDRAIL : BARRIER_NONE);
				s.barrier_right = side_r > ys[i] + 3.0 ? BARRIER_WALL : (side_r < ys[i] - 1.5 ? BARRIER_GUARDRAIL : BARRIER_NONE);
				s.road_surface = hash01(i / 60, r.def.id, 3) < 0.35 ? SURF_ASPHALT_WORN : SURF_ASPHALT;
				break;
			case RK_DOCK:
				s.marking = 5;
				s.road_surface = SURF_CONCRETE;
				s.shoulder_left = s.shoulder_right = 3.0;
				s.shoulder_surface = SURF_CONCRETE;
				break;
			default:
				break;
		}
		if (baked) {
			// Mapped width / lanes; one-way roads have no centre line.
			if (d.half_width > 0.0) s.width_left = s.width_right = d.half_width;
			if (d.lanes > 0) s.lanes = (uint8_t)(d.oneway ? d.lanes * 2 : std::max<int>(d.lanes, 2));
			if (d.oneway) s.marking = 5;
			if (d.kind == RK_STREET && d.half_width < 3.0) s.marking = 0; // narrow old-town lanes
			// Old towns: narrow pavements; hill roads: tight verges.
			if (d.kind == RK_STREET) s.shoulder_left = s.shoulder_right = d.half_width < 3.0 ? 1.2 : 2.2;
		}
		if (sx.type == ST_BRIDGE) {
			if (s.barrier_left != BARRIER_WALL) s.barrier_left = BARRIER_GUARDRAIL;
			if (s.barrier_right != BARRIER_WALL) s.barrier_right = BARRIER_GUARDRAIL;
			s.curb_left = s.curb_right = false;
			s.shoulder_surface = SURF_CONCRETE;
			s.shoulder_left = std::min(s.shoulder_left, 1.2);
			s.shoulder_right = std::min(s.shoulder_right, 1.2);
		} else if (sx.type == ST_TUNNEL) {
			s.barrier_left = s.barrier_right = BARRIER_WALL;
			s.curb_left = s.curb_right = false;
			s.shoulder_surface = SURF_CONCRETE;
			s.shoulder_left = s.shoulder_right = 1.0;
		}
		r.bmin = Vec3(std::min(r.bmin.x, s.center.x), std::min(r.bmin.y, s.center.y), std::min(r.bmin.z, s.center.z));
		r.bmax = Vec3(std::max(r.bmax.x, s.center.x), std::max(r.bmax.y, s.center.y), std::max(r.bmax.z, s.center.z));
	}
	// Tunnel mouths: samples within 25 m of either end of a tunnel run.
	for (int i = 0; i < n;) {
		if (r.samples[i].type != ST_TUNNEL) { ++i; continue; }
		int j = i;
		while (j < n && r.samples[j].type == ST_TUNNEL) ++j;
		real d0 = r.samples[i].rs.distance, d1 = r.samples[j - 1].rs.distance;
		for (int k = i; k < j; ++k) {
			real dd = r.samples[k].rs.distance;
			// Runs that start/end at the road's end continue into a neighbouring tunnel road: no mouth there.
			bool open_start = i > 0 || !d.tunnel, open_end = j < n || !d.tunnel;
			r.samples[k].portal = ((open_start && dd - d0 < 25.0) || (open_end && d1 - dd < 25.0)) ? 1 : 0;
		}
		i = j;
	}
	// Baked tunnel roads: mouths where the tunnel meets the ground at its ends.
	if (baked && d.tunnel)
		for (int k = 0; k < n; ++k) {
			real dd = r.samples[k].rs.distance;
			real ground_gap = r.samples[k].terrain_y - r.samples[k].rs.center.y;
			if ((dd < 25.0 || dist - dd < 25.0) && ground_gap < 9.0) r.samples[k].portal = 1;
		}
	// Banking on fast curved roads (never on city grids).
	if (d.kind == RK_EXPRESSWAY || d.kind == RK_TOUGE || d.kind == RK_COAST || d.kind == RK_RAMP) {
		for (int i = 0; i < n; ++i) {
			const Vec3 &a = r.samples[std::max(i - 3, 0)].rs.center;
			const Vec3 &b = r.samples[i].rs.center;
			const Vec3 &c = r.samples[std::min(i + 3, n - 1)].rs.center;
			Vec3 ab = (b - a).flat(), bc = (c - b).flat(), ac = (c - a).flat();
			real den = ab.length() * bc.length() * ac.length();
			real k = den > 1e-6 ? 2.0 * (ab.x * bc.z - ab.z * bc.x) / den : 0.0;
			real bank = clampr(k * 3.0, -0.07, 0.07); // radians, into the corner
			Vec3 fwd = r.samples[i].rs.tangent;
			r.samples[i].rs.up = Quat::from_axis_angle(fwd, -bank).rotate(Vec3(0, 1, 0));
		}
	}
	r.length = dist;
}

// Roads whose ends meet (within 4 m) share one height; each blends into it over 30 m so there's
// no step where the coast road, touge and mountain road join.
void World::weld_endpoints() {
	struct End {
		int road;
		bool at_start;
		Vec3 p;
	};
	std::vector<End> ends;
	for (int ri = 0; ri < (int)roads.size(); ++ri) {
		if (roads[ri].def.closed || roads[ri].def.height_mode == HM_EXPLICIT) continue;
		ends.push_back({ri, true, roads[ri].samples.front().rs.center});
		ends.push_back({ri, false, roads[ri].samples.back().rs.center});
	}
	std::vector<bool> done(ends.size(), false);
	for (size_t i = 0; i < ends.size(); ++i) {
		if (done[i]) continue;
		std::vector<size_t> group = {i};
		for (size_t j = i + 1; j < ends.size(); ++j)
			if (!done[j] && (ends[j].p - ends[i].p).flat().length() < 4.0) group.push_back(j);
		if (group.size() < 2) continue;
		real y = 0.0;
		for (size_t g : group) y += ends[g].p.y;
		y /= group.size();
		for (size_t g : group) {
			done[g] = true;
			Road &r = roads[ends[g].road];
			int n = (int)r.samples.size();
			real delta = y - (ends[g].at_start ? r.samples.front().rs.center.y : r.samples.back().rs.center.y);
			// Blend over enough distance to stay under ~6% extra grade (never a cliff ramp).
			int len = std::clamp((int)(std::fabs(delta) / 0.06 / 3.0), 10, n);
			for (int k = 0; k < len; ++k) {
				int idx = ends[g].at_start ? k : n - 1 - k;
				real w = 1.0 - smoothstep(0.0, (real)len, (real)k);
				r.samples[idx].rs.center.y += delta * w;
			}
		}
	}
}

// Where two roads meet or run alongside each other at a similar height (junctions, ramp merges),
// remove barriers and curbs so neither road's furniture blocks the other's carriageway.
void World::open_merges() {
	const real cell = 16.0;
	struct Ref {
		int road, sample;
	};
	std::unordered_map<int64_t, std::vector<Ref>> grid;
	auto key = [&](real x, real z) { return ((int64_t)std::floor(x / cell) << 32) ^ (int64_t)(uint32_t)(int32_t)std::floor(z / cell); };
	for (int ri = 0; ri < (int)roads.size(); ++ri)
		for (int si = 0; si < (int)roads[ri].samples.size(); ++si) {
			const Vec3 &p = roads[ri].samples[si].rs.center;
			grid[key(p.x, p.z)].push_back({ri, si});
		}
	for (int ri = 0; ri < (int)roads.size(); ++ri) {
		Road &r = roads[ri];
		int n = (int)r.samples.size();
		std::vector<uint8_t> open(n, 0);
		for (int si = 0; si < n; ++si) {
			const RoadSample &a = r.samples[si].rs;
			real reach_a = std::max(a.width_left + a.shoulder_left, a.width_right + a.shoulder_right);
			bool hit = false;
			for (int dx = -1; dx <= 1 && !hit; ++dx)
				for (int dz = -1; dz <= 1 && !hit; ++dz) {
					auto it = grid.find(key(a.center.x + dx * cell, a.center.z + dz * cell));
					if (it == grid.end()) continue;
					for (const Ref &ref : it->second) {
						if (ref.road == ri) continue;
						const RoadSample &b = roads[ref.road].samples[ref.sample].rs;
						if (std::fabs(b.center.y - a.center.y) > 3.0) continue;
						real reach_b = std::max(b.width_left + b.shoulder_left, b.width_right + b.shoulder_right);
						real d = std::sqrt(sqr(a.center.x - b.center.x) + sqr(a.center.z - b.center.z));
						if (d < reach_a + reach_b + 1.5) {
							hit = true;
							break;
						}
					}
				}
			if (hit) open[si] = 1;
		}
		// Dilate by 15 m either way so the merge mouth is fully open.
		for (int si = 0; si < n; ++si) {
			bool near = false;
			for (int k = -5; k <= 5 && !near; ++k) {
				int j = si + k;
				if (r.def.closed) j = (j % n + n) % n;
				if (j >= 0 && j < n && open[j]) near = true;
			}
			if (!near) continue;
			RoadSample &s = r.samples[si].rs;
			s.barrier_left = s.barrier_right = BARRIER_NONE;
			s.curb_left = s.curb_right = false;
		}
	}
}

void World::carve_roads() {
	for (const Road &r : roads) {
		int n = (int)r.samples.size();
		real blend;
		uint8_t mat;
		switch (r.def.kind) {
			case RK_STREET: case RK_AVENUE: case RK_DOCK: blend = 6.0; mat = 5; break;
			case RK_TOUGE: blend = 26.0; mat = 1; break;
			case RK_COAST: blend = 22.0; mat = 1; break;
			case RK_FARM: blend = 8.0; mat = 1; break;
			default: blend = 18.0; mat = 1; break;
		}
		for (int i = 0; i + 1 < n; ++i) {
			const RoadSampleX &a = r.samples[i];
			const RoadSampleX &b = r.samples[i + 1];
			real hwid = std::max(a.rs.width_left + a.rs.shoulder_left, a.rs.width_right + a.rs.shoulder_right) + 0.5;
			if (a.type == ST_GROUND && b.type == ST_GROUND) terrain.carve_segment(a.rs.center, b.rs.center, hwid, blend, mat);
			else if (a.type == ST_BRIDGE) terrain.keep_below(a.rs.center, b.rs.center, hwid + 1.0, 4.5);
		}
	}
	for (const Intersection &j : junctions) {
		if (!j.poly.empty()) {
			// Polygon junction: flatten a fan of strips from the centre to every edge midpoint.
			for (size_t k = 0; k < j.poly.size(); ++k) {
				const Vec3 &a = j.poly[k], &b = j.poly[(k + 1) % j.poly.size()];
				Vec3 mid = (a + b) * 0.5;
				Vec3 c = j.center;
				mid.y = j.center.y;
				terrain.carve_segment(c, mid, std::max(2.5, distance(a, b) * 0.5), 6.0, 5);
			}
			continue;
		}
		// Rectangles: carve along the longer axis with the shorter half-extent as width.
		bool along_x = j.half_x >= j.half_z;
		Vec3 a = j.center + (along_x ? Vec3(-j.half_x, 0, 0) : Vec3(0, 0, -j.half_z));
		Vec3 b = j.center + (along_x ? Vec3(j.half_x, 0, 0) : Vec3(0, 0, j.half_z));
		terrain.carve_segment(a, b, (along_x ? j.half_z : j.half_x) + 2.0, 8.0, 5);
	}
}

// ---------------------------------------------------------------------------------------------
// Points of interest

void World::layout_pois() {
	auto add = [&](PoiType t, const std::string &id, const Vec3 &p, real yaw, const std::string &data = "") {
		Poi poi;
		poi.type = t;
		poi.id = id;
		poi.pos = Vec3(p.x, height(p.x, p.z), p.z);
		poi.yaw = yaw;
		poi.data = data;
		NearestRoad nr = nearest_road(poi.pos, 80.0);
		poi.road = nr.road;
		poi.road_s = nr.s;
		pois.push_back(poi);
	};
	add(POI_FESTIVAL, "festival", Vec3(2380, 0, -330), 0.0);
	add(POI_SPAWN, "spawn_festival", Vec3(2380, 0, -160), PI);
	add(POI_GARAGE, "garage_daikoku", Vec3(2440, 0, -380), 0.0);
	add(POI_GARAGE, "garage_shibuya", Vec3(-160, 0, -140), 0.0);
	add(POI_GARAGE, "garage_akina", TOUGE_PASS + Vec3(30, 0, 20), 0.0);
	add(POI_FAST_TRAVEL, "ft_shibuya", Vec3(0, 0, 0), 0.0);
	add(POI_FAST_TRAVEL, "ft_docks", Vec3(2750, 0, 550), 0.0);
	add(POI_FAST_TRAVEL, "ft_akina_summit", TOUGE_PASS, 0.0);
	add(POI_FAST_TRAVEL, "ft_satoyama", Vec3(-2000, 0, -2250), 0.0);
	add(POI_LANDMARK, "tower", Vec3(420, 0, -420), 0.0, "lattice_tower");
	add(POI_LANDMARK, "ferris", Vec3(2900, 0, 900), 0.0, "ferris_wheel");
	add(POI_LANDMARK, "pagoda", Vec3(-2150, 0, -1700), 0.0, "pagoda");
	add(POI_LANDMARK, "lighthouse", Vec3(-1500, 0, coast_z(-1500) - 60), 0.0, "lighthouse");
	add(POI_LANDMARK, "bridge", Vec3(3300, 0, -700), 0.0, "suspension_bridge");
	// Omamori collectibles scattered across districts (deterministic).
	Rng rng(seed * 977 + 3);
	int placed = 0;
	for (int tries = 0; placed < 30 && tries < 4000; ++tries) {
		if (roads.empty()) break;
		const Road &r = roads[rng.irange(0, (int)roads.size() - 1)];
		const RoadSampleX &s = r.samples[rng.irange(0, (int)r.samples.size() - 1)];
		if (s.type != ST_GROUND) continue;
		Vec3 right = s.rs.tangent.cross(Vec3(0, 1, 0)).normalized();
		Vec3 p = s.rs.center + right * (s.rs.width_right + s.rs.shoulder_right + 3.0);
		char id[32];
		std::snprintf(id, sizeof(id), "omamori_%02d", placed);
		add(POI_OMAMORI, id, p, 0.0);
		placed++;
	}
}

// ---------------------------------------------------------------------------------------------
// Queries

NearestRoad World::nearest_road(const Vec3 &p, real max_dist) const {
	NearestRoad best;
	best.distance = max_dist;
	for (size_t ri = 0; ri < roads.size(); ++ri) {
		const Road &r = roads[ri];
		if (p.x < r.bmin.x - max_dist || p.x > r.bmax.x + max_dist || p.z < r.bmin.z - max_dist || p.z > r.bmax.z + max_dist) continue;
		for (size_t i = 0; i < r.samples.size(); ++i) {
			const RoadSample &s = r.samples[i].rs;
			real d = std::sqrt(sqr(s.center.x - p.x) + sqr(s.center.z - p.z) + 0.25 * sqr(s.center.y - p.y));
			if (d < best.distance) {
				best.distance = d;
				best.road = (int)ri;
				best.sample = (int)i;
				best.s = s.distance;
				Vec3 right = s.tangent.cross(Vec3(0, 1, 0)).normalized();
				best.lateral = (p - s.center).dot(right);
			}
		}
	}
	return best;
}

void World::chunk_bounds(int cx, int cz, Vec3 &mn, Vec3 &mx) const {
	mn = Vec3(min_x() + cx * CHUNK, -1e6, min_z() + cz * CHUNK);
	mx = Vec3(mn.x + CHUNK, 1e6, mn.z + CHUNK);
}

std::vector<World::RoadSpan> World::roads_in_chunk(int cx, int cz, real margin) const {
	Vec3 mn, mx;
	chunk_bounds(cx, cz, mn, mx);
	std::vector<RoadSpan> out;
	for (size_t ri = 0; ri < roads.size(); ++ri) {
		const Road &r = roads[ri];
		if (r.bmax.x < mn.x - margin || r.bmin.x > mx.x + margin || r.bmax.z < mn.z - margin || r.bmin.z > mx.z + margin) continue;
		int n = (int)r.samples.size();
		int i = 0;
		while (i < n) {
			// A sample belongs to the chunk that contains its centre; spans include one extra
			// sample so consecutive chunks share the seam quad.
			auto inside = [&](int k) {
				const Vec3 &c = r.samples[k].rs.center;
				return c.x >= mn.x && c.x < mx.x && c.z >= mn.z && c.z < mx.z;
			};
			if (!inside(i)) { ++i; continue; }
			int j = i;
			while (j < n && inside(j)) ++j;
			RoadSpan span;
			span.road = (int)ri;
			span.begin = i;
			span.end = std::min(j + 1, n); // include the next sample to close the seam
			out.push_back(span);
			i = j;
		}
	}
	return out;
}

} // namespace nt
