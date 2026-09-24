class_name WheelGeo
extends RefCounted
## Procedural rim mesh builder. Reads parameters from WheelDesigns and generates real spoke
## geometry with hub, fillets, lip, and face ring. Outputs an ArrayMesh with "rim" and
## optionally "lip" surfaces. Cached per (design_id, radius, width) so identical wheels share.

const WheelDesigns := preload("res://scripts/vehicle/wheel_designs.gd")

static var _cache := {} # "(id)_(r)_(w)" -> ArrayMesh

static func build_rim(design_id: String, radius: float, width: float) -> ArrayMesh:
	var cache_key := "%s_%.3f_%.3f" % [design_id, radius, width]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var d := WheelDesigns.design(design_id)
	var mesh := _generate(d, radius, width)
	_cache[cache_key] = mesh
	return mesh

static func _generate(d: Dictionary, radius: float, width: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# Normalize design parameters relative to a reference 17" rim (0.2159 m radius).
	var ref_r := 0.2159
	var scale_r := radius / ref_r
	var hub_r: float = d.hub_r * scale_r
	var lip_w: float = d.lip_w * scale_r
	var dish: float = d.dish * scale_r
	var concave: float = d.concave * scale_r
	var ring_w: float = d.ring_w * scale_r
	var thick: float = d.thick * scale_r
	var n_spokes: int = d.n
	var spoke_steps: int = d.steps
	var twist: float = d.twist
	var half_w := width * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# ---- Hub disc ----
	var hub_segs := 32
	_emit_disc(st, hub_r, hub_segs, -half_w + dish + concave, Vector3(0, 0, -1))

	# ---- Face ring (between spokes and lip) ----
	var face_r := radius - lip_w - ring_w
	_emit_ring(st, face_r, radius - lip_w, 48, -half_w + dish, Vector3(0, 0, -1))

	# ---- Spokes ----
	match d.family:
		"spoke", "split", "y":
			_emit_spokes(st, d, n_spokes, hub_r, face_r, half_w, dish, concave, thick, twist, spoke_steps, scale_r)
		"cross":
			# Cross-mesh: two sets of spokes crossing in opposite twist directions.
			_emit_spokes(st, d, n_spokes, hub_r, face_r, half_w, dish, concave, thick, twist, spoke_steps, scale_r)
			_emit_spokes(st, d, n_spokes, hub_r, face_r, half_w, dish, concave, thick, -twist, spoke_steps, scale_r)
		"holes":
			# Solid disc with windows punched out (simplified: just the solid disc).
			_emit_disc(st, face_r, 48, -half_w + dish, Vector3(0, 0, -1))

	# ---- Lip (outer ring, stepped if dish > 0) ----
	var lip_st := SurfaceTool.new()
	lip_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Lip floor.
	_emit_ring(lip_st, radius - lip_w, radius, 48, -half_w, Vector3(0, 0, -1))
	# Lip step wall (connects dish to the lip floor).
	if dish > 0.002:
		_emit_cylinder_band(lip_st, radius - lip_w, 48, -half_w + dish, -half_w, true)
	# Outer barrel.
	_emit_cylinder_band(lip_st, radius, 48, -half_w, half_w, true)
	# Inner barrel.
	_emit_cylinder_band(lip_st, radius * 0.95, 32, half_w, -half_w + dish + concave, false)
	# Back face disc.
	_emit_disc(lip_st, radius * 0.95, 32, half_w, Vector3(0, 0, 1))

	# ---- Assembly bolts on the face ring ----
	if d.bolts > 0:
		var bolt_r := (face_r + radius - lip_w) * 0.5
		var bolt_size := 0.004 * scale_r
		for i in range(d.bolts):
			var a := TAU * float(i) / float(d.bolts)
			var pos := Vector3(cos(a) * bolt_r, sin(a) * bolt_r, -half_w + dish - 0.001)
			_emit_bolt(st, pos, bolt_size)

	var rim_mesh := st.commit()
	var lip_mesh := lip_st.commit()
	if rim_mesh.get_surface_count() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rim_mesh.surface_get_arrays(0))
		mesh.surface_set_name(0, "rim")
	if lip_mesh.get_surface_count() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lip_mesh.surface_get_arrays(0))
		mesh.surface_set_name(mesh.get_surface_count() - 1, "lip")
	return mesh


## Generate spoke geometry for spoke/split/y families.
static func _emit_spokes(st: SurfaceTool, d: Dictionary, n: int, hub_r: float, face_r: float,
		half_w: float, dish: float, concave: float, thick: float, twist: float,
		steps: int, scale_r: float) -> void:
	var w_in: float = d.w_in * scale_r
	var w_out: float = d.w_out * scale_r
	var fil_in: float = d.fil_in * scale_r
	var fil_out: float = d.fil_out * scale_r
	var fil_len: float = d.fil_len
	var split: float = d.get("split", 0.0) * scale_r
	var crown: float = d.crown * scale_r
	var family: String = d.family
	var k_concave: float = d.get("k", 1.5)

	for i in range(n):
		var base_angle := TAU * float(i) / float(n)
		if family == "split" and split > 0.001:
			# Twin spokes: offset each side by half the split at the outer end.
			for side in [-1.0, 1.0]:
				_emit_single_spoke(st, base_angle, side * split * 0.5, hub_r, face_r,
					half_w, dish, concave, k_concave, w_in * 0.7, w_out * 0.8, fil_in * 0.7, fil_out * 0.7,
					fil_len, thick, twist, crown, steps)
		else:
			_emit_single_spoke(st, base_angle, 0.0, hub_r, face_r,
				half_w, dish, concave, k_concave, w_in, w_out, fil_in, fil_out,
				fil_len, thick, twist, crown, steps)


## Emit one spoke as a lofted strip from hub_r to face_r.
static func _emit_single_spoke(st: SurfaceTool, base_angle: float, split_offset: float,
		hub_r: float, face_r: float, half_w: float, dish: float, concave: float, k_concave: float,
		w_in: float, w_out: float, fil_in: float, fil_out: float, fil_len: float,
		thick: float, twist: float, crown: float, steps: int) -> void:
	# Build cross-section stations along the spoke from hub to rim.
	var sections := []
	for s in range(steps + 1):
		var t := float(s) / float(steps)
		var r := lerpf(hub_r, face_r, t)
		var angle := base_angle + twist * t
		if t > 0.5:
			angle += split_offset / r  # Apply split offset in the outer half.
		# Spoke width with fillets: wider at hub/rim, narrower in the middle.
		var w := lerpf(w_in, w_out, t)
		# Fillet widening at hub end.
		if t < fil_len:
			var fk := 1.0 - smoothstep(0.0, fil_len, t)
			w += fil_in * fk
		# Fillet widening at rim end.
		if t > 1.0 - fil_len:
			var fk := smoothstep(1.0 - fil_len, 1.0, t)
			w += fil_out * fk
		# Depth: concave bowl from hub, rising to the face ring level.
		var z := -half_w + dish + concave * pow(1.0 - t, k_concave)
		# Crown: slight convex top.
		var crown_h := crown * sin(t * PI)
		var center := Vector3(cos(angle) * r, sin(angle) * r, z - crown_h)
		var tangent := Vector3(-sin(angle), cos(angle), 0.0)
		sections.append({"center": center, "tangent": tangent, "width": w, "thick": thick})

	# Loft the spoke: top face, two side walls.
	for s in range(sections.size() - 1):
		var a: Dictionary = sections[s]
		var b: Dictionary = sections[s + 1]
		# Top face quad.
		var a_left: Vector3 = a.center - a.tangent * a.width * 0.5
		var a_right: Vector3 = a.center + a.tangent * a.width * 0.5
		var b_left: Vector3 = b.center - b.tangent * b.width * 0.5
		var b_right: Vector3 = b.center + b.tangent * b.width * 0.5
		var top_n := Vector3(0, 0, -1)
		_quad(st, a_left, a_right, b_right, b_left, top_n)
		# Side walls.
		var a_left_bot: Vector3 = a_left + Vector3(0, 0, a.thick)
		var a_right_bot: Vector3 = a_right + Vector3(0, 0, a.thick)
		var b_left_bot: Vector3 = b_left + Vector3(0, 0, b.thick)
		var b_right_bot: Vector3 = b_right + Vector3(0, 0, b.thick)
		var left_n: Vector3 = -a.tangent
		var right_n: Vector3 = a.tangent
		_quad(st, a_left_bot, a_left, b_left, b_left_bot, left_n)
		_quad(st, a_right, a_right_bot, b_right_bot, b_right, right_n)
		# Bottom face.
		var bot_n := Vector3(0, 0, 1)
		_quad(st, a_right_bot, a_left_bot, b_left_bot, b_right_bot, bot_n)

static func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / maxf(edge1 - edge0, 1e-6), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Helpers ----

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	for v in [a, c, b, a, d, c]:
		st.set_normal(n)
		st.add_vertex(v)

static func _emit_disc(st: SurfaceTool, radius: float, segs: int, z: float, normal: Vector3) -> void:
	var center := Vector3(0, 0, z)
	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, z)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, z)
		if normal.z < 0:
			for v in [center, p0, p1]:
				st.set_normal(normal)
				st.add_vertex(v)
		else:
			for v in [center, p1, p0]:
				st.set_normal(normal)
				st.add_vertex(v)

static func _emit_ring(st: SurfaceTool, inner_r: float, outer_r: float, segs: int, z: float, normal: Vector3) -> void:
	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var i0 := Vector3(cos(a0) * inner_r, sin(a0) * inner_r, z)
		var i1 := Vector3(cos(a1) * inner_r, sin(a1) * inner_r, z)
		var o0 := Vector3(cos(a0) * outer_r, sin(a0) * outer_r, z)
		var o1 := Vector3(cos(a1) * outer_r, sin(a1) * outer_r, z)
		if normal.z < 0:
			_quad(st, i0, o0, o1, i1, normal)
		else:
			_quad(st, i1, o1, o0, i0, normal)

static func _emit_cylinder_band(st: SurfaceTool, radius: float, segs: int, z0: float, z1: float, outward: bool) -> void:
	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)
		var p00 := Vector3(c0 * radius, s0 * radius, z0)
		var p01 := Vector3(c0 * radius, s0 * radius, z1)
		var p10 := Vector3(c1 * radius, s1 * radius, z0)
		var p11 := Vector3(c1 * radius, s1 * radius, z1)
		var n := Vector3((c0 + c1) * 0.5, (s0 + s1) * 0.5, 0).normalized()
		if not outward:
			n = -n
		if outward:
			_quad(st, p00, p10, p11, p01, n)
		else:
			_quad(st, p01, p11, p10, p00, n)

static func _emit_bolt(st: SurfaceTool, pos: Vector3, size: float) -> void:
	# Hex bolt head: 6-sided prism approximated as a flat hex disc.
	var segs := 6
	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := pos + Vector3(cos(a0) * size, sin(a0) * size, 0)
		var p1 := pos + Vector3(cos(a1) * size, sin(a1) * size, 0)
		for v in [pos, p0, p1]:
			st.set_normal(Vector3(0, 0, -1))
			st.add_vertex(v)

## Build a tyre mesh with a rounded sidewall profile.
static func build_tyre(radius: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 32
	var prof_steps := 8
	# Tyre profile: flat tread, rounded shoulders, curved sidewall.
	var profile := [] # Array of (r_offset, z_offset) relative to nominal radius/width.
	var half_w := width * 0.5
	var shoulder := radius * 0.06  # shoulder rounding radius
	for p in range(prof_steps + 1):
		var t := float(p) / float(prof_steps)
		var z := lerpf(-half_w, half_w, t)
		var r := radius
		# Shoulder rounding at the tread edges.
		var edge_dist := half_w - absf(z)
		if edge_dist < shoulder:
			var k := 1.0 - edge_dist / shoulder
			r -= shoulder * (1.0 - sqrt(1.0 - k * k))
		# Sidewall taper: inner part curves inward.
		if edge_dist < shoulder * 2.5:
			var sw := smoothstep(shoulder * 2.5, 0.0, edge_dist)
			r -= sw * radius * 0.12
		profile.append(Vector2(r, z))

	# Revolve the profile.
	var grid := []
	for i in range(segs + 1):
		var a := TAU * float(i) / float(segs)
		var row := []
		for pt in profile:
			row.append(Vector3(cos(a) * pt.x, sin(a) * pt.x, pt.y))
		grid.append(row)

	# Emit the revolved grid.
	for i in range(segs):
		for j in range(prof_steps):
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i][j + 1]
			var c: Vector3 = grid[i + 1][j + 1]
			var dd: Vector3 = grid[i + 1][j]
			var n: Vector3 = (b - a).cross(dd - a).normalized()
			_quad(st, a, b, c, dd, n)

	return st.commit()
