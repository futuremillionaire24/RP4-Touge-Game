// Loader for tools/mapbake "NTMB" blobs: the real Riviera map (OpenStreetMap + terrain tiles).
// Sections (little endian): HGT (8 m u16 heights), LAND (u8 classes), DIST (district grid + names),
// ROAD (baked edges with explicit heights), JUNC (junction polygons), BLDG (footprints), TREE,
// POIS, ROUT (event routes), END.
#include "world.h"

#include "../rng.h"

#include <algorithm>
#include <cstring>
#include <thread>

namespace nt {

namespace {

struct Reader {
	const uint8_t *p, *end;
	bool ok = true;
	bool need(size_t n) {
		if ((size_t)(end - p) < n) ok = false;
		return ok;
	}
	uint8_t u8() { return need(1) ? *p++ : 0; }
	uint16_t u16() {
		if (!need(2)) return 0;
		uint16_t v;
		std::memcpy(&v, p, 2);
		p += 2;
		return v;
	}
	uint32_t u32() {
		if (!need(4)) return 0;
		uint32_t v;
		std::memcpy(&v, p, 4);
		p += 4;
		return v;
	}
	int32_t i32() { return (int32_t)u32(); }
	float f32() {
		if (!need(4)) return 0.0f;
		float v;
		std::memcpy(&v, p, 4);
		p += 4;
		return v;
	}
	std::string str() {
		uint16_t n = u16();
		if (!need(n)) return {};
		std::string s((const char *)p, n);
		p += n;
		return s;
	}
	bool tag(const char *t) {
		if (!need(4) || std::memcmp(p, t, 4) != 0) return ok = false;
		p += 4;
		return true;
	}
	template <typename T>
	void array(std::vector<T> &v, size_t n) {
		if (!need(n * sizeof(T))) return;
		v.resize(n);
		std::memcpy(v.data(), p, n * sizeof(T));
		p += n * sizeof(T);
	}
};

// Catmull-Rom weight row for bicubic sampling.
inline void cubic_w(real t, real w[4]) {
	real t2 = t * t, t3 = t2 * t;
	w[0] = -0.5 * t3 + t2 - 0.5 * t;
	w[1] = 1.5 * t3 - 2.5 * t2 + 1.0;
	w[2] = -1.5 * t3 + 2.0 * t2 + 0.5 * t;
	w[3] = 0.5 * t3 - 0.5 * t2;
}

} // namespace

real World::bake_height(real x, real z) const {
	real fx = (x - bake_x0_) / bake_cell_, fz = (z - bake_z0_) / bake_cell_;
	int ix = (int)std::floor(fx), iz = (int)std::floor(fz);
	real wx[4], wz[4];
	cubic_w(fx - ix, wx);
	cubic_w(fz - iz, wz);
	real h = 0.0;
	for (int j = 0; j < 4; ++j) {
		int zz = std::clamp(iz - 1 + j, 0, bake_hgt_ - 1);
		real row = 0.0;
		for (int i = 0; i < 4; ++i) {
			int xx = std::clamp(ix - 1 + i, 0, bake_w_ - 1);
			row += wx[i] * (bake_h_[(size_t)zz * bake_w_ + xx] * 0.05 - 100.0);
		}
		h += wz[j] * row;
	}
	return h;
}

uint8_t World::land_at(real x, real z) const {
	if (!baked) return LAND_SCRUB;
	int i = std::clamp((int)std::lround((x - bake_x0_) / bake_cell_), 0, bake_w_ - 1);
	int j = std::clamp((int)std::lround((z - bake_z0_) / bake_cell_), 0, bake_hgt_ - 1);
	return bake_land_[(size_t)j * bake_w_ + i];
}

const std::vector<int> &World::roads_at_node(int64_t node) const {
	static const std::vector<int> none;
	auto it = node_roads_.find(node);
	return it == node_roads_.end() ? none : it->second;
}

void World::index_nodes() {
	node_roads_.clear();
	for (int i = 0; i < (int)roads.size(); ++i) {
		const RoadDef &d = roads[i].def;
		if (d.node_a >= 0) node_roads_[d.node_a].push_back(i);
		if (d.node_b >= 0) node_roads_[d.node_b].push_back(i);
	}
}

bool World::build_from_bake(const uint8_t *data, size_t size, std::string &error) {
	Reader r{data, data + size};
	if (!r.tag("NTMB") || r.u32() != 1) {
		error = "not an NTMB v1 map";
		return false;
	}
	baked = true;
	seed = 1;
	roads.clear();
	junctions.clear();
	blocks.clear();
	pois.clear();
	defs_.clear();
	buildings.clear();
	trees.clear();
	routes.clear();
	district_names.clear();

	// Heights + land classes.
	if (!r.tag("HGT ")) return (error = "missing HGT"), false;
	bake_x0_ = r.f32();
	bake_z0_ = r.f32();
	bake_cell_ = r.f32();
	bake_w_ = (int)r.u32();
	bake_hgt_ = (int)r.u32();
	r.array(bake_h_, (size_t)bake_w_ * bake_hgt_);
	if (!r.tag("LAND")) return (error = "missing LAND"), false;
	r.array(bake_land_, (size_t)bake_w_ * bake_hgt_);
	if (!r.tag("DIST")) return (error = "missing DIST"), false;
	dist_cell_ = r.f32();
	dist_w_ = (int)r.u32();
	dist_h_ = (int)r.u32();
	int nd = r.u8();
	for (int k = 0; k < nd; ++k) district_names.push_back(r.str());
	r.array(bake_dist_, (size_t)dist_w_ * dist_h_);
	if (!r.ok) return (error = "truncated grids"), false;

	// Engine terrain at 4 m, bicubic from the 8 m bake plus fine detail the DEM can't resolve.
	real size_x = (bake_w_ - 1) * bake_cell_, size_z = (bake_hgt_ - 1) * bake_cell_;
	terrain.init(bake_x0_, bake_z0_, size_x, size_z, 4.0);
	const int rows = terrain.height();
	unsigned threads = std::max(1u, std::min(8u, std::thread::hardware_concurrency()));
	std::vector<std::thread> pool;
	int band = (rows + (int)threads - 1) / (int)threads;
	for (unsigned t = 0; t < threads; ++t) {
		int r0 = (int)t * band, r1 = std::min(rows, r0 + band);
		if (r0 >= r1) break;
		pool.emplace_back([this, r0, r1] { terrain.fill_rows(r0, r1, [this](real x, real z, uint8_t &m) { return base_height(x, z, m); }); });
	}
	for (auto &th : pool) th.join();

	// Roads.
	if (!r.tag("ROAD")) return (error = "missing ROAD"), false;
	uint32_t nr = r.u32();
	for (uint32_t k = 0; k < nr && r.ok; ++k) {
		RoadDef d;
		d.id = (int)k;
		d.name = r.str();
		d.label = r.str();
		d.kind = (RoadKind)std::min<uint8_t>(r.u8(), RK_COUNT - 1);
		uint8_t fl = r.u8();
		d.oneway = (fl & 1) ? 1 : (fl & 2) ? -1 : 0;
		d.bridge = fl & 4;
		d.tunnel = fl & 8;
		d.roundabout = fl & 16;
		d.race_only = fl & 32;
		d.lanes = r.u8();
		d.speed_limit = r.u8();
		d.half_width = r.f32();
		uint8_t dist = r.u8();
		d.district = (District)std::min<int>(dist, 255);
		d.node_a = r.i32();
		d.node_b = r.i32();
		uint32_t np = r.u32();
		d.ctrl.reserve(np);
		for (uint32_t q = 0; q < np && r.ok; ++q) {
			real x = r.f32(), y = r.f32(), z = r.f32();
			d.ctrl.push_back(Vec3(x, y, z));
		}
		d.height_mode = HM_EXPLICIT;
		d.max_grade = 0.25;
		defs_.push_back(std::move(d));
	}
	// Junctions.
	if (!r.tag("JUNC")) return (error = "missing JUNC"), false;
	uint32_t nj = r.u32();
	for (uint32_t k = 0; k < nj && r.ok; ++k) {
		Intersection it;
		real x = r.f32(), y = r.f32(), z = r.f32();
		it.center = Vec3(x, y, z);
		it.style = r.u8();
		int n = r.u8();
		real ext = 0.0;
		for (int q = 0; q < n; ++q) {
			real px = r.f32(), py = r.f32(), pz = r.f32();
			it.poly.push_back(Vec3(px, py, pz));
			ext = std::max(ext, (Vec3(px, py, pz) - it.center).flat().length());
		}
		it.half_x = it.half_z = ext;
		int nl = r.u8();
		for (int q = 0; q < nl; ++q) it.legs.push_back(r.i32());
		junctions.push_back(std::move(it));
	}
	// Buildings.
	if (!r.tag("BLDG")) return (error = "missing BLDG"), false;
	uint32_t nb = r.u32();
	buildings.reserve(nb);
	for (uint32_t k = 0; k < nb && r.ok; ++k) {
		Building b;
		b.base = r.f32();
		b.top = r.f32();
		b.style = r.u8();
		b.roof = r.u8();
		b.r = r.u8();
		b.g = r.u8();
		b.b = r.u8();
		int n = r.u16();
		Vec3 c;
		for (int q = 0; q < n; ++q) {
			real x = r.f32(), z = r.f32();
			b.ring.push_back(Vec3(x, 0, z));
			c += Vec3(x, 0, z);
		}
		b.center = n ? c / (real)n : Vec3();
		for (const Vec3 &p : b.ring) b.radius = std::max(b.radius, (p - b.center).length());
		buildings.push_back(std::move(b));
	}
	if (!r.tag("TREE")) return (error = "missing TREE"), false;
	uint32_t nt_ = r.u32();
	trees.reserve(nt_);
	for (uint32_t k = 0; k < nt_ && r.ok; ++k) {
		Tree t;
		t.x = r.f32();
		t.z = r.f32();
		t.kind = r.u8();
		t.height_dm = r.u8();
		trees.push_back(t);
	}
	if (!r.tag("POIS")) return (error = "missing POIS"), false;
	uint32_t np = r.u32();
	std::vector<Poi> baked_pois;
	for (uint32_t k = 0; k < np && r.ok; ++k) {
		Poi p;
		p.type = (PoiType)r.u8();
		p.id = r.str();
		real x = r.f32(), y = r.f32(), z = r.f32();
		p.pos = Vec3(x, y, z);
		p.yaw = r.f32();
		p.data = r.str();
		baked_pois.push_back(p);
	}
	if (!r.tag("ROUT")) return (error = "missing ROUT"), false;
	uint32_t nro = r.u32();
	for (uint32_t k = 0; k < nro && r.ok; ++k) {
		Route rt;
		rt.id = r.str();
		rt.name = r.str();
		rt.closed = r.u8() != 0;
		uint32_t n = r.u32();
		for (uint32_t q = 0; q < n; ++q) {
			int32_t v = r.i32();
			int idx = std::abs(v) - 1;
			if (idx < 0 || idx >= (int)defs_.size()) continue;
			rt.roads.push_back((v < 0 ? "~" : "") + defs_[idx].name);
		}
		routes.push_back(std::move(rt));
	}
	if (!r.ok || !r.tag("END ")) return (error = "truncated map"), false;

	// Process roads exactly like the generated map (geometry, then furniture on final heights).
	for (RoadDef &d : defs_) {
		Road road;
		road.def = d;
		process_road(road);
		if (road.samples.size() >= 2) roads.push_back(std::move(road));
	}
	for (Road &road : roads) process_road(road);
	index_nodes();
	open_merges();
	carve_roads();

	// POIs: baked ones (snapped to roads) + collectibles scattered along the network.
	for (Poi &p : baked_pois) {
		p.pos.y = height(p.pos.x, p.pos.z);
		NearestRoad nrd = nearest_road(p.pos, 80.0);
		p.road = nrd.road;
		p.road_s = nrd.s;
		pois.push_back(p);
	}
	Rng rng(977 + 3);
	int placed = 0;
	for (int tries = 0; placed < 40 && tries < 8000 && !roads.empty(); ++tries) {
		const Road &rd = roads[rng.irange(0, (int)roads.size() - 1)];
		if (rd.def.kind == RK_EXPRESSWAY || rd.def.tunnel || rd.def.bridge) continue;
		const RoadSampleX &s = rd.samples[rng.irange(0, (int)rd.samples.size() - 1)];
		Vec3 right = s.rs.tangent.cross(Vec3(0, 1, 0)).normalized();
		Vec3 p = s.rs.center + right * (s.rs.width_right + s.rs.shoulder_right + 2.5);
		Poi poi;
		poi.type = POI_OMAMORI;
		char id[32];
		std::snprintf(id, sizeof(id), "collectible_%02d", placed);
		poi.id = id;
		poi.pos = Vec3(p.x, height(p.x, p.z), p.z);
		poi.road = (int)(&rd - roads.data());
		poi.road_s = s.rs.distance;
		pois.push_back(poi);
		placed++;
	}
	return true;
}

} // namespace nt
