#include "collision_grid.h"

#include <limits>

namespace nt {

static inline Vec3 fv(const float *p) { return {p[0], p[1], p[2]}; }

bool ray_triangle(const Vec3 &o, const Vec3 &d, const Vec3 &a, const Vec3 &b, const Vec3 &c, real &t, bool front_only) {
	const real eps = 1e-9;
	Vec3 e1 = b - a, e2 = c - a;
	Vec3 p = d.cross(e2);
	real det = e1.dot(p);
	if (front_only) {
		if (det < eps) return false;
	} else if (std::fabs(det) < eps) {
		return false;
	}
	real inv = 1.0 / det;
	Vec3 s = o - a;
	real u = s.dot(p) * inv;
	if (u < 0.0 || u > 1.0) return false;
	Vec3 q = s.cross(e1);
	real v = d.dot(q) * inv;
	if (v < 0.0 || u + v > 1.0) return false;
	t = e2.dot(q) * inv;
	return t >= 0.0;
}

// Ericson, Real-Time Collision Detection 5.1.5.
Vec3 closest_point_on_triangle(const Vec3 &p, const Vec3 &a, const Vec3 &b, const Vec3 &c) {
	Vec3 ab = b - a, ac = c - a, ap = p - a;
	real d1 = ab.dot(ap), d2 = ac.dot(ap);
	if (d1 <= 0.0 && d2 <= 0.0) return a;
	Vec3 bp = p - b;
	real d3 = ab.dot(bp), d4 = ac.dot(bp);
	if (d3 >= 0.0 && d4 <= d3) return b;
	real vc = d1 * d4 - d3 * d2;
	if (vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0) return a + ab * (d1 / (d1 - d3));
	Vec3 cp = p - c;
	real d5 = ab.dot(cp), d6 = ac.dot(cp);
	if (d6 >= 0.0 && d5 <= d6) return c;
	real vb = d5 * d2 - d1 * d6;
	if (vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0) return a + ac * (d2 / (d2 - d6));
	real va = d3 * d6 - d5 * d4;
	if (va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0) return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)));
	real denom = 1.0 / (va + vb + vc);
	real v = vb * denom, w = vc * denom;
	return a + ab * v + ac * w;
}

bool CollisionGrid::add_chunk(int64_t chunk_id, const float *positions, const uint8_t *surfaces, const uint8_t *flags, int tri_count) {
	if (chunks_.count(chunk_id)) return false;
	uint32_t slot;
	if (!free_slots_.empty()) {
		slot = free_slots_.back();
		free_slots_.pop_back();
	} else {
		slot = (uint32_t)slots_.size();
		slots_.emplace_back();
	}
	Chunk &ch = slots_[slot];
	ch.id = chunk_id;
	ch.tris.clear();
	ch.cells.clear();
	ch.tris.reserve(tri_count);
	std::unordered_map<int64_t, bool> touched;
	for (int i = 0; i < tri_count; ++i) {
		const float *p = positions + i * 9;
		Tri t;
		for (int k = 0; k < 3; ++k) {
			t.v0[k] = p[k];
			t.v1[k] = p[3 + k];
			t.v2[k] = p[6 + k];
		}
		Vec3 a = fv(t.v0), b = fv(t.v1), c = fv(t.v2);
		Vec3 n = (b - a).cross(c - a);
		real len = n.length();
		if (len < 1e-10) continue; // degenerate
		n = n / len;
		t.n[0] = (float)n.x;
		t.n[1] = (float)n.y;
		t.n[2] = (float)n.z;
		t.surface = surfaces ? surfaces[i] : (uint8_t)SURF_ASPHALT;
		t.flags = flags ? flags[i] : (uint8_t)COL_ALL;
		uint32_t index = (uint32_t)ch.tris.size();
		ch.tris.push_back(t);

		real minx = std::min({a.x, b.x, c.x}), maxx = std::max({a.x, b.x, c.x});
		real minz = std::min({a.z, b.z, c.z}), maxz = std::max({a.z, b.z, c.z});
		int32_t cx0 = cell_of(minx), cx1 = cell_of(maxx), cz0 = cell_of(minz), cz1 = cell_of(maxz);
		for (int32_t cx = cx0; cx <= cx1; ++cx) {
			for (int32_t cz = cz0; cz <= cz1; ++cz) {
				int64_t k = key(cx, cz);
				cells_[k].push_back({slot, index});
				if (!touched[k]) {
					touched[k] = true;
					ch.cells.push_back(k);
				}
			}
		}
	}
	chunks_[chunk_id] = slot;
	return true;
}

void CollisionGrid::remove_chunk(int64_t chunk_id) {
	auto it = chunks_.find(chunk_id);
	if (it == chunks_.end()) return;
	uint32_t slot = it->second;
	Chunk &ch = slots_[slot];
	for (int64_t k : ch.cells) {
		auto cit = cells_.find(k);
		if (cit == cells_.end()) continue;
		auto &v = cit->second;
		size_t w = 0;
		for (size_t r = 0; r < v.size(); ++r) {
			if (v[r].chunk_slot != slot) v[w++] = v[r];
		}
		v.resize(w);
		if (v.empty()) cells_.erase(cit);
	}
	ch.tris.clear();
	ch.tris.shrink_to_fit();
	ch.cells.clear();
	ch.id = -1;
	free_slots_.push_back(slot);
	chunks_.erase(it);
}

void CollisionGrid::clear() {
	slots_.clear();
	free_slots_.clear();
	chunks_.clear();
	cells_.clear();
}

int CollisionGrid::triangle_count() const {
	int n = 0;
	for (const auto &kv : chunks_) n += (int)slots_[kv.second].tris.size();
	return n;
}

void CollisionGrid::test_cell(int32_t cx, int32_t cz, const Vec3 &o, const Vec3 &d, real &best_t, RayHit &best, uint8_t mask, bool front_only) const {
	auto it = cells_.find(key(cx, cz));
	if (it == cells_.end()) return;
	for (const TriRef &r : it->second) {
		const Tri &t = tri(r);
		if (!(t.flags & mask)) continue;
		real th;
		if (ray_triangle(o, d, fv(t.v0), fv(t.v1), fv(t.v2), th, front_only) && th < best_t) {
			best_t = th;
			best.hit = true;
			best.t = th;
			best.normal = fv(t.n);
			best.surface = t.surface;
		}
	}
}

RayHit CollisionGrid::raycast(const Vec3 &origin, const Vec3 &dir_in, real max_t, uint8_t mask, bool front_only) const {
	RayHit best;
	Vec3 dir = dir_in.normalized();
	real best_t = max_t;

	// 2D DDA over XZ cells.
	int32_t cx = cell_of(origin.x), cz = cell_of(origin.z);
	Vec3 end = origin + dir * max_t;
	int32_t ex = cell_of(end.x), ez = cell_of(end.z);
	int step_x = dir.x > 0 ? 1 : (dir.x < 0 ? -1 : 0);
	int step_z = dir.z > 0 ? 1 : (dir.z < 0 ? -1 : 0);
	const real inf = std::numeric_limits<real>::infinity();
	real t_max_x = inf, t_max_z = inf, t_dx = inf, t_dz = inf;
	if (step_x != 0) {
		real next_x = (cx + (step_x > 0 ? 1 : 0)) * cell_;
		t_max_x = (next_x - origin.x) / dir.x;
		t_dx = cell_ / std::fabs(dir.x);
	}
	if (step_z != 0) {
		real next_z = (cz + (step_z > 0 ? 1 : 0)) * cell_;
		t_max_z = (next_z - origin.z) / dir.z;
		t_dz = cell_ / std::fabs(dir.z);
	}
	int guard = 0;
	while (guard++ < 4096) {
		test_cell(cx, cz, origin, dir, best_t, best, mask, front_only);
		if (cx == ex && cz == ez) break;
		real t_next = std::min(t_max_x, t_max_z);
		// A hit closer than the next cell boundary can't be beaten by later cells.
		if (best.hit && best_t <= t_next) break;
		if (t_next > max_t) break;
		if (t_max_x < t_max_z) {
			cx += step_x;
			t_max_x += t_dx;
		} else {
			cz += step_z;
			t_max_z += t_dz;
		}
	}
	if (best.hit) best.point = origin + dir * best.t;
	return best;
}

int CollisionGrid::sphere_contacts(const Vec3 &center, real radius, uint8_t mask, SphereContact *out, int max_out) const {
	int count = 0;
	int32_t cx0 = cell_of(center.x - radius), cx1 = cell_of(center.x + radius);
	int32_t cz0 = cell_of(center.z - radius), cz1 = cell_of(center.z + radius);
	const real r2 = radius * radius;
	for (int32_t cx = cx0; cx <= cx1; ++cx) {
		for (int32_t cz = cz0; cz <= cz1; ++cz) {
			auto it = cells_.find(key(cx, cz));
			if (it == cells_.end()) continue;
			for (const TriRef &r : it->second) {
				const Tri &t = tri(r);
				if (!(t.flags & mask)) continue;
				Vec3 a = fv(t.v0), b = fv(t.v1), c = fv(t.v2);
				// Cheap reject: plane distance.
				Vec3 n = fv(t.n);
				real pd = (center - a).dot(n);
				if (std::fabs(pd) > radius) continue;
				Vec3 cp = closest_point_on_triangle(center, a, b, c);
				Vec3 delta = center - cp;
				real d2 = delta.length_sq();
				if (d2 >= r2) continue;
				// Deduplicate triangles that live in several cells.
				bool dup = false;
				for (int k = 0; k < count; ++k) {
					if ((out[k].point - cp).length_sq() < 1e-10) {
						dup = true;
						break;
					}
				}
				if (dup) continue;
				real d = std::sqrt(d2);
				SphereContact sc;
				sc.point = cp;
				sc.normal = d > 1e-9 ? delta / d : (pd >= 0 ? n : -n);
				sc.depth = radius - d;
				sc.surface = t.surface;
				if (count < max_out) {
					out[count++] = sc;
				} else {
					// Keep the deepest contacts.
					int shallow = 0;
					for (int k = 1; k < count; ++k)
						if (out[k].depth < out[shallow].depth) shallow = k;
					if (out[shallow].depth < sc.depth) out[shallow] = sc;
				}
			}
		}
	}
	return count;
}

real CollisionGrid::ground_height(const Vec3 &from, real max_drop, Vec3 *normal, int *surface) const {
	RayHit h = raycast(from, {0, -1, 0}, max_drop, COL_DRIVABLE);
	if (!h.hit) return std::numeric_limits<real>::quiet_NaN();
	if (normal) *normal = h.normal.y < 0 ? -h.normal : h.normal;
	if (surface) *surface = h.surface;
	return h.point.y;
}

} // namespace nt
