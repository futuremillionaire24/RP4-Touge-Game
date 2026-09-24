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
	bool in_chunk(real x, real z) const { return x >= mn.x && x < mx.x && z >= mn.z && z < mx.z; }
};

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
			// COLOR: r rock, g sand, b urban, a paddy. UV2.x: dirt. Grass is the default.
			real rock = mat == 2 ? 1.0 : 0.0;
			rock = std::max(rock, smoothstep(0.62, 0.78, 1.0 - nrm.y)); // steep = rock
			m.positions.insert(m.positions.end(), {(float)x, (float)h, (float)z});
			m.normals.insert(m.normals.end(), {(float)nrm.x, (float)nrm.y, (float)nrm.z});
			m.uvs.insert(m.uvs.end(), {(float)(x / 8.0), (float)(z / 8.0)});
			m.uv2s.insert(m.uv2s.end(), {mat == 1 ? 1.0f : 0.0f, (float)h});
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

			// Lighting and poles by road kind.
			switch (r.def.kind) {
				case RK_STREET:
				case RK_AVENUE:
					if (s.distance - last_lamp > 28.0) {
						last_lamp = s.distance;
						for (real side : {-1.0, 1.0}) {
							real off = side < 0 ? out_l - 0.6 : out_r - 0.6;
							Vec3 p = s.center + right * (side * off);
							add_prop(c, PROP_STREET_LAMP, p, yaw + (side < 0 ? PI * 0.5 : -PI * 0.5), Vec3(1, 1, 1), 0.0);
							add_light(c, p + Vec3(0, 7.5, 0) - right * side * 1.4, 1.0, 0.1);
						}
					}
					if (r.def.kind == RK_STREET && s.distance - last_pole > 31.0) {
						last_pole = s.distance;
						Vec3 p = s.center - right * (out_l - 0.3);
						add_prop(c, PROP_UTILITY_POLE, p, yaw, Vec3(1, rng.range(0.95, 1.1), 1), rng.next());
					}
					if (rng.chance(0.02)) {
						Vec3 p = s.center + right * (out_r - 0.5);
						add_prop(c, PROP_VENDING, p, yaw - PI * 0.5, Vec3(1, 1, 1), rng.next());
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
						add_light(c, p + Vec3(0, 10.0, 0) - right * side * 3.0, 1.2, 0.08);
					}
					break;
				case RK_RURAL:
				case RK_COAST:
				case RK_TOUGE:
				case RK_FARM:
					if (s.distance - last_pole > 36.0 && sx.type == ST_GROUND) {
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
						add_light(c, p + Vec3(0, 13.0, 0) - right * 3.0, 1.4, 0.07);
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
				add_prop(c, rng.chance(0.5) ? PROP_TREE_SAKURA : PROP_TREE_BROADLEAF, p, rng.range(0, TAU), Vec3(1, 1, 1) * rng.range(0.8, 1.3), rng.next());
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
			if (forest) t = rng.chance(0.75) ? PROP_TREE_CEDAR : PROP_TREE_BROADLEAF;
			else if (d == DIST_RURAL && density_noise > 0.62) t = PROP_BAMBOO;
			else t = rng.chance(0.15) ? PROP_TREE_SAKURA : (rng.chance(0.3) ? PROP_BUSH : PROP_TREE_BROADLEAF);
			real s = rng.range(0.75, 1.35);
			add_prop(c, t, Vec3(px, h - 0.1, pz), rng.range(0, TAU), Vec3(s, s * rng.range(0.9, 1.15), s), rng.next());
		}
}

} // namespace

void build_chunk(const World &w, int cx, int cz, const ChunkOptions &opt, ChunkOutput &out) {
	out = ChunkOutput();
	out.cx = cx;
	out.cz = cz;
	out.lod = opt.lod;
	Ctx c{w, opt, out, Vec3(), Vec3(), {}, {}};
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
	build_junctions(c);
	if (opt.lod <= 2) build_blocks(c);
	if (opt.props) scatter(c);
}

} // namespace nt
