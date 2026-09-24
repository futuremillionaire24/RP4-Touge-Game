class_name Subdiv
extends RefCounted
## Catmull-Clark subdivision for the car body loft grid. Operates on a 2D grid of Vector3
## vertices (stations × ring_size); one pass quadruples the face count and smooths all normals.
## Closed-ring mode wraps the ring dimension (body); open mode leaves edges sharp (greenhouse).
## The result is a new grid suitable for CarBody._emit_grid().

## Subdivide a grid (Array of Arrays of Vector3) once using Catmull-Clark rules.
## `closed_ring` = true wraps the k (ring) axis; the s (station) axis is always open.
## Returns the subdivided grid: (2×ns - 1) stations × (2×nk or 2×nk - 1) ring entries.
static func catmull_clark(grid: Array, closed_ring: bool) -> Array:
	var ns: int = grid.size()
	var nk: int = grid[0].size()
	if ns < 2 or nk < 2:
		return grid

	# Step 1: Face points — average of the 4 corners of each face.
	# Face [s][k] is between grid[s..s+1][k..k+1] (k wraps if closed).
	var face_pts := []
	var fs := ns - 1
	var fk := nk if closed_ring else nk - 1
	for s in range(fs):
		var row := []
		for k in range(fk):
			var k1 := (k + 1) % nk if closed_ring else k + 1
			var fp: Vector3 = (grid[s][k] + grid[s][k1] + grid[s + 1][k] + grid[s + 1][k1]) * 0.25
			row.append(fp)
		face_pts.append(row)

	# Step 2: Edge points — average of the 2 edge endpoints and the 2 adjacent face points.
	# Horizontal edges (along k): between grid[s][k] and grid[s][k+1].
	var h_edge := [] # [ns][fk]
	for s in range(ns):
		var row := []
		for k in range(fk):
			var k1 := (k + 1) % nk if closed_ring else k + 1
			var mid: Vector3 = (grid[s][k] + grid[s][k1]) * 0.5
			# Adjacent faces: above (s-1) and below (s) in station direction.
			var n := 0
			var fsum := Vector3.ZERO
			if s > 0:
				fsum += face_pts[s - 1][k]
				n += 1
			if s < fs:
				fsum += face_pts[s][k]
				n += 1
			if n > 0:
				row.append((mid + fsum / float(n)) * 0.5)
			else:
				row.append(mid)
		h_edge.append(row)

	# Vertical edges (along s): between grid[s][k] and grid[s+1][k].
	var v_edge := [] # [fs][nk]
	for s in range(fs):
		var row := []
		for k in range(nk):
			var mid: Vector3 = (grid[s][k] + grid[s + 1][k]) * 0.5
			# Adjacent faces: left (k-1) and right (k) in ring direction.
			var n := 0
			var fsum := Vector3.ZERO
			if closed_ring:
				fsum += face_pts[s][(k - 1 + fk) % fk] + face_pts[s][k % fk]
				n = 2
			else:
				if k > 0:
					fsum += face_pts[s][k - 1]
					n += 1
				if k < fk:
					fsum += face_pts[s][k]
					n += 1
			if n > 0:
				row.append((mid + fsum / float(n)) * 0.5)
			else:
				row.append(mid)
		v_edge.append(row)

	# Step 3: Vertex points — smoothed original vertices.
	var vert_pts := []
	for s in range(ns):
		var row := []
		for k in range(nk):
			# Boundary vertices (open edges): keep at original position or do boundary rule.
			var is_s_boundary := (s == 0 or s == ns - 1)
			var is_k_boundary := not closed_ring and (k == 0 or k == nk - 1)
			if is_s_boundary and is_k_boundary:
				# Corner: keep original.
				row.append(grid[s][k])
			elif is_s_boundary or is_k_boundary:
				# Boundary edge: average of vertex and its two boundary neighbours.
				var neighbours := []
				if is_s_boundary:
					# Along the k edge.
					if closed_ring:
						neighbours.append(grid[s][(k - 1 + nk) % nk])
						neighbours.append(grid[s][(k + 1) % nk])
					else:
						if k > 0:
							neighbours.append(grid[s][k - 1])
						if k < nk - 1:
							neighbours.append(grid[s][k + 1])
				else:
					# Along the s edge (k is boundary).
					if s > 0:
						neighbours.append(grid[s - 1][k])
					if s < ns - 1:
						neighbours.append(grid[s + 1][k])
				if neighbours.size() == 2:
					row.append((neighbours[0] + neighbours[1] + grid[s][k] * 6.0) * 0.125)
				else:
					row.append(grid[s][k])
			else:
				# Interior vertex: standard CC rule.
				# F = average of adjacent face points.
				var F := Vector3.ZERO
				var adj_faces := 0
				var s0 := s - 1
				var s1 := s
				for si in [s0, s1]:
					if si < 0 or si >= fs:
						continue
					if closed_ring:
						F += face_pts[si][(k - 1 + fk) % fk]
						F += face_pts[si][k % fk]
						adj_faces += 2
					else:
						if k > 0 and k - 1 < fk:
							F += face_pts[si][k - 1]
							adj_faces += 1
						if k < fk:
							F += face_pts[si][k]
							adj_faces += 1
				if adj_faces > 0:
					F /= float(adj_faces)
				# R = average of midpoints of edges touching this vertex.
				var R := Vector3.ZERO
				var adj_edges := 0
				# S-direction edges.
				if s > 0:
					R += (grid[s][k] + grid[s - 1][k]) * 0.5
					adj_edges += 1
				if s < ns - 1:
					R += (grid[s][k] + grid[s + 1][k]) * 0.5
					adj_edges += 1
				# K-direction edges.
				if closed_ring:
					R += (grid[s][k] + grid[s][(k - 1 + nk) % nk]) * 0.5
					R += (grid[s][k] + grid[s][(k + 1) % nk]) * 0.5
					adj_edges += 2
				else:
					if k > 0:
						R += (grid[s][k] + grid[s][k - 1]) * 0.5
						adj_edges += 1
					if k < nk - 1:
						R += (grid[s][k] + grid[s][k + 1]) * 0.5
						adj_edges += 1
				if adj_edges > 0:
					R /= float(adj_edges)
				var n_val := float(adj_faces)
				if n_val >= 3.0:
					row.append((F + R * 2.0 + grid[s][k] * (n_val - 3.0)) / n_val)
				else:
					row.append(grid[s][k])
		vert_pts.append(row)

	# Step 4: Assemble the refined grid.
	# New grid: for each original face, we produce a 2×2 block of sub-faces.
	# Layout: refined[2*s][2*k] = vert_pts[s][k]
	#         refined[2*s][2*k+1] = h_edge[s][k]
	#         refined[2*s+1][2*k] = v_edge[s][k]
	#         refined[2*s+1][2*k+1] = face_pts[s][k]
	var rns := 2 * ns - 1
	var rnk := 2 * nk if closed_ring else 2 * nk - 1
	var result := []
	for rs in range(rns):
		var row := []
		row.resize(rnk)
		result.append(row)

	for s in range(ns):
		for k in range(nk):
			var rs := s * 2
			var rk := k * 2 if closed_ring else k * 2
			if rk < rnk:
				result[rs][rk] = vert_pts[s][k]

	for s in range(ns):
		for k in range(fk):
			var rk := k * 2 + 1
			if rk < rnk:
				result[s * 2][rk] = h_edge[s][k]

	for s in range(fs):
		for k in range(nk):
			var rk := k * 2 if closed_ring else k * 2
			if rk < rnk:
				result[s * 2 + 1][rk] = v_edge[s][k]

	for s in range(fs):
		for k in range(fk):
			var rk := k * 2 + 1
			if rk < rnk:
				result[s * 2 + 1][rk] = face_pts[s][k]

	return result


## Compute smooth vertex normals for a grid using area-weighted face normals.
## More accurate than per-vertex cross-products for curved surfaces.
static func smooth_normals(grid: Array, closed_ring: bool, centroid: Vector3) -> Array:
	var ns: int = grid.size()
	var nk: int = grid[0].size()
	var normals := []
	for s in range(ns):
		var row := []
		for k in range(nk):
			var n := Vector3.ZERO
			# Accumulate area-weighted normals from all adjacent faces.
			var kp := (k + 1) % nk if closed_ring else mini(k + 1, nk - 1)
			var km := (k - 1 + nk) % nk if closed_ring else maxi(k - 1, 0)
			var sp := mini(s + 1, ns - 1)
			var sm := maxi(s - 1, 0)
			# Four adjacent quad faces (each contributes a cross-product normal whose
			# magnitude is proportional to the parallelogram area).
			if s > 0 and (closed_ring or k > 0):
				n += (grid[s][km] - grid[s][k]).cross(grid[sm][k] - grid[s][k])
			if s > 0 and (closed_ring or k < nk - 1):
				n += (grid[sm][k] - grid[s][k]).cross(grid[s][kp] - grid[s][k])
			if s < ns - 1 and (closed_ring or k < nk - 1):
				n += (grid[s][kp] - grid[s][k]).cross(grid[sp][k] - grid[s][k])
			if s < ns - 1 and (closed_ring or k > 0):
				n += (grid[sp][k] - grid[s][k]).cross(grid[s][km] - grid[s][k])
			n = n.normalized()
			# Ensure outward-facing.
			var outward: Vector3 = grid[s][k] - Vector3(centroid.x, centroid.y, grid[s][k].z)
			if n.dot(outward) < 0.0:
				n = -n
			row.append(n)
		normals.append(row)
	return normals
