extends RefCounted
## Presentation helpers shared by the showroom (tools/showroom.gd) and the menu stage
## (scripts/ui/car_stage.gd): an emissive-panel "light rig" that exists twice, once as visible
## geometry and once analytically inside a sky shader (so paint / glass / clearcoat reflect the
## softboxes at full radiance-map resolution), a cyclorama, and car layer helpers.
## Panel dict: {c: Vector3, u: Vector3, v: Vector3, color: Color, energy: float, soft: float,
##              tube: bool, visible: bool}

const SKY_SHADER := preload("res://shaders/present_sky.gdshader")
const EMITTER_SHADER := preload("res://shaders/present_emitter.gdshader")
const CYC_SHADER := preload("res://shaders/present_cyc.gdshader")

## Render layer the cars live on (probes capture only the set, not the car inside them).
const CAR_LAYER := 2
const SET_LAYER := 1
## Light-rig layer: softbox geometry seen by probes but not by the showroom camera.
const RIG_LAYER := 3

static func sky_material(panels: Array, room: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SKY_SHADER
	var c := PackedVector3Array()
	var u := PackedVector3Array()
	var v := PackedVector3Array()
	var col := PackedVector4Array()
	for p in panels:
		if c.size() >= 12:
			break
		if not p.get("in_sky", true):
			continue
		c.append(p.c)
		u.append(p.u)
		v.append(p.v)
		var k: Color = p.get("color", Color.WHITE)
		var e: float = p.get("energy", 1.0) * p.get("sky_gain", 1.0)
		col.append(Vector4(k.r * e, k.g * e, k.b * e, p.get("soft", 0.08)))
	var n := c.size()
	c.resize(12)
	u.resize(12)
	v.resize(12)
	col.resize(12)
	m.set_shader_parameter("panel_count", n)
	m.set_shader_parameter("panel_c", c)
	m.set_shader_parameter("panel_u", u)
	m.set_shader_parameter("panel_v", v)
	m.set_shader_parameter("panel_col", col)
	for k in room.keys():
		m.set_shader_parameter(k, room[k])
	return m

## Visible panel geometry (one quad per panel), so the camera, the floor and probes see them.
static func add_panels(parent: Node3D, panels: Array, layer := SET_LAYER) -> void:
	for p in panels:
		if not p.get("visible", true):
			continue
		var u: Vector3 = p.u
		var v: Vector3 = p.v
		var mi := MeshInstance3D.new()
		mi.name = "Panel"
		var qm := QuadMesh.new()
		qm.size = Vector2(2.0, 2.0)
		mi.mesh = qm
		# Quad spans local X/Y in [-1, 1]; map X -> u, Y -> v.
		var n := u.cross(v).normalized()
		mi.transform = Transform3D(Basis(u, v, n), p.c)
		var m := ShaderMaterial.new()
		m.shader = EMITTER_SHADER
		var k: Color = p.get("color", Color.WHITE)
		var e: float = p.get("energy", 1.0) * p.get("geo_gain", 1.0)
		m.set_shader_parameter("color", Vector4(k.r * e, k.g * e, k.b * e, p.get("soft", 0.08)))
		m.set_shader_parameter("tube", p.get("tube", false))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1 << (layer - 1)
		parent.add_child(mi)

## Seamless cyclorama: flat floor out to `radius`, quarter-circle cove, wall up to `height`.
static func cyclorama(radius: float, cove: float, height: float, segs := 96) -> ArrayMesh:
	var prof := PackedVector2Array() # (r, y)
	prof.append(Vector2(0.0, 0.0))
	for i in range(1, 7):
		prof.append(Vector2((radius - cove) * float(i) / 6.0, 0.0))
	for i in range(1, 13):
		var a := float(i) / 12.0 * PI * 0.5
		prof.append(Vector2(radius - cove + sin(a) * cove, cove - cos(a) * cove))
	prof.append(Vector2(radius, height * 0.5))
	prof.append(Vector2(radius, height))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := prof.size()
	for j in range(segs + 1):
		var a := float(j) / float(segs) * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		for i in range(rows):
			var p := prof[i]
			# Normal: up on the floor, inward on the wall, blended through the cove.
			var nrm := Vector3.UP
			if i > 0:
				var q := prof[i - 1]
				var t := (p - q).normalized()
				nrm = (Vector3.UP * t.x - dir * t.y).normalized()
			st.set_normal(nrm)
			st.set_uv(Vector2(float(j) / segs, float(i) / rows))
			st.add_vertex(dir * p.x + Vector3(0, p.y, 0))
	for j in range(segs):
		for i in range(rows - 1):
			var a0 := j * rows + i
			var b0 := (j + 1) * rows + i
			st.add_index(a0)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(b0 + 1)
	return st.commit()

static func cyc_material(floor_albedo: Color, wall_albedo: Color, floor_roughness: float, cove_top: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CYC_SHADER
	m.set_shader_parameter("floor_albedo", floor_albedo)
	m.set_shader_parameter("wall_albedo", wall_albedo)
	m.set_shader_parameter("floor_roughness", floor_roughness)
	m.set_shader_parameter("cove_top", cove_top)
	return m

## Puts every GeometryInstance3D under `root` on `layer` (lights keep their layers).
static func set_layer_recursive(root: Node, layer: int) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).layers = 1 << (layer - 1)
	for c in root.get_children():
		set_layer_recursive(c, layer)

## World-space AABB of every mesh under `root`.
static func visual_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).is_visible_in_tree():
			var mi := n as MeshInstance3D
			if mi.get_meta("present_ignore", false):
				continue
			var bb := mi.global_transform * mi.get_aabb()
			if first:
				out = bb
				first = false
			else:
				out = out.merge(bb)
		for c in n.get_children():
			stack.append(c)
	return out
