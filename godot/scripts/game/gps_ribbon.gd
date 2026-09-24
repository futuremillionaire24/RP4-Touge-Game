class_name GPSRibbon
extends MeshInstance3D
## Dynamic 3D GPS navigation ribbon / Forza Horizon racing line projected onto the road.
## Features animated directional chevrons and real-time curvature braking zones (cyan -> amber -> red).

const SHADER := preload("res://shaders/gps_ribbon.gdshader")
const RIBBON_WIDTH := 1.15
const SURFACE_OFFSET := 0.06 # Height above asphalt to eliminate z-fighting

var _mat: ShaderMaterial
var _centers: PackedVector3Array
var _ups: PackedVector3Array
var _distance: PackedFloat32Array
var _curvature: PackedFloat32Array
var _active_route: Route

func _init() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Sets the ribbon to follow an active race route
func set_route(r: Route) -> void:
	_active_route = r
	if r == null or r.centers.size() < 2:
		mesh = null
		visible = false
		return
	_build_from_samples(r.centers, r.ups)
	visible = true

## Sets the ribbon to follow raw points and up-vectors
func set_samples(centers: PackedVector3Array, ups: PackedVector3Array) -> void:
	if centers.size() < 2:
		mesh = null
		visible = false
		return
	_build_from_samples(centers, ups)
	visible = true

func clear() -> void:
	mesh = null
	visible = false

func _build_from_samples(centers: PackedVector3Array, ups: PackedVector3Array) -> void:
	var n := centers.size()
	if n < 2:
		return
	
	_centers = centers
	_ups = ups
	
	# Compute tangents and segment lengths
	var tangents := PackedVector3Array()
	tangents.resize(n)
	var seg_lens := PackedFloat32Array()
	seg_lens.resize(n)
	var cum_dist := PackedFloat32Array()
	cum_dist.resize(n)
	var total_d := 0.0
	
	for i in range(n):
		var prev_idx := maxi(0, i - 1)
		var next_idx := mini(n - 1, i + 1)
		var t := (centers[next_idx] - centers[prev_idx]).normalized()
		if t.length_squared() < 0.01:
			t = Vector3.FORWARD
		tangents[i] = t
		
		if i > 0:
			var d := centers[i].distance_to(centers[i - 1])
			total_d += d
			seg_lens[i - 1] = d
		cum_dist[i] = total_d
	
	# Curvature calculation: change of direction per meter
	var raw_curv := PackedFloat32Array()
	raw_curv.resize(n)
	for i in range(n):
		if i == 0 or i == n - 1:
			raw_curv[i] = 0.0
			continue
		var d := maxf(centers[i + 1].distance_to(centers[i - 1]) * 0.5, 0.5)
		var dot := clampf(tangents[i - 1].dot(tangents[i + 1]), -1.0, 1.0)
		var ang := acos(dot)
		raw_curv[i] = ang / d
	
	# Look-ahead braking zones: spread curvature backwards by ~30m for anticipation
	var brake_zones := PackedFloat32Array()
	brake_zones.resize(n)
	for i in range(n):
		var max_c := raw_curv[i]
		# Look ahead up to 35 meters
		var d_accum := 0.0
		var k := i
		while k < n - 1 and d_accum < 35.0:
			var step: float = seg_lens[k]
			d_accum += step
			k += 1
			# Weight look-ahead curvature by inverse distance
			var weight := 1.0 - (d_accum / 35.0)
			max_c = maxf(max_c, raw_curv[k] * weight)
		brake_zones[i] = max_c

	# Build triangle strip mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var straight_col := Color(0.08, 0.88, 1.0, 0.72)
	var coast_col := Color(1.0, 0.82, 0.15, 0.78)
	var brake_col := Color(1.0, 0.12, 0.22, 0.88)
	
	var half_w := RIBBON_WIDTH * 0.5
	
	for i in range(n - 1):
		var p0 := centers[i]
		var p1 := centers[i + 1]
		var up0 := ups[i] if i < ups.size() else Vector3.UP
		var up1 := ups[i + 1] if i + 1 < ups.size() else Vector3.UP
		var t0 := tangents[i]
		var t1 := tangents[i + 1]
		
		var right0 := t0.cross(up0).normalized() * half_w
		var right1 := t1.cross(up1).normalized() * half_w
		
		# Offset slightly above road to prevent z-fighting
		var off0 := up0 * SURFACE_OFFSET
		var off1 := up1 * SURFACE_OFFSET
		
		var v0_l := p0 - right0 + off0
		var v0_r := p0 + right0 + off0
		var v1_l := p1 - right1 + off1
		var v1_r := p1 + right1 + off1
		
		# Color based on upcoming curvature (racing line brake guidance)
		var c0: Color
		var k0: float = brake_zones[i]
		if k0 > 0.038:
			c0 = brake_col
		elif k0 > 0.016:
			var t_blend := (k0 - 0.016) / (0.038 - 0.016)
			c0 = coast_col.lerp(brake_col, t_blend)
		else:
			var t_blend := clampf(k0 / 0.016, 0.0, 1.0)
			c0 = straight_col.lerp(coast_col, t_blend)
			
		var c1: Color
		var k1: float = brake_zones[i + 1]
		if k1 > 0.038:
			c1 = brake_col
		elif k1 > 0.016:
			var t_blend := (k1 - 0.016) / (0.038 - 0.016)
			c1 = coast_col.lerp(brake_col, t_blend)
		else:
			var t_blend := clampf(k1 / 0.016, 0.0, 1.0)
			c1 = straight_col.lerp(coast_col, t_blend)
			
		var uv_y0 := cum_dist[i] * 0.15
		var uv_y1 := cum_dist[i + 1] * 0.15
		
		# Quad (two triangles)
		# Tri 1: v0_l, v0_r, v1_l
		st.set_color(c0)
		st.set_uv(Vector2(0.0, uv_y0))
		st.add_vertex(v0_l)
		
		st.set_color(c0)
		st.set_uv(Vector2(1.0, uv_y0))
		st.add_vertex(v0_r)
		
		st.set_color(c1)
		st.set_uv(Vector2(0.0, uv_y1))
		st.add_vertex(v1_l)
		
		# Tri 2: v0_r, v1_r, v1_l
		st.set_color(c0)
		st.set_uv(Vector2(1.0, uv_y0))
		st.add_vertex(v0_r)
		
		st.set_color(c1)
		st.set_uv(Vector2(1.0, uv_y1))
		st.add_vertex(v1_r)
		
		st.set_color(c1)
		st.set_uv(Vector2(0.0, uv_y1))
		st.add_vertex(v1_l)
		
	mesh = st.commit()
