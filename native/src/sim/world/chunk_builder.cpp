#include "chunk_builder.h"

#include "../rng.h"

#include <algorithm>

namespace nt {

namespace {

struct Vec2 {
	real x, y;
};

struct Ctx {
	const World &w;
	const ChunkOptions &opt;
	ChunkOutput &out;
	Vec3 mn, mx;
	std::vector<const RoadSampleX *> nearby; // road samples within the chunk (+margin)
	std::vector<const RoadSampleX *> tunnels;
	std::vector<const Building *> near_buildings; // baked footprints in/around the chunk
	bool in_chunk(real x, real z) const { return x >= mn.x && x < mx.x && z >= mn.z && z < mx.z; }
};

bool point_in_ring(const std::vector<Vec3> &ring, real x, real z) {
	bool in = false;
	for (size_t a = 0, b = ring.size() - 1; a < ring.size(); b = a++) {
		const Vec3 &p = ring[a], &q = ring[b];
		if ((p.z > z) != (q.z > z) && x < (q.x - p.x) * (z - p.z) / (q.z - p.z) + p.x) in = !in;
	}
	return in;
}

void add_prop(Ctx &c, PropType t, const Vec3 &p, real yaw, const Vec3 &scale, real color) {
	if (!c.opt.props) return;
	PropInstance pi{(float)p.x, (float)p.y, (float)p.z, (float)yaw, (float)scale.x, (float)scale.y, (float)scale.z, (float)color};
	c.out.props[t].push_back(pi);
}

void add_light(Ctx &c, const Vec3 &p, real intensity, real hue) {
	c.out.lights.insert(c.out.lights.end(), {(float)p.x, (float)p.y, (float)p.z, (float)intensity, (float)hue});
}

void quad(MeshData &m, const Vec3 &a, const Vec3 &b, const Vec3 &cc, const Vec3 &d, const Vec3 &n, const Vec2 &ua, const Vec2 &ub, const Vec2 &uc,
		const Vec2 &ud, real u2 = 0, real v2 = 0, real ao = 1) {
	int i = m.vertex_count();
	m.add_vertex(a, n, ua.x, ua.y, u2, v2, ao);
	m.add_vertex(b, n, ub.x, ub.y, u2, v2, ao);
	m.add_vertex(cc, n, uc.x, uc.y, u2, v2, ao);
	m.add_vertex(d, n, ud.x, ud.y, u2, v2, ao);
	// Corners are given counter-clockwise seen from the side `n` points to.
	Vec3 fn = (b - a).cross(cc - a);
	if (fn.dot(n) >= 0) m.add_quad(i, i + 1, i + 2, i + 3);
	else m.add_quad(i, i + 3, i + 2, i + 1);
}

void quad_color(MeshData &m, const Vec3 &a, const Vec3 &b, const Vec3 &cc, const Vec3 &d, const Vec3 &n, const Vec2 &ua, const Vec2 &ub, const Vec2 &uc,
		const Vec2 &ud, real u2, real v2, real r, real g, real b_col, real a_col) {
	int i = m.vertex_count();
	m.add_vertex(a, n, ua.x, ua.y, u2, v2, r, g, b_col, a_col);
	m.add_vertex(b, n, ub.x, ub.y, u2, v2, r, g, b_col, a_col);
	m.add_vertex(cc, n, uc.x, uc.y, u2, v2, r, g, b_col, a_col);
	m.add_vertex(d, n, ud.x, ud.y, u2, v2, r, g, b_col, a_col);
	Vec3 fn = (b - a).cross(cc - a);
	if (fn.dot(n) >= 0) m.add_quad(i, i + 1, i + 2, i + 3);
	else m.add_quad(i, i + 3, i + 2, i + 1);
}

// ---- Terrain ---------------------------------------------------------------------------

uint8_t terrain_surface(int mat) {
	switch (mat) {
		case 1: return SURF_DIRT;
		case 2: return SURF_DIRT;
		case 3: return SURF_SAND;
		case 4: return SURF_GRASS;
		case 5: return SURF_CONCRETE;
		default: return SURF_GRASS;
	}
}

bool tunnel_hole(const Ctx &c, real x, real z, real h) {
	for (const RoadSampleX *s : c.tunnels) {
		// Real map: the ground only opens at tunnel mouths (city streets run over shallow tunnels).
		if (c.w.baked && !s->portal) continue;
		real hw = std::max(s->rs.width_left, s->rs.width_right) + 3.0;
		real d2 = sqr(s->rs.center.x - x) + sqr(s->rs.center.z - z);
		if (d2 < hw * hw && h < s->rs.center.y + 11.0) return true;
	}
	return false;
}

void build_terrain(Ctx &c) {
	const World &w = c.w;
	int step_m = 4 << std::clamp(c.opt.lod, 0, 3);
	int n = (int)(World::CHUNK / step_m);
	MeshData &m = c.out.groups[WG_TERRAIN];
	int base = m.vertex_count();
	for (int iz = 0; iz <= n; ++iz) {
		for (int ix = 0; ix <= n; ++ix) {
			real x = c.mn.x + ix * step_m, z = c.mn.z + iz * step_m;
			real h = w.terrain.sample(x, z);
			Vec3 nrm = w.terrain.normal(x, z);
			int mat = w.terrain.material(x, z);
			// COLOR: r rock, g sand, b urban, a farm. UV2: x forest, y park. Scrub is the default.
			real rock = mat == 2 ? 1.0 : 0.0;
			rock = std::max(rock, smoothstep(0.62, 0.78, 1.0 - nrm.y)); // steep = rock
			m.positions.insert(m.positions.end(), {(float)x, (float)h, (float)z});
			m.normals.insert(m.normals.end(), {(float)nrm.x, (float)nrm.y, (float)nrm.z});
			m.uvs.insert(m.uvs.end(), {(float)(x / 8.0), (float)(z / 8.0)});
			m.uv2s.insert(m.uv2s.end(), {mat == 1 ? 1.0f : 0.0f, mat == 6 ? 1.0f : 0.0f});
			m.colors.insert(m.colors.end(), {(float)rock, mat == 3 ? 1.0f : 0.0f, mat == 5 ? 1.0f : 0.0f, mat == 4 ? 1.0f : 0.0f});
			c.out.min_y = std::min(c.out.min_y, h);
			c.out.max_y = std::max(c.out.max_y, h);
		}
	}
	auto idx = [&](int ix, int iz) { return base + iz * (n + 1) + ix; };
	for (int iz = 0; iz < n; ++iz)
		for (int ix = 0; ix < n; ++ix) {
			real cx = c.mn.x + (ix + 0.5) * step_m, cz = c.mn.z + (iz + 0.5) * step_m;
			if (!c.tunnels.empty() && tunnel_hole(c, cx, cz, w.terrain.sample(cx, cz))) continue;
			// Seen from above: (ix,iz)->(ix,iz+1)->(ix+1,iz+1)->(ix+1,iz) is counter-clockwise.
			m.add_quad(idx(ix, iz), idx(ix, iz + 1), idx(ix + 1, iz + 1), idx(ix + 1, iz));
		}
	// Skirts hide cracks between chunks at different LODs.
	if (c.opt.lod > 0) {
		auto skirt = [&](int ax, int az, int bx, int bz, Vec3 outward) {
			Vec3 a(c.mn.x + ax * step_m, 0, c.mn.z + az * step_m), b(c.mn.x + bx * step_m, 0, c.mn.z + bz * step_m);
			a.y = w.terrain.sample(a.x, a.z);
			b.y = w.terrain.sample(b.x, b.z);
			quad(m, a, b, b - Vec3(0, 6, 0), a - Vec3(0, 6, 0), outward, {0, 0}, {1, 0}, {1, 1}, {0, 1});
		};
		for (int k = 0; k < n; ++k) {
			skirt(k, 0, k + 1, 0, Vec3(0, 0, -1));
			skirt(k + 1, n, k, n, Vec3(0, 0, 1));
			skirt(0, k + 1, 0, k, Vec3(-1, 0, 0));
			skirt(n, k, n, k + 1, Vec3(1, 0, 0));
		}
	}
	// Collision always at 4 m resolution.
	if (c.opt.collision) {
		const int cn = (int)(World::CHUNK / 4.0);
		for (int iz = 0; iz < cn; ++iz)
			for (int ix = 0; ix < cn; ++ix) {
				real x0 = c.mn.x + ix * 4.0, z0 = c.mn.z + iz * 4.0;
				real ccx = x0 + 2.0, ccz = z0 + 2.0;
				if (!c.tunnels.empty() && tunnel_hole(c, ccx, ccz, w.terrain.sample(ccx, ccz))) continue;
				Vec3 a(x0, w.terrain.sample(x0, z0), z0), b(x0, w.terrain.sample(x0, z0 + 4), z0 + 4);
				Vec3 d(x0 + 4, w.terrain.sample(x0 + 4, z0), z0), e(x0 + 4, w.terrain.sample(x0 + 4, z0 + 4), z0 + 4);
				uint8_t s = terrain_surface(w.terrain.material(ccx, ccz));
				c.out.collision.add_tri(a, b, e, s, COL_ALL);
				c.out.collision.add_tri(a, e, d, s, COL_ALL);
			}
	}
	// Sea surface.
	if (c.out.min_y < 0.5) {
		MeshData &wm = c.out.groups[WG_WATER];
		Vec3 a(c.mn.x, 0, c.mn.z), b(c.mn.x, 0, c.mx.z), cc(c.mx.x, 0, c.mx.z), d(c.mx.x, 0, c.mn.z);
		quad(wm, a, b, cc, d, Vec3(0, 1, 0), {(float)(a.x / 16), (float)(a.z / 16)}, {(float)(b.x / 16), (float)(b.z / 16)},
				{(float)(cc.x / 16), (float)(cc.z / 16)}, {(float)(d.x / 16), (float)(d.z / 16)});
	}
}

// ---- Roads, tunnels, bridges, roadside furniture ---------------------------------------

// Concrete portal at a tunnel mouth: a headwall wider and taller than the hole the terrain opens
// around the bore (tunnel_hole: road width + 3 m, 11 m up), filled in around the arch, and splayed
// wingwalls retaining the approach cutting. `face` = -1 at an entry (faces back down the road),
// +1 at an exit. GROUP_WALL, UV2.x = 2 (wall shader: portal concrete), UV2.y = metres from the arch
// edge (hazard chevrons), UV = metres.
void tunnel_portal(Ctx &c, const RoadSample &s, const Vec3 &right, real out_l, real out_r, real crown, real face) {
	MeshData &m = c.out.groups[GROUP_WALL];
	Vec3 fwd = s.tangent.flat().normalized() * face; // out of the bore
	const real W = std::max(out_l, out_r) + 5.0, H = crown + 5.0;
	auto at = [&](real x, real y) { return s.center + right * x + Vec3(0, y, 0); };
	auto arch = [&](real a) {
		real x = -std::cos(a) * (a < PI * 0.5 ? out_l : out_r);
		return Vec2{x, 1.0 + std::sin(a) * (crown - 1.0)};
	};
	auto q = [&](Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, real d0, real d1, real d2, real d3) {
		int i = m.vertex_count();
		Vec2 ps[4] = {p0, p1, p2, p3};
		real ds[4] = {d0, d1, d2, d3};
		for (int k = 0; k < 4; ++k) m.add_vertex(at(ps[k].x, ps[k].y), fwd, ps[k].x, ps[k].y, 2.0, ds[k], 0.9);
		Vec3 fn = (at(p1.x, p1.y) - at(p0.x, p0.y)).cross(at(p2.x, p2.y) - at(p0.x, p0.y));
		if (fn.dot(fwd) >= 0) m.add_quad(i, i + 1, i + 2, i + 3);
		else m.add_quad(i, i + 3, i + 2, i + 1);
	};
	// Piers either side of the opening, then the face above the arch, one strip per arch segment.
	q({-W, -1.0}, {-out_l, -1.0}, {-out_l, H}, {-W, H}, W - out_l, 0.0, 0.0, W - out_l);
	q({out_r, -1.0}, {W, -1.0}, {W, H}, {out_r, H}, 0.0, W - out_r, W - out_r, 0.0);
	const int arc = 8;
	for (int k = 0; k < arc; ++k) {
		Vec2 p0 = arch(PI * k / arc), p1 = arch(PI * (k + 1) / arc);
		q(p0, p1, {p1.x, H}, {p0.x, H}, 0.0, 0.0, H - p1.y, H - p0.y);
	}
	// Wingwalls: along the approach (straight, so kept short enough for curved approaches),
	// stepping down from the headwall to 2 m. Left out where a junction sits at the mouth. Portal
	// pieces are visual only (no collision): they must never close a carriageway.
	const real L = 8.0;
	for (const Intersection &j : c.w.junctions)
		if ((j.center - s.center).flat().length() < j.half_x + L + 4.0) return;
	for (real side : {-1.0, 1.0}) {
		real x = side < 0 ? -(out_l + 0.2) : out_r + 0.2;
		Vec3 b0 = at(x, -1.0), t0 = at(x, H);
		Vec3 b1 = b0 + fwd * L, t1 = b1 + Vec3(0, 3.0, 0);
		Vec3 n = right * -side; // faces the road
		quad(m, b0, b1, t1, t0, n, {0, -1.0f}, {(float)L, -1.0f}, {(float)L, 2.0f}, {0, (float)H}, 2.0, 3.0, 0.85);
		Vec3 back = right * (side * 0.4);
		quad(m, t0, t1, t1 + back, t0 + back, Vec3(0, 1, 0), {0, 0}, {(float)L, 0}, {(float)L, 0.4f}, {0, 0.4f}, 2.0, 3.0, 1.0);
	}
}

void build_roads(Ctx &c) {
	const World &w = c.w;
	for (const World::RoadSpan &span : w.roads_in_chunk(c.out.cx, c.out.cz)) {
		const Road &r = w.roads[span.road];
		std::vector<RoadSample> rs(r.samples.size());
		for (size_t i = 0; i < rs.size(); ++i) rs[i] = r.samples[i].rs;
		RoadBuildOptions o;
		o.closed = r.def.closed;
		o.collision = c.opt.collision;
		o.render = true;
		o.range_begin = span.begin;
		o.range_end = span.end - 1;
		if (o.range_end <= o.range_begin && !(o.closed && span.end == (int)rs.size())) continue;
		if (o.closed && span.end == (int)rs.size()) o.range_end = (int)rs.size();
		RoadMeshOutput ro;
		build_road(rs, o, ro);
		for (int g = 0; g < GROUP_COUNT; ++g) {
			MeshData &dst = c.out.groups[g];
			const MeshData &src = ro.groups[g];
			int base = dst.vertex_count();
			dst.positions.insert(dst.positions.end(), src.positions.begin(), src.positions.end());
			dst.normals.insert(dst.normals.end(), src.normals.begin(), src.normals.end());
			dst.uvs.insert(dst.uvs.end(), src.uvs.begin(), src.uvs.end());
			dst.uv2s.insert(dst.uv2s.end(), src.uv2s.begin(), src.uv2s.end());
			dst.colors.insert(dst.colors.end(), src.colors.begin(), src.colors.end());
			for (int32_t i : src.indices) dst.indices.push_back(i + base);
		}
		CollisionData &cd = c.out.collision;
		cd.positions.insert(cd.positions.end(), ro.collision.positions.begin(), ro.collision.positions.end());
		cd.surfaces.insert(cd.surfaces.end(), ro.collision.surfaces.begin(), ro.collision.surfaces.end());
		cd.flags.insert(cd.flags.end(), ro.collision.flags.begin(), ro.collision.flags.end());

		// Per-sample extras.
		int n = (int)r.samples.size();
		real last_lamp = -1e9, last_pole = -1e9, last_pier = -1e9, last_chevron = -1e9;
		real last_bench = -1e9, last_hydrant = -1e9;
		bool bollards_start = false, bollards_end = false;
		Rng rng((uint64_t)span.road * 7919 + span.begin);
		for (int i = span.begin; i < std::min(span.end, n); ++i) {
			const RoadSampleX &sx = r.samples[i];
			const RoadSample &s = sx.rs;
			if (!c.in_chunk(s.center.x, s.center.z)) continue;
			Vec3 right = s.tangent.cross(Vec3(0, 1, 0)).normalized();
			real yaw = std::atan2(-s.tangent.x, -s.tangent.z);
			real out_l = s.width_left + s.shoulder_left + (s.curb_left ? 0.9 : 0.0);
			real out_r = s.width_right + s.shoulder_right + (s.curb_right ? 0.9 : 0.0);
			int nx = std::min(i + 1, n - 1);
			const RoadSample &s1 = r.samples[nx].rs;
			Vec3 right1 = s1.tangent.cross(Vec3(0, 1, 0)).normalized();

			if (sx.type == ST_TUNNEL && i + 1 < n) {
				// Tunnel liner: arch from wall top to wall top, lit strip at the crown.
				MeshData &tm = c.out.groups[WG_TUNNEL];
				const int arc = 8;
				real crown = 7.0;
				for (int k = 0; k < arc; ++k) {
					real a0 = PI * k / arc, a1 = PI * (k + 1) / arc;
					auto P = [&](const RoadSample &q, const Vec3 &rr, real a, real ol, real orr) {
						real x = -std::cos(a) * (a < PI * 0.5 ? ol : orr);
						real y = 1.0 + std::sin(a) * (crown - 1.0);
						return q.center + rr * x + Vec3(0, y, 0);
					};
					Vec3 p00 = P(s, right, a0, out_l, out_r), p01 = P(s, right, a1, out_l, out_r);
					Vec3 p10 = P(s1, right1, a0, out_l, out_r), p11 = P(s1, right1, a1, out_l, out_r);
					Vec3 mid = (p00 + p11) * 0.5;
					Vec3 inward = ((s.center + Vec3(0, 2.5, 0)) - mid).normalized();
					quad(tm, p00, p10, p11, p01, inward, {0, (float)(s.distance / 4)}, {0, (float)(s1.distance / 4)},
							{1, (float)(s1.distance / 4)}, {1, (float)(s.distance / 4)}, k, 0, 0.8);
				}
				if (i % 2 == 0) {
					MeshData &lm = c.out.groups[WG_TUNNEL_LIGHT];
					Vec3 top = s.center + Vec3(0, crown - 0.05, 0);
					Vec3 top1 = s1.center + Vec3(0, crown - 0.05, 0);
					for (real side : {-2.2, 2.2}) {
						Vec3 a = top + right * (side - 0.15), b = top + right * (side + 0.15);
						Vec3 a1 = top1 + right1 * (side - 0.15), b1 = top1 + right1 * (side + 0.15);
						quad(lm, a, a1, b1, b, Vec3(0, -1, 0), {0, 0}, {0, 1}, {1, 1}, {1, 0});
					}
				}
				if (s.distance - last_lamp > 16.0) {
					last_lamp = s.distance;
					add_light(c, s.center + Vec3(0, crown - 0.6, 0), 0.8, 0.12);
				}
				// Portals where a real bore meets daylight: not where a tunnel runs on into the next
				// road, and not on shallow galleries (under ~3.5 m of cover the ground is opened instead).
				auto bored = [&](const RoadSampleX &q) { return q.terrain_y - q.rs.center.y >= 3.5; };
				bool entry = (i == 0 ? sx.portal != 0 : r.samples[i - 1].type != ST_TUNNEL) && bored(sx);
				bool exit = (nx == n - 1 ? (r.samples[nx].type != ST_TUNNEL || r.samples[nx].portal) : r.samples[nx].type != ST_TUNNEL) && bored(sx);
				if (entry) tunnel_portal(c, s, right, out_l, out_r, crown, -1.0);
				if (exit) tunnel_portal(c, s1, right1, out_l, out_r, crown, 1.0);
				continue;
			}
			if (sx.type == ST_BRIDGE && i + 1 < n) {
				// Deck slab underside and fascias.
				MeshData &dm = c.out.groups[WG_DECK];
				Vec3 l0 = s.center - right * (out_l + 0.3), r0 = s.center + right * (out_r + 0.3);
				Vec3 l1 = s1.center - right1 * (out_l + 0.3), r1 = s1.center + right1 * (out_r + 0.3);
				Vec3 dn(0, -1.3, 0);
				quad(dm, l0 + dn, r0 + dn, r1 + dn, l1 + dn, Vec3(0, -1, 0), {0, 0}, {1, 0}, {1, 1}, {0, 1}, 0, 0, 0.6);
				quad(dm, l0 + Vec3(0, 0.1, 0), l1 + Vec3(0, 0.1, 0), l1 + dn, l0 + dn, -right, {0, 0}, {1, 0}, {1, 1}, {0, 1});
				quad(dm, r0 + Vec3(0, 0.1, 0), r0 + dn, r1 + dn, r1 + Vec3(0, 0.1, 0), right, {0, 0}, {1, 0}, {1, 1}, {0, 1});
				if (s.distance - last_pier > 34.0) {
					last_pier = s.distance;
					real ground = w.terrain.sample(s.center.x, s.center.z);
					ground = std::max(ground, -12.0);
					real h = s.center.y - 1.3 - ground;
					if (h > 1.0) add_prop(c, PROP_PIER, Vec3(s.center.x, ground, s.center.z), yaw, Vec3((out_l + out_r) * 0.5, h, 1.0), 0.0);
				}
			}

			if (sx.type == ST_GROUND && i + 1 < n && r.samples[nx].type == ST_GROUND) {
				// Murs de soutenement: dressed limestone where the road is cut into the slope (up to
				// 6 m, with a coping stone) and where it stands on fill above a drop (down to 8 m).
				// Built on the verge line; GROUP_WALL, UV2.x = 1 (wall shader: limestone), UV = metres.
				MeshData &wm = c.out.groups[GROUP_WALL];
				real v0 = s.distance, v1 = s1.distance;
				for (real side : {-1.0, 1.0}) {
					real o = side < 0 ? out_l : out_r;
					Vec3 e0 = s.center + right * (side * o), e1 = s1.center + right1 * (side * o);
					real h0 = w.terrain.sample(e0.x, e0.z), h1 = w.terrain.sample(e1.x, e1.z);
					Vec3 face_n = right * -side; // toward the road
					if (h0 > e0.y + 1.2 && h1 > e1.y + 1.2) {
						real c0 = std::min(h0 - e0.y, 6.0), c1 = std::min(h1 - e1.y, 6.0);
						Vec3 t0 = e0 + Vec3(0, c0, 0), t1 = e1 + Vec3(0, c1, 0);
						quad(wm, e0 - Vec3(0, 0.3, 0), e1 - Vec3(0, 0.3, 0), t1, t0, face_n, {(float)v0, -0.3f}, {(float)v1, -0.3f}, {(float)v1, (float)c1}, {(float)v0, (float)c0}, 1.0, 0.0, 0.85);
						Vec3 back = right * (side * 0.45);
						quad(wm, t0, t1, t1 + back, t0 + back, Vec3(0, 1, 0), {(float)v0, 0}, {(float)v1, 0}, {(float)v1, 0.45f}, {(float)v0, 0.45f}, 1.0, 1.0, 1.0);
					} else if (e0.y > h0 + 1.2 && e1.y > h1 + 1.2) {
						real d0 = std::min(e0.y - h0, 8.0), d1 = std::min(e1.y - h1, 8.0);
						quad(wm, e0 - Vec3(0, d0 + 0.5, 0), e1 - Vec3(0, d1 + 0.5, 0), e1, e0, -face_n, {(float)v0, (float)-d0}, {(float)v1, (float)-d1}, {(float)v1, 0}, {(float)v0, 0}, 1.0, 0.0, 0.85);
					}
				}
			}

			// Lighting and poles by road kind.
			switch (r.def.kind) {
				case RK_STREET:
				case RK_AVENUE:
					// Real map: lamps staggered from side to side (one per ~26 m of street), never at a
					// junction mouth and never crowding lamps of the other roads at a plaza.
					if (w.baked ? (s.distance - last_lamp > 26.0 && s.distance > 10.0 && s.distance < r.length - 10.0 && sx.type == ST_GROUND)
								: s.distance - last_lamp > 28.0) {
						last_lamp = s.distance;
						int lamp_k = (int)(s.distance / 26.0);
						for (real side : {-1.0, 1.0}) {
							if (w.baked && ((lamp_k & 1) ? side > 0 : side < 0)) continue;
							real off = side < 0 ? out_l - 0.6 : out_r - 0.6;
							Vec3 p = s.center + right * (side * off);
							bool crowded = false;
							for (const PropInstance &o : c.out.props[PROP_STREET_LAMP])
								if (sqr(o.x - p.x) + sqr(o.z - p.z) < 14.0 * 14.0) crowded = true;
							if (crowded) continue;
							add_prop(c, PROP_STREET_LAMP, p, yaw + (side < 0 ? PI * 0.5 : -PI * 0.5), Vec3(1, 1, 1), 0.0);
							add_light(c, p + Vec3(0, 7.0, 0) - right * side * 3.2, 1.0, 0.1);
						}
					}
					// Street furniture on real sidewalks: benches with a bin beside them, hydrants, and
					// bollards guarding the kerb at the junction mouths of avenues.
					if (w.baked && sx.type == ST_GROUND) {
						real side = ((int)(s.distance / 26.0) & 1) ? -1.0 : 1.0; // opposite the lamp
						real walk = side < 0 ? s.shoulder_left : s.shoulder_right;
						real edge = side < 0 ? out_l : out_r;
						if (walk > 2.2 && s.distance - last_bench > 55.0 && s.distance > 15.0 && s.distance < r.length - 15.0) {
							last_bench = s.distance;
							Vec3 p = s.center + right * (side * (edge - 1.1));
							add_prop(c, PROP_BENCH, p, yaw + (side < 0 ? 0.0 : PI), Vec3(1, 1, 1), 0.0);
							add_prop(c, PROP_BIN, p + s.tangent * 1.4, rng.range(0, TAU), Vec3(1, 1, 1), rng.next());
						}
						if (walk > 1.5 && s.distance - last_hydrant > 95.0 && s.distance > 20.0) {
							last_hydrant = s.distance;
							real hs = -side; // the lamp side, at the kerb
							Vec3 p = s.center + right * (hs * ((hs < 0 ? out_l : out_r) - 0.5));
							add_prop(c, PROP_HYDRANT, p, rng.range(0, TAU), Vec3(1, 1, 1), 0.0);
						}
						if (r.def.kind == RK_AVENUE && r.length > 60.0 && s.shoulder_left > 1.5 && s.shoulder_right > 1.5) {
							bool at_start = !bollards_start && s.distance > 5.0;
							bool at_end = !bollards_end && s.distance > r.length - 7.0;
							if (at_start || at_end) {
								(at_start ? bollards_start : bollards_end) = true;
								for (real sd : {-1.0, 1.0})
									for (int b = -1; b <= 1; ++b) {
										Vec3 p = s.center + right * (sd * ((sd < 0 ? s.width_left : s.width_right) + 0.45)) + s.tangent * (b * 1.6);
										add_prop(c, PROP_BOLLARD, p, 0.0, Vec3(1, 1, 1), 0.0);
									}
							}
						}
					}
					// European towns bury their cables; the generated (legacy) map keeps Japanese poles.
					if (!w.baked && r.def.kind == RK_STREET && s.distance - last_pole > 31.0) {
						last_pole = s.distance;
						Vec3 p = s.center - right * (out_l - 0.3);
						add_prop(c, PROP_UTILITY_POLE, p, yaw, Vec3(1, rng.range(0.95, 1.1), 1), rng.next());
					}
					// Avenue trees: plane trees / palms between the lamps on wide streets.
					if (w.baked && r.def.kind == RK_AVENUE && sx.type == ST_GROUND && s.distance - last_pole > 14.0 && s.shoulder_left > 3.0) {
						last_pole = s.distance;
						for (real side : {-1.0, 1.0}) {
							real off = side < 0 ? out_l - 1.4 : out_r - 1.4;
							Vec3 p = s.center + right * (side * off);
							bool palm = w.district_at(p.x, p.z) % 3 == 0;
							add_prop(c, palm ? PROP_TREE_PALM : PROP_TREE_PLANE, p, rng.range(0, TAU), Vec3(1, 1, 1) * rng.range(0.85, 1.1), rng.next());
						}
					}
					if (!w.baked && rng.chance(0.02)) {
						Vec3 p = s.center + right * (out_r - 0.5);
						add_prop(c, PROP_KIOSK, p, yaw - PI * 0.5, Vec3(1, 1, 1), rng.next());
						add_light(c, p + Vec3(0, 1.2, 0) - right * 0.6, 0.25, rng.next());
					}
					break;
				case RK_EXPRESSWAY:
				case RK_RAMP:
					if (s.distance - last_lamp > 42.0) {
						last_lamp = s.distance;
						real side = ((int)(s.distance / 42.0) % 2) ? 1.0 : -1.0;
						Vec3 p = s.center + right * side * ((side < 0 ? out_l : out_r) - 0.2);
						add_prop(c, PROP_HIGHWAY_LAMP, p + Vec3(0, 1.1, 0), yaw + (side < 0 ? PI * 0.5 : -PI * 0.5), Vec3(1, 1, 1), 0.0);
						add_light(c, p + Vec3(0, 10.0, 0) - right * side * 4.1, 1.2, 0.08);
					}
					break;
				case RK_RURAL:
				case RK_COAST:
				case RK_TOUGE:
				case RK_FARM:
					if (!w.baked && s.distance - last_pole > 36.0 && sx.type == ST_GROUND) { // Riviera cables are buried
						last_pole = s.distance;
						Vec3 p = s.center - right * (out_l + 1.2);
						p.y = w.terrain.sample(p.x, p.z);
						add_prop(c, PROP_UTILITY_POLE, p, yaw, Vec3(1, rng.range(0.9, 1.05), 1), rng.next());
					}
					if (r.def.kind == RK_TOUGE && s.distance - last_chevron > 12.0) {
						// Chevron signs on the outside of tight corners.
						const Vec3 &pa = r.samples[std::max(i - 4, 0)].rs.center;
						const Vec3 &pc = r.samples[std::min(i + 4, n - 1)].rs.center;
						Vec3 ab = (s.center - pa).flat(), bc = (pc - s.center).flat(), ac = (pc - pa).flat();
						real den = ab.length() * bc.length() * ac.length();
						real k = den > 1e-6 ? 2.0 * (ab.x * bc.z - ab.z * bc.x) / den : 0.0;
						if (std::fabs(k) > 1.0 / 30.0) {
							last_chevron = s.distance;
							real side = k > 0 ? -1.0 : 1.0; // outside of the turn
							Vec3 p = s.center + right * side * ((side < 0 ? out_l : out_r) + 0.4);
							add_prop(c, PROP_SIGN_CURVE, p, yaw + (k > 0 ? -PI * 0.5 : PI * 0.5), Vec3(1, 1, 1), 0.0);
						}
					}
					break;
				case RK_DOCK:
					if (s.distance - last_lamp > 45.0) {
						last_lamp = s.distance;
						Vec3 p = s.center + right * (out_r - 0.4);
						add_prop(c, PROP_HIGHWAY_LAMP, p, yaw - PI * 0.5, Vec3(1, 1.4, 1), 0.0);
						add_light(c, p + Vec3(0, 12.6, 0) - right * 4.1, 1.4, 0.07);
					}
					break;
				default:
					break;
			}
		}
	}
}

// ---- Junction patches ------------------------------------------------------------------

void build_junctions(Ctx &c) {
	for (const Intersection &j : c.w.junctions) {
		if (!c.in_chunk(j.center.x, j.center.z)) continue;
		MeshData &m = c.out.groups[WG_JUNCTION];
		real hx = j.half_x, hz = j.half_z;
		Vec3 a = j.center + Vec3(-hx, 0, -hz), b = j.center + Vec3(-hx, 0, hz), cc = j.center + Vec3(hx, 0, hz), d = j.center + Vec3(hx, 0, -hz);
		real code = 80.0 + j.style;
		int i = m.vertex_count();
		Vec3 up(0, 1, 0);
		m.add_vertex(a, up, 0.0, 0.0, code, hx * 2.0, 1.0, 0, 0, hz * 2.0);
		m.add_vertex(b, up, 0.0, 1.0, code, hx * 2.0, 1.0, 0, 0, hz * 2.0);
		m.add_vertex(cc, up, 1.0, 1.0, code, hx * 2.0, 1.0, 0, 0, hz * 2.0);
		m.add_vertex(d, up, 1.0, 0.0, code, hx * 2.0, 1.0, 0, 0, hz * 2.0);
		m.add_quad(i, i + 1, i + 2, i + 3);
		if (c.opt.collision) {
			c.out.collision.add_tri(a, b, cc, j.surface, COL_ALL);
			c.out.collision.add_tri(a, cc, d, j.surface, COL_ALL);
		}
		// Traffic lights on the corners of city crossings.
		if (j.style == 1 || j.style == 2) {
			for (int k = 0; k < 4; ++k) {
				real sx = (k & 1) ? 1.0 : -1.0, sz = (k & 2) ? 1.0 : -1.0;
				Vec3 p = j.center + Vec3(sx * (hx + 2.2), 0, sz * (hz + 2.2));
				add_prop(c, PROP_TRAFFIC_LIGHT, p, std::atan2(sx, sz) + PI, Vec3(1, 1, 1), (real)k / 4.0);
			}
		}
	}
}

// ---- City blocks: buildings, neon, rooftops, docks, parks ------------------------------

void building_box(Ctx &c, const Vec3 &mn, const Vec3 &mx, real style, uint64_t seed) {
	MeshData &m = c.out.groups[WG_BUILDING];
	real h = mx.y - mn.y;
	Vec3 corners[4] = {Vec3(mn.x, mn.y, mn.z), Vec3(mx.x, mn.y, mn.z), Vec3(mx.x, mn.y, mx.z), Vec3(mn.x, mn.y, mx.z)};
	Vec3 normals[4] = {Vec3(0, 0, -1), Vec3(1, 0, 0), Vec3(0, 0, 1), Vec3(-1, 0, 0)};
	real u = 0.0;
	real seedf = (real)(seed % 997) / 997.0;
	for (int k = 0; k < 4; ++k) {
		Vec3 a = corners[k], b = corners[(k + 1) % 4];
		real len = distance(a, b);
		Vec3 top(0, h, 0);
		int i = m.vertex_count();
		// UV: u = meters along the perimeter, v = meters up. UV2: style, seed. COLOR.g: face id.
		m.add_vertex(a, normals[k], u, 0.0, style, seedf, 1.0, k / 4.0);
		m.add_vertex(b, normals[k], u + len, 0.0, style, seedf, 1.0, k / 4.0);
		m.add_vertex(b + top, normals[k], u + len, h, style, seedf, 1.0, k / 4.0);
		m.add_vertex(a + top, normals[k], u, h, style, seedf, 1.0, k / 4.0);
		// Counter-clockwise seen from outside: a -> b -> b+top -> a+top when walking the perimeter
		// clockwise from above. Resolve with the face normal to be safe.
		Vec3 fn = (b - a).cross(top);
		if (fn.dot(normals[k]) >= 0) m.add_quad(i, i + 1, i + 2, i + 3);
		else m.add_quad(i, i + 3, i + 2, i + 1);
		u += len;
		if (c.opt.collision) {
			c.out.collision.add_tri(a, b, b + top, SURF_BUILDING, COL_SOLID);
			c.out.collision.add_tri(a, b + top, a + top, SURF_BUILDING, COL_SOLID);
		}
	}
	MeshData &rm = c.out.groups[WG_ROOF];
	quad(rm, Vec3(mn.x, mx.y, mn.z), Vec3(mn.x, mx.y, mx.z), Vec3(mx.x, mx.y, mx.z), Vec3(mx.x, mx.y, mn.z), Vec3(0, 1, 0),
			{(float)(mn.x / 6), (float)(mn.z / 6)}, {(float)(mn.x / 6), (float)(mx.z / 6)}, {(float)(mx.x / 6), (float)(mx.z / 6)}, {(float)(mx.x / 6), (float)(mn.z / 6)});
}

void neon_sign(Ctx &c, const Vec3 &base, const Vec3 &outward, const Vec3 &along, real height, real width, int atlas, real hue) {
	MeshData &m = c.out.groups[WG_NEON];
	Vec3 root = base + outward * 0.15;
	Vec3 tip = base + outward * (0.15 + width);
	Vec3 up(0, height, 0);
	// Blade sign perpendicular to the facade, lit on both faces. UV2: atlas cell, hue.
	quad(m, root, tip, tip + up, root + up, along, {0, 1}, {1, 1}, {1, 0}, {0, 0}, atlas, hue);
	quad(m, tip, root, root + up, tip + up, -along, {1, 1}, {0, 1}, {0, 0}, {1, 0}, atlas, hue);
	add_light(c, base + outward * (0.5 + width) + Vec3(0, height * 0.5, 0), 0.6, hue);
}

void billboard(Ctx &c, const Vec3 &center, const Vec3 &facing, real w, real h, int atlas, real hue) {
	MeshData &m = c.out.groups[WG_NEON];
	Vec3 side = Vec3(0, 1, 0).cross(facing).normalized() * (w * 0.5);
	Vec3 up(0, h * 0.5, 0);
	quad(m, center - side - up, center + side - up, center + side + up, center - side + up, facing, {0, 1}, {1, 1}, {1, 0}, {0, 0}, atlas + 100, hue);
	add_light(c, center + facing * 2.0, 0.9, hue);
}

void build_blocks(Ctx &c) {
	for (size_t bi = 0; bi < c.w.blocks.size(); ++bi) {
		const Block &b = c.w.blocks[bi];
		if (b.max.x < c.mn.x || b.min.x >= c.mx.x || b.max.z < c.mn.z || b.min.z >= c.mx.z) continue;
		Rng rng(c.w.seed * 131 + bi * 7919);
		real y = b.min.y + 0.15;
		// Block ground (pavement / yard) clipped to the chunk.
		{
			real x0 = std::max(b.min.x - 3.4, c.mn.x), x1 = std::min(b.max.x + 3.4, c.mx.x);
			real z0 = std::max(b.min.z - 3.4, c.mn.z), z1 = std::min(b.max.z + 3.4, c.mx.z);
			if (x1 > x0 && z1 > z0) {
				MeshData &sm = c.out.groups[WG_SIDEWALK];
				Vec3 a(x0, y, z0), bb(x0, y, z1), cc(x1, y, z1), d(x1, y, z0);
				// UV2.x = verge surface id: pavers in the city, plain concrete in dock yards, grass in parks.
				real surf_id = b.kind == 2 ? (real)SURF_GRASS : (b.kind == 3 ? (real)SURF_COBBLE : (real)SURF_CONCRETE);
				quad(sm, a, bb, cc, d, Vec3(0, 1, 0), {(float)(x0 / 2), (float)(z0 / 2)}, {(float)(x0 / 2), (float)(z1 / 2)}, {(float)(x1 / 2), (float)(z1 / 2)},
						{(float)(x1 / 2), (float)(z0 / 2)}, surf_id);
				if (c.opt.collision) {
					uint8_t s = b.kind == 2 ? SURF_GRASS : SURF_CONCRETE;
					c.out.collision.add_tri(a, bb, cc, s, COL_ALL);
					c.out.collision.add_tri(a, cc, d, s, COL_ALL);
				}
			}
		}
		if (b.kind == 2) { // park
			for (int k = 0; k < 24; ++k) {
				Vec3 p(rng.range(b.min.x + 3, b.max.x - 3), y, rng.range(b.min.z + 3, b.max.z - 3));
				if (!c.in_chunk(p.x, p.z)) continue;
				add_prop(c, rng.chance(0.5) ? PROP_TREE_PALM : PROP_TREE_PLANE, p, rng.range(0, TAU), Vec3(1, 1, 1) * rng.range(0.8, 1.3), rng.next());
			}
			continue;
		}
		if (b.kind == 3) { // dock yard: container stacks
			real x = b.min.x + 2.0;
			while (x + 13.0 < b.max.x) {
				real z = b.min.z + 2.0;
				while (z + 3.0 < b.max.z) {
					int stack = rng.irange(0, 4);
					Vec3 p(x + 6.1, y, z + 1.3);
					if (stack > 0 && c.in_chunk(p.x, p.z)) {
						for (int s = 0; s < stack; ++s) add_prop(c, PROP_CONTAINER, p + Vec3(0, s * 2.6, 0), 0.0, Vec3(1, 1, 1), rng.next());
						if (c.opt.collision) {
							Vec3 mn(x, y, z), mx(x + 12.2, y + stack * 2.6, z + 2.5);
							Vec3 cs[4] = {Vec3(mn.x, y, mn.z), Vec3(mx.x, y, mn.z), Vec3(mx.x, y, mx.z), Vec3(mn.x, y, mx.z)};
							for (int k = 0; k < 4; ++k) {
								Vec3 a = cs[k], bb = cs[(k + 1) % 4], up(0, mx.y - y, 0);
								c.out.collision.add_tri(a, bb, bb + up, SURF_METAL, COL_SOLID);
								c.out.collision.add_tri(a, bb + up, a + up, SURF_METAL, COL_SOLID);
							}
						}
					}
					z += 3.0;
				}
				x += 14.0;
			}
			continue;
		}
		// Buildings: lots around the perimeter facing the streets.
		bool commercial = b.kind == 0;
		real bw = b.max.x - b.min.x, bd = b.max.z - b.min.z;
		real center_dist = std::sqrt(sqr((b.min.x + b.max.x) * 0.5) + sqr((b.min.z + b.max.z) * 0.5));
		real tall = commercial ? smoothstep(600.0, 80.0, center_dist) : 0.0;
		for (int edge = 0; edge < 4; ++edge) {
			bool along_x = edge % 2 == 0;
			real len = along_x ? bw : bd;
			real depth_max = std::min((along_x ? bd : bw) * 0.5, commercial ? 28.0 : 16.0);
			real t = 0.0;
			while (t < len - 6.0) {
				real lot = std::min(rng.range(commercial ? 10.0 : 8.0, commercial ? 26.0 : 16.0), len - t);
				if (len - t - lot < 6.0) lot = len - t;
				real depth = rng.range(depth_max * 0.55, depth_max);
				Vec3 mn, mx;
				switch (edge) {
					case 0: mn = Vec3(b.min.x + t, y, b.min.z); mx = Vec3(b.min.x + t + lot, y, b.min.z + depth); break; // north side
					case 1: mn = Vec3(b.max.x - depth, y, b.min.z + t); mx = Vec3(b.max.x, y, b.min.z + t + lot); break; // east
					case 2: mn = Vec3(b.min.x + t, y, b.max.z - depth); mx = Vec3(b.min.x + t + lot, y, b.max.z); break; // south
					default: mn = Vec3(b.min.x, y, b.min.z + t); mx = Vec3(b.min.x + depth, y, b.min.z + t + lot); break; // west
				}
				// Corner lots overlap the perpendicular edge; shrink along x for east/west edges.
				if (!along_x) {
					mn.z = std::max(mn.z, b.min.z + depth_max);
					mx.z = std::min(mx.z, b.max.z - depth_max);
					if (mx.z - mn.z < 5.0) { t += lot; continue; }
				}
				t += lot + rng.range(0.0, 1.5);
				real cxm = (mn.x + mx.x) * 0.5, czm = (mn.z + mx.z) * 0.5;
				if (!c.in_chunk(cxm, czm)) continue;
				real h;
				if (commercial) h = 10.0 + std::pow(rng.next(), 2.0 - tall) * (18.0 + 90.0 * tall);
				else h = 6.5 + rng.next() * 16.0;
				h = std::round(h / 3.4) * 3.4 + 1.0;
				mx.y = y + h;
				real style = commercial ? (real)rng.irange(0, 4) : (real)rng.irange(5, 7);
				uint64_t seed = rng.next_u64();
				building_box(c, mn, mx, style, seed);
				// Facade facing the street for signage.
				Vec3 outward = edge == 0 ? Vec3(0, 0, -1) : edge == 1 ? Vec3(1, 0, 0) : edge == 2 ? Vec3(0, 0, 1) : Vec3(-1, 0, 0);
				Vec3 along = Vec3(0, 1, 0).cross(outward);
				Vec3 face_c(cxm + outward.x * (mx.x - mn.x) * 0.5, y, czm + outward.z * (mx.z - mn.z) * 0.5);
				real flen = along_x ? (mx.x - mn.x) : (mx.z - mn.z);
				if (commercial && h > 9.0) {
					int signs = rng.irange(1, 3);
					for (int s = 0; s < signs; ++s) {
						real off = rng.range(-flen * 0.4, flen * 0.4);
						real sh = std::min(h - 5.0, rng.range(4.0, 12.0));
						neon_sign(c, face_c + along * off + Vec3(0, rng.range(3.5, std::max(3.6, h - sh - 1.0)), 0), outward, along, sh, 0.9,
								rng.irange(0, 15), rng.next());
					}
					if (h > 30.0 && rng.chance(0.45)) billboard(c, face_c + outward * 0.3 + Vec3(0, h - rng.range(4.0, 9.0), 0), outward, flen * 0.8, 5.0, rng.irange(0, 7), rng.next());
				} else if (!commercial && rng.chance(0.25)) {
					neon_sign(c, face_c + Vec3(0, 3.2, 0), outward, along, 2.2, 0.6, rng.irange(0, 15), rng.next());
				}
				// Rooftop clutter.
				int ac = rng.irange(0, 3);
				for (int k = 0; k < ac; ++k)
					add_prop(c, PROP_AC_UNIT, Vec3(rng.range(mn.x + 1, mx.x - 1), mx.y, rng.range(mn.z + 1, mx.z - 1)), rng.range(0, TAU), Vec3(1, 1, 1), rng.next());
				if (rng.chance(0.3)) add_prop(c, PROP_WATER_TANK, Vec3(cxm, mx.y, czm), 0.0, Vec3(1, 1, 1), rng.next());
			}
		}
	}
}

// ---- Nature scatter ----------------------------------------------------------------------

void scatter(Ctx &c) {
	if (c.opt.prop_density <= 0.0) return;
	const World &w = c.w;
	Rng rng(w.seed * 7 + (uint64_t)(c.out.cx * 92821 + c.out.cz * 68917));
	real cell = 13.0 / std::sqrt(c.opt.prop_density);
	for (real z = c.mn.z; z < c.mx.z; z += cell)
		for (real x = c.mn.x; x < c.mx.x; x += cell) {
			real px = x + rng.range(0.0, cell), pz = z + rng.range(0.0, cell);
			if (w.is_sea(px, pz)) continue;
			District d = w.district_at(px, pz);
			if (d == DIST_CITY || d == DIST_DOCKS || d == DIST_DAIKOKU) continue;
			int mat = w.terrain.material(px, pz);
			if (mat == 5 || mat == 3 || mat == 4) continue;
			real h = w.terrain.sample(px, pz);
			Vec3 nrm = w.terrain.normal(px, pz);
			if (nrm.y < 0.72) continue;
			// Keep clear of roads.
			bool near = false;
			for (const RoadSampleX *s : c.nearby) {
				real hw = std::max(s->rs.width_left + s->rs.shoulder_left, s->rs.width_right + s->rs.shoulder_right) + 4.0;
				if (sqr(s->rs.center.x - px) + sqr(s->rs.center.z - pz) < hw * hw) {
					near = true;
					break;
				}
			}
			if (near) continue;
			real density_noise = fbm2(px / 180.0, pz / 180.0, 2);
			bool forest = d == DIST_TOUGE || h > 120.0;
			if (!forest && density_noise < 0.45) continue;
			if (rng.chance(0.08)) {
				add_prop(c, PROP_ROCK, Vec3(px, h - 0.2, pz), rng.range(0, TAU), Vec3(1, 1, 1) * rng.range(0.6, 2.2), rng.next());
				continue;
			}
			PropType t;
			if (forest) t = rng.chance(0.75) ? PROP_TREE_PINE : PROP_TREE_PLANE;
			else if (d == DIST_RURAL && density_noise > 0.62) t = PROP_TREE_CYPRESS;
			else t = rng.chance(0.15) ? PROP_TREE_PALM : (rng.chance(0.3) ? PROP_BUSH : PROP_TREE_PLANE);
			real s = rng.range(0.75, 1.35);
			add_prop(c, t, Vec3(px, h - 0.1, pz), rng.range(0, TAU), Vec3(s, s * rng.range(0.9, 1.15), s), rng.next());
		}
}

// ---- Baked (real) map: junction polygons, buildings, vegetation ------------------------------------

// Junction polygon as a fan around its centre (road shader junction code 80 + style; UV in metres
// so the asphalt texture continues from the roads). Traffic lights stand at the corners of big ones.
void build_junction_polys(Ctx &c) {
	for (const Intersection &j : c.w.junctions) {
		if (j.poly.size() < 3 || !c.in_chunk(j.center.x, j.center.z)) continue;
		MeshData &m = c.out.groups[WG_JUNCTION];
		Vec3 up(0, 1, 0);
		real span = std::max(j.half_x * 2.0, 2.0);
		int n = (int)j.poly.size();
		// The polygon is a fan of mouth triangles (centre + one leg's mouth edge) and corner
		// triangles between legs. Mouth triangles carry leg-local UVs so the road shader can lay
		// markings square to that leg: UV.x 0..1 across the mouth (0 = the inbound, right-hand
		// half's kerb), UV.y metres in from the mouth, UV2.y mouth width. Code 85: stop line +
		// zebra (major junctions), 86: dashed give-way line (roundabout entries), 80: plain.
		auto tri = [&](const Vec3 &a, const Vec3 &b, const Vec3 &cc, Vec2 ua, Vec2 ub, Vec2 uc, real code, real width) {
			int base = m.vertex_count();
			m.add_vertex(a, up, ua.x, ua.y, code, width, 1.0, 0, 0, span);
			m.add_vertex(b, up, ub.x, ub.y, code, width, 1.0, 0, 0, span);
			m.add_vertex(cc, up, uc.x, uc.y, code, width, 1.0, 0, 0, span);
			// Counter-clockwise seen from above.
			real cross = (b.x - a.x) * (cc.z - a.z) - (b.z - a.z) * (cc.x - a.x);
			if (cross < 0) m.indices.insert(m.indices.end(), {base, base + 1, base + 2});
			else m.indices.insert(m.indices.end(), {base, base + 2, base + 1});
			if (c.opt.collision) c.out.collision.add_tri(a, b, cc, j.surface, COL_ALL);
		};
		auto plain_uv = [&](const Vec3 &p) { return Vec2{0.5 + (p.x - j.center.x) / span, 0.5 + (p.z - j.center.z) / span}; };
		for (int k = 0; k < n; ++k) {
			if (k < (int)j.skip.size() && j.skip[k]) continue;
			const Vec3 &pa = j.poly[k], &pb = j.poly[(k + 1) % n];
			bool mouth = (k % 2) == 0 && n % 2 == 0;
			real code = 80.0;
			if (mouth) {
				int leg = k / 2;
				int ri = leg < (int)j.legs.size() && j.legs[leg] >= 0 && j.legs[leg] < (int)c.w.road_of_def.size() ? c.w.road_of_def[j.legs[leg]] : -1;
				bool ring = ri >= 0 && c.w.roads[ri].def.roundabout;
				if (j.style == 1) code = 85.0;
				else if (j.style == 3 && !ring && ri >= 0) code = 86.0;
			}
			if (code > 80.5) {
				Vec3 edge = (pb - pa).flat();
				real width = edge.length();
				Vec3 mid = (pa + pb) * 0.5;
				Vec3 inward = Vec3(-edge.z, 0, edge.x) / std::max(width, 1e-3);
				if (inward.dot((j.center - mid).flat()) < 0) inward = -inward;
				real depth = (j.center - mid).flat().dot(inward);
				tri(pa, pb, j.center, {0, 0}, {1, 0}, {0.5, depth}, code, width);
			} else {
				tri(pa, pb, j.center, plain_uv(pa), plain_uv(pb), {0.5, 0.5}, 80.0, span);
			}
		}
		if (j.style == 1) {
			for (int k = 1; k < n; k += 2) {
				Vec3 p = j.poly[k];
				Vec3 out = (p - j.center).flat().normalized();
				Vec3 q = p + out * 1.8;
				q.y = c.w.height(q.x, q.z);
				add_prop(c, PROP_TRAFFIC_LIGHT, q, std::atan2(-out.x, -out.z), Vec3(1, 1, 1), (real)k / n);
			}
		}
	}
}

// Ear clipping of a simple polygon (x/z), any winding. Appends triangle index triples.
void triangulate(const std::vector<Vec3> &ring, std::vector<int> &tris) {
	int n = (int)ring.size();
	if (n < 3) return;
	std::vector<int> idx(n);
	for (int i = 0; i < n; ++i) idx[i] = i;
	real area = 0;
	for (int i = 0; i < n; ++i) area += ring[i].x * ring[(i + 1) % n].z - ring[(i + 1) % n].x * ring[i].z;
	real sgn = area >= 0 ? 1.0 : -1.0;
	auto cross = [&](const Vec3 &a, const Vec3 &b, const Vec3 &p) { return (b.x - a.x) * (p.z - a.z) - (b.z - a.z) * (p.x - a.x); };
	int guard = 0;
	while ((int)idx.size() > 3 && guard++ < 4 * n) {
		bool clipped = false;
		int m = (int)idx.size();
		for (int k = 0; k < m; ++k) {
			int ia = idx[(k + m - 1) % m], ib = idx[k], ic = idx[(k + 1) % m];
			const Vec3 &a = ring[ia], &b = ring[ib], &cc = ring[ic];
			if (cross(a, b, cc) * sgn <= 1e-9) continue; // reflex
			bool empty = true;
			for (int q = 0; q < m && empty; ++q) {
				int iq = idx[q];
				if (iq == ia || iq == ib || iq == ic) continue;
				const Vec3 &p = ring[iq];
				if (cross(a, b, p) * sgn >= 0 && cross(b, cc, p) * sgn >= 0 && cross(cc, a, p) * sgn >= 0) empty = false;
			}
			if (!empty) continue;
			tris.insert(tris.end(), {ia, ib, ic});
			idx.erase(idx.begin() + k);
			clipped = true;
			break;
		}
		if (!clipped) break;
	}
	if (idx.size() == 3) tris.insert(tris.end(), {idx[0], idx[1], idx[2]});
}

// Buildings from real footprints: walls (facade shader: UV = perimeter metres / height metres,
// UV2 = style, seed; COLOR = wall colour), flat or hipped terracotta roofs, wall collision.
void build_buildings(Ctx &c) {
	const World &w = c.w;
	for (size_t bi = 0; bi < w.buildings.size(); ++bi) {
		const Building &b = w.buildings[bi];
		if (!c.in_chunk(b.center.x, b.center.z)) continue;
		int n = (int)b.ring.size();
		if (n < 3) continue;
		// Far rings: only buildings tall enough to read on the skyline.
		if (c.opt.lod >= 3 && b.top - b.base < 12.0) continue;
		MeshData &m = c.out.groups[WG_BUILDING];
		real seedf = (real)((bi * 2654435761u) % 997) / 997.0;
		real cr = b.r / 255.0, cg = b.g / 255.0, cb = b.b / 255.0;
		real area = 0;
		for (int k = 0; k < n; ++k) area += b.ring[k].x * b.ring[(k + 1) % n].z - b.ring[(k + 1) % n].x * b.ring[k].z;
		real sgn = area >= 0 ? 1.0 : -1.0; // outward normal side
		real h = b.top - b.base;
		real u = 0.0;
		// Floors stay level: the ground floor starts at the highest ground along the footprint
		// (the street-side entrance on a slope); downhill walls show the storeys below it.
		real gmax = b.base;
		for (int k = 0; k < n; ++k) gmax = std::max(gmax, w.terrain.sample(b.ring[k].x, b.ring[k].z));
		real anchor = clampr(gmax - b.base, 0.0, std::max(0.0, h - 3.0));
		// UV2: x = style + seed * 0.98 (seed in the fraction), y = ground-floor anchor (m).
		real style_seed = b.style + seedf * 0.98;
		// Real depth where the chase cam grazes a facade: a projecting roof cornice on classic
		// styles and continuous balconies (balcons filants) on Monaco apartment blocks. Only on
		// walls that face the open (not a party wall against the next building). Trim pieces tell
		// the facade shader what they are through UV2.x + 10 * kind (1 moulding, 2 parapet, 3 glass).
		bool cornice = c.opt.lod <= 1 && h > 4.0 && b.style != 4 && b.style != 6;
		bool balconies = c.opt.lod == 0 && b.style == 2 && seedf >= 0.55 && h >= 10.0;
		std::vector<uint8_t> open_edge;
		std::vector<Vec3> miter;
		if (cornice || balconies) {
			open_edge.assign(n, 1);
			std::vector<Vec3> en(n);
			for (int k = 0; k < n; ++k) {
				Vec3 d = b.ring[(k + 1) % n] - b.ring[k];
				real l = d.flat().length();
				en[k] = l > 1e-3 ? Vec3(d.z, 0, -d.x) * (sgn / l) : Vec3();
				Vec3 probe = (b.ring[k] + b.ring[(k + 1) % n]) * 0.5 + en[k] * 1.2;
				for (const Building *o : c.near_buildings) {
					if (o == &b || (o->center - probe).flat().length() > o->radius + 0.5) continue;
					if (point_in_ring(o->ring, probe.x, probe.z)) {
						open_edge[k] = 0;
						break;
					}
				}
			}
			// Mitred corner offsets so cornices close around corners (1 m = unit outward push).
			miter.resize(n);
			for (int k = 0; k < n; ++k) {
				Vec3 np = en[(k + n - 1) % n], nn = en[k];
				Vec3 mdir = (np + nn).flat();
				real ml = mdir.length();
				if (ml < 1e-3) { miter[k] = nn; continue; }
				mdir = mdir / ml;
				miter[k] = mdir / std::max(mdir.dot(nn), 0.5);
			}
		}
		for (int k = 0; k < n; ++k) {
			Vec3 a(b.ring[k].x, b.base, b.ring[k].z), bb(b.ring[(k + 1) % n].x, b.base, b.ring[(k + 1) % n].z);
			real len = distance(a, bb);
			if (len < 0.05) continue;
			Vec3 dir = (bb - a) / len;
			Vec3 nrm = Vec3(dir.z, 0, -dir.x) * sgn;
			Vec3 top(0, h, 0);
			int i = m.vertex_count();
			// COLOR: wall colour, alpha = wall height / 250 m (facade shader: cornice, parapet).
			real ha = std::min(h, 250.0) / 250.0;
			m.add_vertex(a, nrm, u, 0.0, style_seed, anchor, cr, cg, cb, ha);
			m.add_vertex(bb, nrm, u + len, 0.0, style_seed, anchor, cr, cg, cb, ha);
			m.add_vertex(bb + top, nrm, u + len, h, style_seed, anchor, cr, cg, cb, ha);
			m.add_vertex(a + top, nrm, u, h, style_seed, anchor, cr, cg, cb, ha);
			Vec3 fn = (bb - a).cross(top);
			if (fn.dot(nrm) >= 0) m.add_quad(i, i + 1, i + 2, i + 3);
			else m.add_quad(i, i + 3, i + 2, i + 1);

			if (cornice && open_edge[k]) {
				// Eave: 0.45 m out, 0.35 m deep, with top and soffit so it reads from the street
				// and from the corniche roads above.
				const real P = 0.45, D = 0.35;
				real kind = style_seed + 10.0;
				Vec3 wa = a + top, wb = bb + top;
				Vec3 oa = wa + miter[k] * P, ob = wb + miter[(k + 1) % n] * P;
				Vec3 dn(0, -D, 0);
				quad_color(m, oa + dn, ob + dn, ob, oa, nrm, {u, h - D}, {u + len, h - D}, {u + len, h}, {u, h}, kind, anchor, cr, cg, cb, ha);
				quad_color(m, wa + dn, wb + dn, ob + dn, oa + dn, Vec3(0, -1, 0), {u, 0}, {u + len, 0}, {u + len, P}, {u, P}, kind, anchor, cr, cg, cb, ha);
				quad_color(m, wa, oa, ob, wb, Vec3(0, 1, 0), {u, 0}, {u, P}, {u + len, P}, {u + len, 0}, kind, anchor, cr, cg, cb, ha);
			}
			bool street = false;
			if (balconies && open_edge[k] && len >= 5.0) {
				// Balconies face the street (or the sea front): a road within ~25 m out front.
				Vec3 front = (a + bb) * 0.5 + nrm * 12.0;
				for (const RoadSampleX *rsx : c.nearby)
					if (sqr(rsx->rs.center.x - front.x) + sqr(rsx->rs.center.z - front.z) < 14.0 * 14.0) {
						street = true;
						break;
					}
			}
			if (street) {
				// Continuous balcony per floor, on the facade shader's floor grid (style 2: ground
				// floor 4.2 m, then 3.05 m storeys; windows stop 0.7 m under the roof line).
				const real gf = 4.2, fh = 3.05, Dp = 0.9, T = 0.1;
				bool glass = seedf > 0.8;
				real kind_slab = style_seed + 10.0, kind_front = style_seed + (glass ? 30.0 : 20.0);
				Vec3 A = a + dir * 0.3, B = bb - dir * 0.3;
				int floors = 0;
				for (real fy = anchor + gf; fy + fh < h - 0.7 && floors < 14; fy += fh, ++floors) {
					real y0 = fy - 0.02, y1 = fy + 0.16, yr = fy + 1.05;
					Vec3 A0 = A + Vec3(0, y0, 0), B0 = B + Vec3(0, y0, 0);
					Vec3 Ao = A0 + nrm * Dp, Bo = B0 + nrm * Dp; // outer bottom edge
					Vec3 Ai = Ao - nrm * T, Bi = Bo - nrm * T; // parapet inner face
					Vec3 up1(0, y1 - y0, 0), upr(0, yr - y0, 0);
					real l2 = distance(A, B);
					// Soffit, parapet front (UV.y = metres up from the slab bottom), parapet cap and back, slab top.
					quad_color(m, A0, B0, Bo, Ao, Vec3(0, -1, 0), {u, 0}, {u + l2, 0}, {u + l2, Dp}, {u, Dp}, kind_slab, anchor, cr, cg, cb, ha);
					quad_color(m, Ao, Bo, Bo + upr, Ao + upr, nrm, {u, 0}, {u + l2, 0}, {u + l2, yr - y0}, {u, yr - y0}, kind_front, anchor, cr, cg, cb, ha);
					quad_color(m, Ai + upr, Ao + upr, Bo + upr, Bi + upr, Vec3(0, 1, 0), {u, yr - y0}, {u, yr - y0}, {u + l2, yr - y0}, {u + l2, yr - y0}, kind_front, anchor, cr, cg, cb, ha);
					quad_color(m, Bi + up1, Ai + up1, Ai + upr, Bi + upr, -nrm, {u + l2, y1 - y0}, {u, y1 - y0}, {u, yr - y0}, {u + l2, yr - y0}, kind_front, anchor, cr, cg, cb, ha);
					quad_color(m, A0 + up1, Ai + up1, Bi + up1, B0 + up1, Vec3(0, 1, 0), {u, 0}, {u, Dp}, {u + l2, Dp}, {u + l2, 0}, kind_slab, anchor, cr, cg, cb, ha);
					// End caps.
					for (int e = 0; e < 2; ++e) {
						Vec3 W = e ? B0 : A0, O = e ? Bo : Ao, I = e ? Bi : Ai;
						Vec3 en_cap = e ? dir : -dir;
						quad_color(m, W, O, O + up1, W + up1, en_cap, {0, 0}, {Dp, 0}, {Dp, y1 - y0}, {0, y1 - y0}, kind_slab, anchor, cr, cg, cb, ha);
						quad_color(m, I + up1, O + up1, O + upr, I + upr, en_cap, {0, y1 - y0}, {T, y1 - y0}, {T, yr - y0}, {0, yr - y0}, kind_front, anchor, cr, cg, cb, ha);
					}
				}
			}

			u += len;
			if (c.opt.collision && c.opt.lod == 0) {
				c.out.collision.add_tri(a, bb, bb + top, SURF_BUILDING, COL_SOLID);
				c.out.collision.add_tri(a, bb + top, a + top, SURF_BUILDING, COL_SOLID);
			}
		}
		// Roof. UV2.x: 0 flat (gravel/concrete), 1 clay tiles.
		MeshData &rm = c.out.groups[WG_ROOF];
		if (b.roof == 0 || n > 24) {
			std::vector<int> tris;
			triangulate(b.ring, tris);
			int i0 = rm.vertex_count();
			for (int k = 0; k < n; ++k) rm.add_vertex(Vec3(b.ring[k].x, b.top, b.ring[k].z), Vec3(0, 1, 0), b.ring[k].x / 2.0, b.ring[k].z / 2.0, 0.0, seedf);
			for (size_t t = 0; t + 2 < tris.size(); t += 3) {
				// Face up: order by the polygon winding.
				if (sgn > 0) rm.indices.insert(rm.indices.end(), {i0 + tris[t], i0 + tris[t + 2], i0 + tris[t + 1]});
				else rm.indices.insert(rm.indices.end(), {i0 + tris[t], i0 + tris[t + 1], i0 + tris[t + 2]});
			}
		} else {
			// Hipped: every eave edge slopes up to a ridge point above the centroid (~30 degrees).
			real minside = 1e9;
			for (int k = 0; k < n; ++k) minside = std::min(minside, (b.ring[k] - b.center).length());
			real rise = clampr(minside * 0.55, 1.2, 4.5);
			Vec3 apex(b.center.x, b.top + rise, b.center.z);
			for (int k = 0; k < n; ++k) {
				Vec3 a(b.ring[k].x, b.top, b.ring[k].z), bb(b.ring[(k + 1) % n].x, b.top, b.ring[(k + 1) % n].z);
				Vec3 fnrm = (bb - a).cross(apex - a).normalized();
				if (fnrm.y < 0) fnrm = -fnrm;
				int i = rm.vertex_count();
				// UV along the eave (m) and up the slope (m) so tile rows run along the eave.
				real el = distance(a, bb), sl = distance((a + bb) * 0.5, apex);
				rm.add_vertex(a, fnrm, 0.0, 0.0, 1.0, seedf);
				rm.add_vertex(bb, fnrm, el / 2.0, 0.0, 1.0, seedf);
				rm.add_vertex(apex, fnrm, el / 4.0, sl / 2.0, 1.0, seedf);
				Vec3 fc = (bb - a).cross(apex - a);
				if (fc.y >= 0) rm.indices.insert(rm.indices.end(), {i, i + 2, i + 1});
				else rm.indices.insert(rm.indices.end(), {i, i + 1, i + 2});
			}
		}
		// Rooftop details on flat roofs: AC units / water tanks.
		if (b.roof == 0 && h > 9.0) {
			Rng rng(bi * 7919 + 17);
			int k = rng.irange(0, 2);
			for (int q = 0; q < k; ++q) {
				const Vec3 &p = b.ring[rng.irange(0, n - 1)];
				Vec3 pos = lerp(p, b.center, rng.range(0.3, 0.7));
				add_prop(c, PROP_AC_UNIT, Vec3(pos.x, b.top, pos.z), rng.range(0, TAU), Vec3(1, 1, 1), rng.next());
			}
		}
	}
}

// Vegetation from real land cover + every mapped tree. Mediterranean mix: umbrella / Aleppo pines,
// cypresses, palms, olives, plane trees and scrub.
void scatter_baked(Ctx &c) {
	const World &w = c.w;
	// Mapped trees first (exact positions from OpenStreetMap).
	static const PropType TREE_PROP[6] = {PROP_TREE_PINE, PROP_TREE_CYPRESS, PROP_TREE_PALM, PROP_TREE_OLIVE, PROP_TREE_PLANE, PROP_TREE_PLANE};
	for (const Tree &t : w.trees) {
		if (!c.in_chunk(t.x, t.z)) continue;
		real s = t.height_dm ? clampr(t.height_dm / 100.0, 0.5, 2.2) : 1.0;
		uint64_t hs = (uint64_t)(t.x * 13.0) * 31 + (uint64_t)(t.z * 7.0);
		add_prop(c, TREE_PROP[std::min<int>(t.kind, 5)], Vec3(t.x, w.height(t.x, t.z) - 0.1, t.z), (hs % 628) / 100.0, Vec3(s, s, s), (hs % 97) / 97.0);
	}
	if (c.opt.prop_density <= 0.0) return;
	// Buildings in/near this chunk (so trees don't grow through walls).
	std::vector<const Building *> near;
	for (const Building &b : w.buildings)
		if (b.center.x > c.mn.x - 40 && b.center.x < c.mx.x + 40 && b.center.z > c.mn.z - 40 && b.center.z < c.mx.z + 40) near.push_back(&b);
	Rng rng(w.seed * 7 + (uint64_t)(c.out.cx * 92821 + c.out.cz * 68917));
	real cell = 9.0 / std::sqrt(c.opt.prop_density);
	for (real z = c.mn.z; z < c.mx.z; z += cell)
		for (real x = c.mn.x; x < c.mx.x; x += cell) {
			real px = x + rng.range(0.0, cell), pz = z + rng.range(0.0, cell);
			uint8_t lc = w.land_at(px, pz);
			real r = rng.next();
			PropType t;
			real scale = rng.range(0.8, 1.25);
			switch (lc) {
				case LAND_FOREST:
					if (r > 0.8) continue;
					t = r < 0.5 ? PROP_TREE_PINE : r < 0.62 ? PROP_TREE_CYPRESS : PROP_TREE_PLANE;
					break;
				case LAND_SCRUB:
					if (r > 0.34) continue;
					t = r < 0.2 ? PROP_BUSH : r < 0.26 ? PROP_TREE_PINE : r < 0.3 ? PROP_TREE_OLIVE : PROP_ROCK;
					break;
				case LAND_PARK:
					if (r > 0.3) continue;
					t = r < 0.09 ? PROP_TREE_PALM : r < 0.17 ? PROP_TREE_PLANE : r < 0.22 ? PROP_TREE_PINE : r < 0.26 ? PROP_TREE_CYPRESS : PROP_BUSH;
					break;
				case LAND_FARM:
					if (r > 0.22) continue;
					t = r < 0.16 ? PROP_TREE_OLIVE : PROP_TREE_CYPRESS;
					break;
				case LAND_ROCK:
					if (r > 0.12) continue;
					t = r < 0.08 ? PROP_ROCK : PROP_BUSH;
					scale = rng.range(0.7, 2.2);
					break;
				default:
					continue;
			}
			real h = w.terrain.sample(px, pz);
			if (h < 0.5 || w.terrain.normal(px, pz).y < (t == PROP_ROCK ? 0.4 : 0.66)) continue;
			bool blocked = false;
			for (const RoadSampleX *s : c.nearby) {
				real hw = std::max(s->rs.width_left + s->rs.shoulder_left, s->rs.width_right + s->rs.shoulder_right) + 2.5;
				if (sqr(s->rs.center.x - px) + sqr(s->rs.center.z - pz) < hw * hw) {
					blocked = true;
					break;
				}
			}
			for (const Building *b : near) {
				if (blocked) break;
				if (sqr(b->center.x - px) + sqr(b->center.z - pz) < sqr(b->radius + 3.0)) blocked = true;
			}
			if (blocked) continue;
			add_prop(c, t, Vec3(px, h - 0.1, pz), rng.range(0, TAU), Vec3(scale, scale * rng.range(0.9, 1.15), scale), rng.next());
		}
}

// Quay and sea walls: marching squares over the sea mask on a 4 m grid; every boundary segment
// whose land side is port or urban gets a concrete wall from the berth floor to the deck (and a
// coping kerb), with bollards along the port quays. GROUP_WALL, UV2.x = 0 (concrete).
void build_quays(Ctx &c) {
	const World &w = c.w;
	const real step = 4.0, deck = 0.9, floor_y = -4.5;
	MeshData &m = c.out.groups[GROUP_WALL];
	Rng rng(w.seed * 31 + (uint64_t)(c.out.cx * 131 + c.out.cz * 977));
	auto sea = [&](real x, real z) { return w.is_sea(x, z); };
	auto walled = [&](real x, real z) { uint8_t l = w.land_at(x, z); return l == LAND_PORT || l == LAND_URBAN; };
	for (real z = c.mn.z; z < c.mx.z; z += step)
		for (real x = c.mn.x; x < c.mx.x; x += step) {
			bool s00 = sea(x, z), s10 = sea(x + step, z), s01 = sea(x, z + step), s11 = sea(x + step, z + step);
			int k = s00 + s10 + s01 + s11;
			if (k == 0 || k == 4) continue;
			// Edge midpoints where the mask flips; pair them up into segments.
			Vec3 pts[4];
			int np = 0;
			if (s00 != s10) pts[np++] = Vec3(x + step * 0.5, 0, z);
			if (s10 != s11) pts[np++] = Vec3(x + step, 0, z + step * 0.5);
			if (s11 != s01) pts[np++] = Vec3(x + step * 0.5, 0, z + step);
			if (s01 != s00) pts[np++] = Vec3(x, 0, z + step * 0.5);
			for (int q = 0; q + 1 < np; q += 2) {
				Vec3 a = pts[q], b = pts[q + 1];
				Vec3 mid = (a + b) * 0.5, along = (b - a).flat();
				real len = along.length();
				if (len < 0.5) continue;
				Vec3 n = Vec3(-along.z, 0, along.x) / len; // one of the two sides
				if (!sea(mid.x + n.x * 2.0, mid.z + n.z * 2.0)) n = -n; // n faces the water
				Vec3 land = mid - n * 2.0;
				if (!walled(land.x, land.z)) continue;
				Vec3 a0(a.x, floor_y, a.z), b0(b.x, floor_y, b.z), a1(a.x, deck + 0.15, a.z), b1(b.x, deck + 0.15, b.z);
				quad(m, a0, b0, b1, a1, n, {(float)a.x, (float)floor_y}, {(float)b.x, (float)floor_y}, {(float)b.x, (float)deck}, {(float)a.x, (float)deck}, 0.0, 0.0, 0.8);
				// Coping stone along the edge (0.35 m on to the quay).
				Vec3 in = -n * 0.35;
				quad(m, a1, b1, b1 + in, a1 + in, Vec3(0, 1, 0), {(float)a.x, 0}, {(float)b.x, 0}, {(float)b.x, 0.35f}, {(float)a.x, 0.35f}, 0.0, 0.0, 1.0);
				if (c.opt.collision) {
					c.out.collision.add_tri(a0, b0, b1, SURF_CONCRETE, COL_SOLID);
					c.out.collision.add_tri(a0, b1, a1, SURF_CONCRETE, COL_SOLID);
				}
				if (w.land_at(land.x, land.z) == LAND_PORT && rng.chance(len / 9.0)) {
					Vec3 p = mid - n * 0.7;
					add_prop(c, PROP_BOLLARD, Vec3(p.x, deck, p.z), std::atan2(n.x, n.z), Vec3(1.3, 0.8, 1.3), rng.next());
				}
			}
		}
}

// Yachts moored Mediterranean-style (stern to the quay) along the port quays: walk the water
// 2-5 m off LAND_PORT edges and fit boats side by side with a hull's width of clearance.
void scatter_harbour(Ctx &c) {
	const World &w = c.w;
	Rng rng(w.seed * 13 + (uint64_t)(c.out.cx * 7919 + c.out.cz * 104729));
	const real step = 3.0;
	auto &yachts = c.out.props[PROP_YACHT];
	for (real z = c.mn.z; z < c.mx.z; z += step)
		for (real x = c.mn.x; x < c.mx.x; x += step) {
			if (!w.is_sea(x, z) || w.terrain.sample(x, z) > -1.5) continue;
			// Nearest quay direction.
			Vec3 d;
			bool quay = false;
			for (int k = 0; k < 8 && !quay; ++k) {
				real a = k * (TAU / 8.0);
				Vec3 dir(std::cos(a), 0, std::sin(a));
				for (real r = 2.0; r <= 5.0; r += 1.5) {
					real qx = x + dir.x * r, qz = z + dir.z * r;
					if (!w.is_sea(qx, qz)) {
						if (w.land_at(qx, qz) == LAND_PORT) {
							d = dir;
							quay = true;
						}
						break;
					}
				}
			}
			if (!quay) continue;
			real s = rng.range(0.45, 1.0);
			real len = 30.0 * s, beam = 6.1 * s;
			Vec3 centre = Vec3(x, 0, z) - d * (len * 0.5);
			Vec3 bow = Vec3(x, 0, z) - d * len;
			if (!w.is_sea(bow.x, bow.z) || !w.is_sea(centre.x, centre.z)) continue;
			bool clash = false;
			for (const PropInstance &o : yachts) {
				real ob = 6.1 * o.sx;
				if (sqr(o.x - centre.x) + sqr(o.z - centre.z) < sqr((beam + ob) * 0.5 + 1.2)) {
					clash = true;
					break;
				}
			}
			if (clash) continue;
			add_prop(c, PROP_YACHT, centre, std::atan2(d.x, d.z), Vec3(s, s, s), rng.next());
		}
}

} // namespace

// Far rings are drawn from 500 m to ~1.3 km: every surface costs a draw call and kerbs, rails,
// posts, walls, tunnel liners and signs are sub-pixel there. Keep what reads at distance (terrain,
// which carries the road corridors in its carve tint, buildings, roofs, water, bridge decks) and,
// on the nearer far ring, the carriageways with the junction patches merged in (same material).
void append_group(MeshData &dst, MeshData &src) {
	int base = dst.vertex_count();
	dst.positions.insert(dst.positions.end(), src.positions.begin(), src.positions.end());
	dst.normals.insert(dst.normals.end(), src.normals.begin(), src.normals.end());
	dst.uvs.insert(dst.uvs.end(), src.uvs.begin(), src.uvs.end());
	dst.uv2s.insert(dst.uv2s.end(), src.uv2s.begin(), src.uv2s.end());
	dst.colors.insert(dst.colors.end(), src.colors.begin(), src.colors.end());
	for (int32_t i : src.indices) dst.indices.push_back(i + base);
	src.clear();
}

void simplify_far(ChunkOutput &out) {
	if (out.lod == 1) {
		// 256-640 m: kerb faces, guardrail posts, tyre walls and tunnel strip lights are sub-pixel.
		for (int g : {(int)GROUP_CURB, (int)GROUP_POST, (int)GROUP_TIREWALL, (int)WG_TUNNEL_LIGHT}) out.groups[g].clear();
		append_group(out.groups[GROUP_ROAD], out.groups[WG_JUNCTION]);
		append_group(out.groups[GROUP_SHOULDER], out.groups[WG_SIDEWALK]);
	}
	if (out.lod < 2) return;
	for (int g : {(int)GROUP_CURB, (int)GROUP_RAIL, (int)GROUP_POST, (int)GROUP_WALL, (int)GROUP_TIREWALL, (int)WG_TUNNEL, (int)WG_TUNNEL_LIGHT, (int)WG_NEON,
				 (int)GROUP_SHOULDER, (int)WG_SIDEWALK})
		out.groups[g].clear();
	if (out.lod >= 3) {
		out.groups[GROUP_ROAD].clear();
		out.groups[WG_JUNCTION].clear();
	} else {
		append_group(out.groups[GROUP_ROAD], out.groups[WG_JUNCTION]);
	}
}

void build_chunk(const World &w, int cx, int cz, const ChunkOptions &opt, ChunkOutput &out) {
	out = ChunkOutput();
	out.cx = cx;
	out.cz = cz;
	out.lod = opt.lod;
	Ctx c{w, opt, out, Vec3(), Vec3(), {}, {}, {}};
	w.chunk_bounds(cx, cz, c.mn, c.mx);
	out.center = Vec3((c.mn.x + c.mx.x) * 0.5, 0, (c.mn.z + c.mx.z) * 0.5);
	const real margin = 30.0;
	for (const Road &r : w.roads) {
		if (r.bmax.x < c.mn.x - margin || r.bmin.x > c.mx.x + margin || r.bmax.z < c.mn.z - margin || r.bmin.z > c.mx.z + margin) continue;
		for (const RoadSampleX &s : r.samples) {
			if (s.rs.center.x < c.mn.x - margin || s.rs.center.x > c.mx.x + margin || s.rs.center.z < c.mn.z - margin || s.rs.center.z > c.mx.z + margin) continue;
			c.nearby.push_back(&s);
			if (s.type == ST_TUNNEL) c.tunnels.push_back(&s);
		}
	}
	build_terrain(c);
	build_roads(c);
	if (w.baked) {
		for (const Building &b : w.buildings)
			if (b.center.x > c.mn.x - 60 && b.center.x < c.mx.x + 60 && b.center.z > c.mn.z - 60 && b.center.z < c.mx.z + 60) c.near_buildings.push_back(&b);
		build_junction_polys(c);
		build_buildings(c);
		if (opt.props) scatter_baked(c);
		if (opt.props && out.min_y < 0.5) scatter_harbour(c);
		if (opt.lod <= 1 && out.min_y < 0.5) build_quays(c);
		simplify_far(out);
		return;
	}
	build_junctions(c);
	if (opt.lod <= 2) build_blocks(c);
	if (opt.props) scatter(c);
}

} // namespace nt
