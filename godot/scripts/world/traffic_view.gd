class_name TrafficView
extends Node3D
## Draws ambient traffic: two MultiMeshes (near / far LOD) per traffic model, fed every frame from
## NTSim's packed instance buffers (transform + custom data). Models are the real European cars
## baked by tools/carbake in "lite" form (<= 5 surfaces each, see traffic_car.gdshader), so all
## traffic costs ~50 draw calls.

const MAX_PER_MODEL := 90
const NEAR_DISTANCE := 45.0
## Native model slots (TrafficModel in native/src/sim/traffic.h) -> baked traffic car keys.
const MODEL_KEYS := ["vw_polo", "skoda_superb", "volvo_v60", "vw_t6", "mb_sprinter", "town_bus"]
const SHADER := preload("res://shaders/traffic_car.gdshader")
const PARTS := {"body": 0, "paint": 1, "glass": 2, "light_head": 3, "light_tail": 4}

var sim: NTSim
var _mm_near: Array[MultiMesh] = []
var _mm_far: Array[MultiMesh] = []
var _near := PackedFloat32Array()
var _far := PackedFloat32Array()

func _ready() -> void:
	_near.resize(MAX_PER_MODEL * 16)
	_far.resize(MAX_PER_MODEL * 16)
	for m in range(MODEL_KEYS.size()):
		var key: String = MODEL_KEYS[m]
		var meta := _meta(key)
		_mm_near.append(_make_mm(_load_mesh("res://assets/cars/%s/%s.gltf" % [key, key], meta, m), true))
		_mm_far.append(_make_mm(_load_mesh("res://assets/cars/%s/%s_lod1.gltf" % [key, key], meta, m), false))

func _make_mm(mesh: Mesh, near: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = MAX_PER_MODEL
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Instances are spread over ~800 m; skip per-instance culling cost.
	mmi.custom_aabb = AABB(Vector3(-5000, -100, -5000), Vector3(10000, 1000, 10000))
	add_child(mmi)
	return mm

static func _meta(key: String) -> Dictionary:
	var f := FileAccess.open("res://assets/cars/%s/%s.json" % [key, key], FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else {}

## One ArrayMesh with a traffic_car material per surface ("<part>:lite" material names).
static func _load_mesh(path: String, meta: Dictionary, model: int) -> Mesh:
	if not ResourceLoader.exists(path):
		push_warning("TrafficView: missing %s" % path)
		return BoxMesh.new()
	var inst := (load(path) as PackedScene).instantiate()
	var mi := inst.find_child("Body", true, false) as MeshInstance3D
	if mi == null:
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			mi = c
			break
	var mesh: ArrayMesh = (mi.mesh as ArrayMesh).duplicate() if mi and mi.mesh is ArrayMesh else null
	inst.free()
	if mesh == null:
		return BoxMesh.new()
	# Sim traffic cars sit centred at half height; the bakes have the ground at y=0 and the origin
	# mid-wheelbase.
	var b: Dictionary = meta.get("bounds", {"min": [0, 0, 0], "max": [0, 0, 0]})
	var half_h: float = [0.73, 0.73, 0.74, 1.0, 1.35, 1.52][model]
	var zc := (float(b.min[2]) + float(b.max[2])) * 0.5
	var offset := Vector3(0.0, -half_h - 0.02, -zc)
	for s in range(mesh.get_surface_count()):
		var src := mesh.surface_get_material(s)
		var tag := src.resource_name.get_slice(":", 0) if src else "body"
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("part", PARTS.get(tag, 0))
		m.set_shader_parameter("wheel_radius", float(meta.get("wheel_radius", 0.32)))
		m.set_shader_parameter("origin_offset", offset)
		mesh.surface_set_material(s, m)
	return mesh

func _process(_delta: float) -> void:
	if sim == null:
		return
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	var near2 := NEAR_DISTANCE * NEAR_DISTANCE
	for m in range(MODEL_KEYS.size()):
		var buf := sim.traffic_buffer(m)
		var count := mini(buf.size() / 16, MAX_PER_MODEL)
		var n_near := 0
		var n_far := 0
		for i in range(count):
			var o := i * 16
			var dx := buf[o + 3] - eye.x
			var dz := buf[o + 11] - eye.z
			# Packed arrays are value types: write the member arrays directly.
			if dx * dx + dz * dz < near2:
				var d := n_near * 16
				for k in range(16):
					_near[d + k] = buf[o + k]
				n_near += 1
			else:
				var d := n_far * 16
				for k in range(16):
					_far[d + k] = buf[o + k]
				n_far += 1
		_mm_near[m].buffer = _near
		_mm_near[m].visible_instance_count = n_near
		_mm_far[m].buffer = _far
		_mm_far[m].visible_instance_count = n_far
