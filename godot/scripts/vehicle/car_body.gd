class_name CarBody
extends RefCounted
## Car body geometry: loft with wheel-arch cut-outs (body) and the lofted greenhouse (glass +
## painted roof). Dimensions come from the physics spec via `dims`.

const Subdiv := preload("res://scripts/vehicle/subdiv.gd")

const RING := 20 # body cross-section vertices (see _section)
const STATIONS := 72 # body stations front -> rear

static func profile(b: Dictionary, t: float) -> Dictionary:
	# Heights are above ground; converted to car-local later.
	var nose: float = b.nose_h
	var hood: float = b.hood_h
	var belt: float = b.get("belt_h", hood + 0.05)
	var deck: float = b.deck_h
	var tail: float = b.tail_h
	var cowl: float = b.cowl
	var deck_start: float = b.deck_start
	var top: float
	if t < 0.05:
		top = lerpf(nose * 0.82, nose, smoothstep(0.0, 0.05, t))
	elif t < cowl:
		var k := (t - 0.05) / maxf(cowl - 0.05, 0.01)
		top = lerpf(nose, hood, sin(k * PI * 0.5))
	elif t < deck_start:
		var k := (t - cowl) / maxf(deck_start - cowl, 0.01)
		top = lerpf(hood, belt, smoothstep(0.0, 0.3, k))
	elif t < 0.97:
		var k := (t - deck_start) / maxf(0.97 - deck_start, 0.01)
		top = lerpf(belt, deck, smoothstep(0.0, 0.4, k))
		top = lerpf(top, tail, smoothstep(0.7, 1.0, k))
	else:
		top = lerpf(tail, tail * 0.9, (t - 0.97) / 0.03)
	var w := 1.0
	w *= lerpf(0.84, 1.0, smoothstep(0.0, 0.12, t))
	w *= lerpf(1.0, 0.94, smoothstep(0.9, 1.0, t))
	var clear: float = b.clear
	var bottom := clear
	# Front splitter lip rises gently; the tail stays square with a short diffuser kick.
	bottom = maxf(bottom, lerpf(nose * 0.42, clear, smoothstep(0.0, 0.05, t)))
	bottom = maxf(bottom, lerpf(clear, clear + 0.1, smoothstep(0.96, 1.0, t)))
	return {"top": top, "bottom": bottom, "w": w}

static func clear_cache() -> void:
	pass

static func build_body_lod(b: Dictionary, dims: Dictionary, level: int) -> ArrayMesh:
	return build_body(b, dims, level)

static func build_body(b: Dictionary, dims: Dictionary, lod := 0) -> ArrayMesh:
	var hx: float = dims.hx
	var hz: float = dims.hz
	var cg: float = dims.cg
	var wheels: Array = dims.wheels
	var grid := [] # grid[s][k] = Vector3
	var ts := []
	for s in range(STATIONS):
		# Denser stations at the nose and tail where curvature is highest.
		var u := float(s) / float(STATIONS - 1)
		var t := 0.5 - 0.5 * cos(u * PI)
		ts.append(t)
		var z := lerpf(-hz, hz, t)
		var p := profile(b, t)
		var half_w: float = hx * p.w
		# Fender bulge around the axles (JDM blister arches)
		for wh in wheels:
			var dz: float = absf(z - wh.pos.z)
			half_w += 0.052 * smoothstep(0.68, 0.0, dz)
		var yb: float = p.bottom
		var yt: float = p.top
		# Wheel arch contour at this station (height above ground), or -1 outside the arches.
		var arch := -1.0
		for wh in wheels:
			var ra: float = wh.radius + 0.05
			var dz2: float = z - wh.pos.z
			if absf(dz2) < ra:
				arch = maxf(arch, minf((wh.pos.y + cg) + sqrt(ra * ra - dz2 * dz2), yt - 0.1))
		var ring := []
		for pt in _section(half_w, yb, yt, t, arch):
			ring.append(Vector3(pt.x, pt.y - cg, z))
		grid.append(ring)
	# Subdivide the body grid for smoother specular if LOD > 0.
	var centroid := Vector3(0, (b.hood_h * 0.5) - cg, 0)
	if lod > 0:
		for _pass in range(lod):
			grid = Subdiv.catmull_clark(grid, true)
	var normals := Subdiv.smooth_normals(grid, true, centroid)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_grid(st, grid, true, centroid, normals)
	# Nose and tail caps (fans).
	_emit_cap(st, grid[0], Vector3(0, 0, -1))
	_emit_cap(st, grid[grid.size() - 1], Vector3(0, 0, 1))
	var mesh := st.commit()
	# Dark underbody plane between the arches.
	var ub := SurfaceTool.new()
	ub.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0: float = b.clear + 0.02 - cg
	var q := [Vector3(-hx * 0.85, y0, -hz * 0.9), Vector3(hx * 0.85, y0, -hz * 0.9), Vector3(hx * 0.85, y0, hz * 0.9), Vector3(-hx * 0.85, y0, hz * 0.9)]
	for idx in [0, 1, 2, 0, 2, 3]:
		ub.set_normal(Vector3.DOWN)
		ub.add_vertex(q[idx])
	ub.commit(mesh)
	# Surface names select materials in CarBuilder ("paint" = the car's paint, others = CarMaterials).
	mesh.surface_set_name(0, "paint")
	mesh.surface_set_name(1, "underbody")
	return mesh

## Automotive cross-section (closed ring, RING points): flat floor, tucked sill, near-vertical door
## panel, shoulder crease, tumblehome into the hood/deck. Inside a wheel arch the outer lower
## points are lifted to the arch contour so the wheel shows through from the side.
static func _section(w: float, yb: float, yt: float, t: float, arch: float) -> Array:
	var h := maxf(yt - yb, 0.05)
	var ys := yb + h * 0.68 # shoulder crease height
	# End caps round off: less shoulder, more taper toward the nose/tail.
	var end_round := maxf(smoothstep(0.06, 0.0, t), smoothstep(0.94, 1.0, t))
	var side := lerpf(1.0, 0.9, end_round)
	var half := [
		Vector2(0.0, yb),
		Vector2(w * 0.68, yb),
		Vector2(w * 0.92, yb + h * 0.03),
		Vector2(w * 0.985 * side, yb + h * 0.14),
		Vector2(w * side, yb + h * 0.36),
		Vector2(w * 0.995 * side, yb + h * 0.56),
		Vector2(w * 0.975 * side, ys),
		Vector2(w * lerpf(0.9, 0.8, end_round), ys + (yt - ys) * 0.45),
		Vector2(w * lerpf(0.72, 0.55, end_round), yt - (yt - ys) * 0.08),
		Vector2(w * 0.36, yt),
	]
	if arch > 0.0:
		for i in range(1, 7):
			var p: Vector2 = half[i]
			if p.x > w * 0.6 and p.y < arch:
				half[i] = Vector2(p.x, arch + (i - 1) * 0.004)
	# Right half bottom -> top, then left half top -> bottom (mirror). 10 + 10 points = RING (20).
	var ring := []
	for p in half:
		ring.append(p)
	ring.append(Vector2(0.0, yt))
	for i in range(half.size() - 1, 0, -1):
		ring.append(Vector2(-half[i].x, half[i].y))
	# Ring runs counter-clockwise when viewed from the front; keep a fixed vertex count.
	return ring

## Emits a lofted grid with analytic normals; faces are wound clockwise as seen from outside.
static func _emit_grid(st: SurfaceTool, grid: Array, closed_ring: bool, centroid: Vector3, precomputed_normals: Array = []) -> void:
	var ns := grid.size()
	var nk: int = grid[0].size()
	var normals: Array
	if not precomputed_normals.is_empty():
		normals = precomputed_normals
	else:
		normals = []
		for s in range(ns):
			var row := []
			for k in range(nk):
				var kp := (k + 1) % nk if closed_ring else mini(k + 1, nk - 1)
				var km := (k - 1 + nk) % nk if closed_ring else maxi(k - 1, 0)
				var sp := mini(s + 1, ns - 1)
				var sm := maxi(s - 1, 0)
				var t_ring: Vector3 = grid[s][kp] - grid[s][km]
				var t_len: Vector3 = grid[sp][k] - grid[sm][k]
				var n := t_ring.cross(t_len).normalized()
				var outward: Vector3 = grid[s][k] - Vector3(centroid.x, centroid.y, grid[s][k].z)
				if n.dot(outward) < 0.0:
					n = -n
				row.append(n)
			normals.append(row)
	var klimit := nk if closed_ring else nk - 1
	for s in range(ns - 1):
		for k in range(klimit):
			var k2 := (k + 1) % nk
			var a: Vector3 = grid[s][k]
			var bb: Vector3 = grid[s][k2]
			var c: Vector3 = grid[s + 1][k2]
			var d: Vector3 = grid[s + 1][k]
			var na: Vector3 = normals[s][k]
			var face_n := (bb - a).cross(c - a)
			var verts := [[a, na], [bb, normals[s][k2]], [c, normals[s + 1][k2]], [d, normals[s + 1][k]]]
			var order := [0, 2, 1, 0, 3, 2] if face_n.dot(na) >= 0.0 else [0, 1, 2, 0, 2, 3]
			for o in order:
				st.set_normal(verts[o][1])
				st.set_uv(Vector2(float(k) / nk, float(s) / ns))
				st.add_vertex(verts[o][0])

static func _emit_cap(st: SurfaceTool, ring: Array, n: Vector3) -> void:
	var center := Vector3.ZERO
	for p in ring:
		center += p
	center /= ring.size()
	for k in range(ring.size()):
		var a: Vector3 = ring[k]
		var bb: Vector3 = ring[(k + 1) % ring.size()]
		var face := (a - center).cross(bb - center)
		var tri := [center, bb, a] if face.dot(n) >= 0.0 else [center, a, bb]
		for p in tri:
			st.set_normal(n)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(p)

# ---------------------------------------------------------------------------------------------
# Greenhouse

static func build_greenhouse(b: Dictionary, dims: Dictionary, lod := 0) -> ArrayMesh:
	var hx: float = dims.hx
	var hz: float = dims.hz
	var cg: float = dims.cg
	var cowl: float = b.cowl
	var rf: float = b.roof_front
	var rb: float = b.roof_back
	var ds: float = b.deck_start
	var roof_h: float = b.roof_h
	var open_top: bool = b.get("open_top", false)
	var end_t := rf if open_top else ds
	var n := 20
	var grid := []
	var roles := [] # per station segment: "glass_slope" or "roof"
	for s in range(n):
		var t := lerpf(cowl, end_t, float(s) / float(n - 1))
		var p := profile(b, t)
		var belt: float = p.top - 0.01
		var h: float
		if t < rf:
			h = lerpf(belt, roof_h, smoothstep(cowl, rf, t) * 0.9 + 0.1 * sin(smoothstep(cowl, rf, t) * PI * 0.5))
		elif t < rb:
			h = roof_h
		else:
			h = lerpf(roof_h, belt, smoothstep(rb, ds, t))
		if open_top:
			h = lerpf(belt, roof_h - 0.22, smoothstep(cowl, rf, t))
		var z := lerpf(-hz, hz, t)
		var wb: float = hx * p.w * 0.95
		var wt: float = hx * p.w * float(b.roof_w)
		var y0 := belt - cg
		var y1 := maxf(h, belt + 0.02) - cg
		# Open strip: left belt -> left roof edge -> across -> right roof edge -> right belt.
		var ring := [
			Vector3(-wb, y0, z),
			Vector3(lerpf(-wb, -wt, 0.5) - 0.02, lerpf(y0, y1, 0.55), z),
			Vector3(-wt, y1 - 0.04, z),
			Vector3(-wt * 0.55, y1, z),
			Vector3(wt * 0.55, y1, z),
			Vector3(wt, y1 - 0.04, z),
			Vector3(lerpf(wb, wt, 0.5) + 0.02, lerpf(y0, y1, 0.55), z),
			Vector3(wb, y0, z),
		]
		grid.append(ring)
		roles.append("roof" if (t >= rf and t <= rb and not open_top) else "glass")
	# Subdivide the greenhouse grid for smoother glass/roof specular.
	if lod > 0:
		for _pass in range(lod):
			grid = Subdiv.catmull_clark(grid, false)
		# Expand roles to match the new grid size.
		var new_roles := []
		for i in range(grid.size()):
			var orig_i := clampi(i / 2, 0, roles.size() - 1)
			new_roles.append(roles[orig_i])
		roles = new_roles
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centroid := Vector3(0, roof_h * 0.7 - cg, 0)
	for s in range(n - 1):
		for k in range(7):
			var a: Vector3 = grid[s][k]
			var bb: Vector3 = grid[s][k + 1]
			var c: Vector3 = grid[s + 1][k + 1]
			var d: Vector3 = grid[s + 1][k]
			var face_n := (bb - a).cross(c - a).normalized()
			var outward := ((a + c) * 0.5 - Vector3(0, centroid.y, (a.z + c.z) * 0.5)).normalized()
			var is_top := k >= 2 and k <= 4
			var role: String = roles[s]
			var use_roof := is_top and role == "roof"
			var target := roof if use_roof else glass
			var n_face := face_n if face_n.dot(outward) >= 0.0 else -face_n
			var tris := [a, c, bb, a, d, c] if face_n.dot(outward) >= 0.0 else [a, bb, c, a, c, d]
			for p in tris:
				target.set_normal(n_face)
				target.add_vertex(p)
	# Close the front and back of the cabin (glass end panels) only for closed cabins.
	var mesh := ArrayMesh.new()
	var gm := glass.commit()
	var rm := roof.commit()
	if gm.get_surface_count() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, gm.surface_get_arrays(0))
		mesh.surface_set_name(mesh.get_surface_count() - 1, "glass")
	if rm.get_surface_count() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rm.surface_get_arrays(0))
		mesh.surface_set_name(mesh.get_surface_count() - 1, "paint")
	return mesh
