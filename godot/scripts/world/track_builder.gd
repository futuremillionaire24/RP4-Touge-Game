class_name TrackBuilder
extends RefCounted
## Builds a closed or open road from control points through the native mesher: render meshes
## (road / shoulder / curb / barriers), collision chunks for NTSim and the AI racing line.

const ROAD_SHADER := preload("res://shaders/road.gdshader")
const CURB_SHADER := preload("res://shaders/curb.gdshader")
const GROUND_SHADER := preload("res://shaders/ground.gdshader")

enum Surf { ASPHALT, ASPHALT_WORN, CONCRETE, PAINT, CURB, GRAVEL, DIRT, GRASS, SAND, SNOW, ICE, METAL, COBBLE, WALL, GUARDRAIL, BUILDING, WATER }
enum Barrier { NONE, GUARDRAIL, WALL, TIREWALL, FENCE }

static var _materials := {}

static func material_for_group(group: int) -> Material:
	if _materials.has(group):
		return _materials[group]
	var m: Material
	match group:
		0:
			var s := ShaderMaterial.new()
			s.shader = ROAD_SHADER
			m = s
		1:
			var s := ShaderMaterial.new()
			s.shader = load("res://shaders/verge.gdshader")
			m = s
		2:
			var s := ShaderMaterial.new()
			s.shader = CURB_SHADER
			m = s
		3:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.7, 0.72, 0.74)
			sm.metallic = 0.85
			sm.roughness = 0.35
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = sm
		4:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.58, 0.57, 0.55)
			sm.roughness = 0.85
			m = sm
		5:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.55, 0.56, 0.58)
			sm.metallic = 0.6
			sm.roughness = 0.5
			m = sm
		6:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.05, 0.05, 0.055)
			sm.roughness = 0.9
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = sm
		_:
			m = StandardMaterial3D.new()
	_materials[group] = m
	return m

## samples: output of NTRoad.resample; per-sample dictionaries of arrays as accepted by NTRoad.build.
static func build_road(parent: Node3D, sim: NTSim, chunk_id: int, samples: Dictionary, options: Dictionary) -> MeshInstance3D:
	var result := NTRoad.build(samples, options)
	var mesh := NTRoad.make_mesh(result)
	var mi := MeshInstance3D.new()
	mi.name = "Road_%d" % chunk_id
	mi.mesh = mesh
	var groups: PackedInt32Array = mesh.get_meta("surface_groups")
	for s in range(groups.size()):
		mi.set_surface_override_material(s, material_for_group(groups[s]))
	parent.add_child(mi)
	if sim:
		sim.set_collision_chunk(chunk_id, result.collision_faces, result.collision_surfaces, result.collision_flags)
	return mi

## Flat ground made of tiles; each tile becomes one collision chunk so streaming can drop them.
static func build_ground(parent: Node3D, sim: NTSim, center: Vector3, half_size: float, tile: float, height: float, surface: int, first_chunk_id: int) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("kind", 0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_size * 2.0, half_size * 2.0)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(center.x, height, center.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if sim == null:
		return
	var id := first_chunk_id
	var x := -half_size
	while x < half_size:
		var z := -half_size
		while z < half_size:
			var a := Vector3(center.x + x, height, center.z + z)
			var b := Vector3(center.x + x, height, center.z + z + tile)
			var c := Vector3(center.x + x + tile, height, center.z + z + tile)
			var d := Vector3(center.x + x + tile, height, center.z + z)
			var faces := PackedVector3Array([a, b, c, a, c, d])
			sim.set_collision_chunk(id, faces, PackedByteArray([surface, surface]), PackedByteArray([3, 3]))
			id += 1
			z += tile
		x += tile

## Computes per-sample road attributes for a racing circuit: curbs and tire walls on the
## outside of corners, gravel traps, straights with plain verges.
static func circuit_samples(points: PackedVector3Array, tangents: PackedVector3Array, half_width: float) -> Dictionary:
	var n := points.size()
	var curv := PackedFloat32Array()
	curv.resize(n)
	for i in range(n):
		var a := points[(i - 3 + n) % n]
		var b := points[i]
		var c := points[(i + 3) % n]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var bc := Vector2(c.x - b.x, c.z - b.z)
		var ac := Vector2(c.x - a.x, c.z - a.z)
		var den := ab.length() * bc.length() * ac.length()
		curv[i] = 2.0 * (ab.x * bc.y - ab.y * bc.x) / den if den > 1e-6 else 0.0
	var wl := PackedFloat32Array()
	var wr := PackedFloat32Array()
	var sl := PackedFloat32Array()
	var sr := PackedFloat32Array()
	var cl := PackedByteArray()
	var cr := PackedByteArray()
	var bl := PackedByteArray()
	var br := PackedByteArray()
	var ss := PackedByteArray()
	for arr in [wl, wr, sl, sr]:
		arr.resize(n)
	for arr in [cl, cr, bl, br, ss]:
		arr.resize(n)
	for i in range(n):
		# Smooth curvature over a window to decide corner furniture.
		var k := 0.0
		for j in range(-6, 7):
			k += curv[(i + j + n) % n]
		k /= 13.0
		var corner := absf(k) > 1.0 / 180.0
		var right_turn := k > 0.0
		wl[i] = half_width
		wr[i] = half_width
		cl[i] = 1 if corner and not right_turn else 0 # inside curb = apex side
		cr[i] = 1 if corner and right_turn else 0
		# Outside of the corner gets a gravel trap and a tire wall; inside gets grass run-off.
		var outside_trap := 9.0 if corner else 4.0
		sl[i] = outside_trap if (corner and right_turn) else 4.0
		sr[i] = outside_trap if (corner and not right_turn) else 4.0
		bl[i] = Barrier.TIREWALL if (corner and right_turn) else Barrier.GUARDRAIL
		br[i] = Barrier.TIREWALL if (corner and not right_turn) else Barrier.GUARDRAIL
		ss[i] = Surf.GRAVEL if corner else Surf.GRASS
	return {
		"centers": points, "width_left": wl, "width_right": wr, "shoulder_left": sl, "shoulder_right": sr,
		"curb_left": cl, "curb_right": cr, "barrier_left": bl, "barrier_right": br, "shoulder_surface": ss,
	}
