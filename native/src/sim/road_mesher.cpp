#include "road_mesher.h"

namespace nt {

void MeshData::add_vertex(const Vec3 &p, const Vec3 &n, real u, real v, real u2, real v2, real r, real g, real b, real a) {
	positions.insert(positions.end(), {(float)p.x, (float)p.y, (float)p.z});
	normals.insert(normals.end(), {(float)n.x, (float)n.y, (float)n.z});
	uvs.insert(uvs.end(), {(float)u, (float)v});
	uv2s.insert(uv2s.end(), {(float)u2, (float)v2});
	colors.insert(colors.end(), {(float)r, (float)g, (float)b, (float)a});
}

// Godot treats clockwise triangles as front faces; callers pass corners counter-clockwise as seen
// from the visible side, so emit them reversed.
void MeshData::add_quad(int a, int b, int c, int d) {
	indices.insert(indices.end(), {a, c, b, a, d, c});
}

void MeshData::clear() {
	positions.clear();
	normals.clear();
	uvs.clear();
	uv2s.clear();
	colors.clear();
	indices.clear();
}

void CollisionData::add_tri(const Vec3 &a, const Vec3 &b, const Vec3 &c, uint8_t surface, uint8_t fl) {
	positions.insert(positions.end(), {(float)a.x, (float)a.y, (float)a.z, (float)b.x, (float)b.y, (float)b.z, (float)c.x, (float)c.y, (float)c.z});
	surfaces.push_back(surface);
	flags.push_back(fl);
}

void CollisionData::clear() {
	positions.clear();
	surfaces.clear();
	flags.clear();
}

void RoadMeshOutput::clear() {
	for (auto &g : groups) g.clear();
	collision.clear();
}

namespace {

struct Row {
	Vec3 right, up;
	Vec3 l_out, l_curb, l_edge, center, r_edge, r_curb, r_out;
	real dist;
};

Row make_row(const RoadSample &s, const RoadBuildOptions &o) {
	Row r;
	r.up = s.up.normalized();
	r.right = s.tangent.cross(r.up).normalized();
	r.dist = s.distance;
	real crown = (s.width_left + s.width_right) * 0.5 * 0.015; // 1.5% drainage crown
	r.center = s.center + r.up * crown;
	r.l_edge = s.center - r.right * s.width_left;
	r.r_edge = s.center + r.right * s.width_right;
	real cl = s.curb_left ? o.curb_width : 0.0;
	real cr = s.curb_right ? o.curb_width : 0.0;
	r.l_curb = s.center - r.right * (s.width_left + cl) + r.up * (s.curb_left ? o.curb_height * 0.3 : 0.0);
	r.r_curb = s.center + r.right * (s.width_right + cr) + r.up * (s.curb_right ? o.curb_height * 0.3 : 0.0);
	r.l_out = s.center - r.right * (s.width_left + cl + s.shoulder_left) - r.up * o.shoulder_drop;
	r.r_out = s.center + r.right * (s.width_right + cr + s.shoulder_right) - r.up * o.shoulder_drop;
	return r;
}

// Adds a strip quad (a0,b0 on row i; a1,b1 on row i+1; a left of b) to a render group and collision.
void strip(RoadMeshOutput &out, MeshGroup g, const RoadBuildOptions &o, const Vec3 &a0, const Vec3 &b0, const Vec3 &a1, const Vec3 &b1,
		const Vec3 &n0, const Vec3 &n1, real v0, real v1, real ua, real ub, real u2, real ao_a, real ao_b, uint8_t surface,
		uint8_t flags) {
	if (o.render) {
		MeshData &m = out.groups[g];
		int base = m.vertex_count();
		// UV2: x = marking code (lanes*10 + style), y = strip width in meters (for marking widths).
		real width = distance(a0, b0) / std::max(ub - ua, 1e-3);
		m.add_vertex(a0, n0, ua, v0, u2, width, ao_a);
		m.add_vertex(b0, n0, ub, v0, u2, width, ao_b);
		m.add_vertex(b1, n1, ub, v1, u2, width, ao_b);
		m.add_vertex(a1, n1, ua, v1, u2, width, ao_a);
		m.add_quad(base + 0, base + 1, base + 2, base + 3);
	}
	if (o.collision && flags) {
		out.collision.add_tri(a0, b0, b1, surface, flags);
		out.collision.add_tri(a0, b1, a1, surface, flags);
	}
}

void vertical_panel(RoadMeshOutput &out, MeshGroup g, const RoadBuildOptions &o, const Vec3 &p0, const Vec3 &p1, real y_lo, real y_hi,
		const Vec3 &up0, const Vec3 &up1, const Vec3 &face_n, real u0, real u1, uint8_t surface, bool collide) {
	Vec3 a = p0 + up0 * y_lo, b = p1 + up1 * y_lo, c = p1 + up1 * y_hi, d = p0 + up0 * y_hi;
	if (o.render) {
		MeshData &m = out.groups[g];
		int base = m.vertex_count();
		m.add_vertex(a, face_n, u0, 1.0, 0, 0, 0.8);
		m.add_vertex(b, face_n, u1, 1.0, 0, 0, 0.8);
		m.add_vertex(c, face_n, u1, 0.0, 0, 0, 1.0);
		m.add_vertex(d, face_n, u0, 0.0, 0, 0, 1.0);
		// Visible side is the one `face_n` points to: order corners CCW from that side.
		Vec3 tri_n = (b - a).cross(c - a);
		if (tri_n.dot(face_n) >= 0) m.add_quad(base + 0, base + 1, base + 2, base + 3);
		else m.add_quad(base + 0, base + 3, base + 2, base + 1);
	}
	if (o.collision && collide) {
		out.collision.add_tri(a, b, c, surface, COL_SOLID);
		out.collision.add_tri(a, c, d, surface, COL_SOLID);
	}
}

void post(RoadMeshOutput &out, const Vec3 &base, const Vec3 &up, const Vec3 &fwd, const Vec3 &right, real h) {
	MeshData &m = out.groups[GROUP_POST];
	const real w = 0.07;
	Vec3 corners[4] = {base - right * w - fwd * w, base + right * w - fwd * w, base + right * w + fwd * w, base - right * w + fwd * w};
	Vec3 norms[4] = {-fwd, right, fwd, -right};
	for (int k = 0; k < 4; ++k) {
		Vec3 a = corners[k], b = corners[(k + 1) % 4];
		Vec3 n = norms[k];
		int i = m.vertex_count();
		m.add_vertex(a, n, 0, 1, 0, 0, 0.7);
		m.add_vertex(b, n, 1, 1, 0, 0, 0.7);
		m.add_vertex(b + up * h, n, 1, 0, 0, 0, 1.0);
		m.add_vertex(a + up * h, n, 0, 0, 0, 0, 1.0);
		Vec3 tri_n = (b - a).cross(up);
		if (tri_n.dot(n) >= 0) m.add_quad(i, i + 1, i + 2, i + 3);
		else m.add_quad(i, i + 3, i + 2, i + 1);
	}
}

} // namespace

void build_road(const std::vector<RoadSample> &samples, const RoadBuildOptions &o, RoadMeshOutput &out) {
	int n = (int)samples.size();
	if (n < 2) return;
	int begin = std::max(0, o.range_begin);
	int end = o.range_end < 0 ? (o.closed ? n : n - 1) : std::min(o.range_end, o.closed ? n : n - 1);
	std::vector<Row> rows;
	rows.reserve(end - begin + 1);
	for (int i = begin; i <= end; ++i) rows.push_back(make_row(samples[i % n], o));
	if (o.closed && end == n) rows.back().dist = samples[n - 1].distance + distance(samples[n - 1].center, samples[0].center);

	RoadBuildOptions collision_only = o;
	collision_only.render = false;
	real post_acc = 0.0;
	for (int k = 0; k + 1 < (int)rows.size(); ++k) {
		const RoadSample &s0 = samples[(begin + k) % n];
		const RoadSample &s1 = samples[(begin + k + 1) % n];
		const Row &r0 = rows[k];
		const Row &r1 = rows[k + 1];
		real v0 = r0.dist / o.uv_length, v1 = r1.dist / o.uv_length;
		real marking = s0.lanes * 10 + s0.marking;
		uint8_t road_flags = COL_DRIVABLE | COL_SOLID;
		real ao_l = s0.barrier_left == BARRIER_WALL ? 0.7 : 1.0;
		real ao_r = s0.barrier_right == BARRIER_WALL ? 0.7 : 1.0;

		// Asphalt: two strips (left half, right half) sharing the crowned centre.
		real total_w = s0.width_left + s0.width_right;
		real uc = s0.width_left / total_w;
		strip(out, GROUP_ROAD, o, r0.l_edge, r0.center, r1.l_edge, r1.center, r0.up, r1.up, v0, v1, 0.0, uc, marking, ao_l, 1.0, s0.road_surface, road_flags);
		strip(out, GROUP_ROAD, o, r0.center, r0.r_edge, r1.center, r1.r_edge, r0.up, r1.up, v0, v1, uc, 1.0, marking, 1.0, ao_r, s0.road_surface, road_flags);

		// Curbs. UV2.x: 0 = red/white racing kerb, 1 = grey city kerb (sidewalk edge).
		real curb_kind = s0.shoulder_surface == SURF_CONCRETE ? 1.0 : 0.0;
		uint8_t curb_surf = curb_kind > 0.5 ? (uint8_t)SURF_CONCRETE : (uint8_t)SURF_CURB;
		if (s0.curb_left)
			strip(out, GROUP_CURB, o, r0.l_curb, r0.l_edge, r1.l_curb, r1.l_edge, r0.up, r1.up, v0 * 4.0, v1 * 4.0, 0, 1, curb_kind, 1, 1, curb_surf, road_flags);
		if (s0.curb_right)
			strip(out, GROUP_CURB, o, r0.r_edge, r0.r_curb, r1.r_edge, r1.r_curb, r0.up, r1.up, v0 * 4.0, v1 * 4.0, 0, 1, curb_kind, 1, 1, curb_surf, road_flags);

		// Shoulders / verges. UV2.x carries the surface id for the verge shader.
		if (s0.shoulder_left > 0.01)
			strip(out, GROUP_SHOULDER, o, r0.l_out, r0.l_curb, r1.l_out, r1.l_curb, r0.up, r1.up, v0, v1, 0, s0.shoulder_left / 4.0, s0.shoulder_surface, 0.9, 1, s0.shoulder_surface, road_flags);
		if (s0.shoulder_right > 0.01)
			strip(out, GROUP_SHOULDER, o, r0.r_curb, r0.r_out, r1.r_curb, r1.r_out, r0.up, r1.up, v0, v1, 0, s0.shoulder_right / 4.0, s0.shoulder_surface, 1, 0.9, s0.shoulder_surface, road_flags);

		// Barriers along the outer verge edge.
		real u0 = r0.dist / 4.0, u1 = r1.dist / 4.0;
		Vec3 fwd = s0.tangent;
		for (int side = 0; side < 2; ++side) {
			uint8_t kind = side == 0 ? s0.barrier_left : s0.barrier_right;
			if (kind == BARRIER_NONE) continue;
			// Only continue the barrier where the next sample has one too.
			uint8_t next_kind = side == 0 ? s1.barrier_left : s1.barrier_right;
			if (next_kind != kind) continue;
			Vec3 p0 = side == 0 ? r0.l_out : r0.r_out;
			Vec3 p1 = side == 0 ? r1.l_out : r1.r_out;
			Vec3 face = side == 0 ? r0.right : -r0.right; // faces the road
			switch (kind) {
				case BARRIER_GUARDRAIL:
					vertical_panel(out, GROUP_RAIL, o, p0, p1, o.rail_height - 0.32, o.rail_height, r0.up, r1.up, face, u0, u1, SURF_GUARDRAIL, false);
					vertical_panel(out, GROUP_RAIL, o, p0, p1, o.rail_height - 0.32, o.rail_height, r0.up, r1.up, -face, u0, u1, SURF_GUARDRAIL, false);
					// Collision spans from below the deck to well above the hull, so a car always meets a
					// vertical face instead of riding up the rail's top edge and rolling over.
					vertical_panel(out, GROUP_RAIL, collision_only, p0, p1, -0.2, 1.6, r0.up, r1.up, face, u0, u1, SURF_GUARDRAIL, true);
					if (o.render) {
						post_acc += distance(p0, p1);
						if (post_acc >= o.post_spacing) {
							post_acc = 0.0;
							post(out, p0 - face * 0.12, r0.up, fwd, r0.right, o.rail_height - 0.05);
						}
					}
					break;
				case BARRIER_WALL:
					vertical_panel(out, GROUP_WALL, o, p0, p1, -0.3, o.wall_height, r0.up, r1.up, face, u0, u1, SURF_WALL, false);
					vertical_panel(out, GROUP_WALL, collision_only, p0, p1, -0.3, 1.8, r0.up, r1.up, face, u0, u1, SURF_WALL, true);
					vertical_panel(out, GROUP_WALL, o, p0 - face * 0.25, p1 - face * 0.25, -0.3, o.wall_height, r0.up, r1.up, -face, u0, u1, SURF_WALL, false);
					if (o.render) {
						// Wall cap.
						MeshData &m = out.groups[GROUP_WALL];
						int i = m.vertex_count();
						Vec3 a = p0 + r0.up * o.wall_height, b = p1 + r1.up * o.wall_height;
						Vec3 c = b - face * 0.25, d = a - face * 0.25;
						m.add_vertex(a, r0.up, u0, 0, 0, 0, 1);
						m.add_vertex(b, r1.up, u1, 0, 0, 0, 1);
						m.add_vertex(c, r1.up, u1, 0.1, 0, 0, 1);
						m.add_vertex(d, r0.up, u0, 0.1, 0, 0, 1);
						Vec3 tn = (b - a).cross(c - a);
						if (tn.dot(r0.up) >= 0) m.add_quad(i, i + 1, i + 2, i + 3);
						else m.add_quad(i, i + 3, i + 2, i + 1);
					}
					break;
				case BARRIER_TIREWALL:
					vertical_panel(out, GROUP_TIREWALL, o, p0, p1, -0.1, 0.75, r0.up, r1.up, face, u0 * 2.0, u1 * 2.0, SURF_WALL, false);
					vertical_panel(out, GROUP_TIREWALL, collision_only, p0, p1, -0.1, 1.6, r0.up, r1.up, face, u0, u1, SURF_WALL, true);
					vertical_panel(out, GROUP_TIREWALL, o, p0 - face * 0.6, p1 - face * 0.6, -0.1, 0.75, r0.up, r1.up, -face, u0 * 2.0, u1 * 2.0, SURF_WALL, false);
					break;
				case BARRIER_FENCE:
					vertical_panel(out, GROUP_RAIL, o, p0, p1, 0.0, 1.8, r0.up, r1.up, face, u0, u1, SURF_GUARDRAIL, true);
					break;
				default:
					break;
			}
		}
	}
}

} // namespace nt
