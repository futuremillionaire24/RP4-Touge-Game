class_name CarBuilder
extends RefCounted
## Builds a car's visual rig from the real model baked by tools/carbake
## (res://assets/cars/<key>/<key>.gltf + .json):
##   Body                       every non-wheel mesh; materials tagged "<class>:<source name>"
##   Wheel_XX/Wheel_XX_Spin     tyre, rim and disc around the hub (spins + steers)
##   Wheel_XX/Wheel_XX_Caliper  calliper (steers, never spins)
## The model is aligned so its hubs sit on the simulated hubs (the physics roster uses the baked
## wheelbase, track and radii). Materials: paint -> car_paint.gdshader (player colour/finish,
## optional livery), glass -> tinted transparent glass, lamps -> per-car emissive copies driven by
## set_light_state(), everything else keeps the model's own PBR materials.
## Root metas used by CarView / CarStage: "wheels" (4 pivots, child 0 = spin), "paint"
## (ShaderMaterial), "lamps" ({head, tail, reverse, signal} -> [materials]), "exhaust_local",
## "exhausts_local", "headlights_local", "taillights_local".

const LAMP_TAIL_IDLE := 0.0
const LAMP_TAIL_ON := 1.6
const LAMP_BRAKE := 5.0
const LAMP_HEAD_ON := 5.5
const LAMP_REVERSE := 3.0
const WHEEL_NAMES := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]

static var _scene_cache := {}
static var _glass: StandardMaterial3D

static func shared_material(name: String) -> Material:
	return CarMaterials.shared(name)

static func paint_material(key: String, color_override = null, finish_override = "") -> ShaderMaterial:
	return CarMaterials.paint_material(key, color_override, finish_override)

## Tinted automotive glass: transparent so the modelled cabins show, strong clear-coat reflection.
static func glass_material() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.resource_name = "car_glass"
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Dark tint (real windscreens transmit ~70%, side/rear privacy glass far less); plain
		# dielectric reflectance so bright skies don't turn the glass into a white mirror.
		_glass.albedo_color = Color(0.015, 0.02, 0.025, 0.62)
		_glass.metallic = 0.0
		_glass.roughness = 0.04
		_glass.metallic_specular = 0.5
	return _glass

static func _scene(key: String) -> PackedScene:
	var path := CarData.model_path(key)
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _scene_cache[path]

## Builds the full visual rig. `spec` = NTSim.get_car_spec(), `wheels` = NTSim.get_wheel_data().
static func build(key: String, spec: Dictionary, wheels: PackedFloat32Array, paint: Material = null, _is_player := false) -> Node3D:
	key = CarData.resolve(key)
	var car := CarData.get_car(key)
	var meta := CarData.model_meta(key)
	var root := Node3D.new()
	root.name = "CarVisual"
	if paint == null:
		paint = paint_material(key)
	var scene := _scene(key)
	var model: Node3D = scene.instantiate() if scene else Node3D.new()
	model.name = "Model"
	root.add_child(model)

	# Align hubs: model hubs (bake metadata, car frame with the ground at y=0) onto the simulated hubs.
	var sim_hubs := wheel_list(wheels)
	var model_hubs: Array = []
	var baked_wheels = meta.get("wheels")
	if baked_wheels is Array:
		for w in baked_wheels:
			model_hubs.append(Vector3(w.pos[0], w.pos[1], w.pos[2]))
	if model_hubs.size() == 4:
		var ds := Vector3.ZERO
		for i in range(4):
			ds += sim_hubs[i].pos - model_hubs[i]
		model.position = ds / 4.0
	else:
		model.position = Vector3(0, -float(spec.get("cg_height", 0.45)), 0)

	# Materials.
	var lamps := {"head": [], "tail": [], "reverse": [], "signal": []}
	var livery_mode: String = car.get("livery", "")
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		_dress(mi as MeshInstance3D, paint as ShaderMaterial, livery_mode, lamps)

	# Wheel pivots at the root (CarView drives position/steer; child 0 spins).
	var pivots := []
	for i in range(4):
		var src := model.find_child(WHEEL_NAMES[i], true, false) as Node3D
		if src == null:
			# No detachable wheels in this model: procedural wheels instead.
			var w := CarWheels.make_wheel(i, sim_hubs[i], car)
			root.add_child(w)
			pivots.append(w)
			continue
		var pivot := Node3D.new()
		pivot.name = WHEEL_NAMES[i] + "_Pivot"
		pivot.position = sim_hubs[i].pos
		root.add_child(pivot)
		var spin := Node3D.new()
		spin.name = "Spin"
		pivot.add_child(spin)
		for part in [WHEEL_NAMES[i] + "_Spin", WHEEL_NAMES[i] + "_Caliper"]:
			var n := src.find_child(part, true, false) as Node3D
			if n == null:
				continue
			n.owner = null
			n.get_parent().remove_child(n)
			n.transform = Transform3D.IDENTITY
			(spin if part.ends_with("_Spin") else pivot).add_child(n)
		pivots.append(pivot)

	var off := model.position
	root.set_meta("wheels", pivots)
	root.set_meta("paint", paint)
	root.set_meta("lamps", lamps)
	root.set_meta("headlights_local", _anchors(meta, "headlights", off))
	root.set_meta("taillights_local", _anchors(meta, "taillights", off))
	var exh := _anchors(meta, "exhausts", off)
	var rear_z: float = float(meta.get("bounds", {}).get("max", [0, 0, 2.2])[2]) + off.z
	root.set_meta("exhausts_local", exh)
	root.set_meta("exhaust_local", exh[0] if not exh.is_empty() else Vector3(0.35, 0.3 + off.y, rear_z - 0.05))
	root.set_meta("brake_lights", lamps.get("tail", []))
	root.set_meta("headlights", lamps.get("head", []))
	root.set_meta("popups", [])
	set_light_state(root, false, false)
	return root

static func _anchors(meta: Dictionary, list_key: String, off: Vector3) -> Array:
	var out := []
	var src = meta.get(list_key, [])
	if src == null:
		return out
	for p in src:
		out.append(Vector3(p[0], p[1], p[2]) + off)
	return out

## Assigns game materials to one mesh by the bake's material class tag.
static func _dress(mi: MeshInstance3D, paint: ShaderMaterial, livery_mode: String, lamps: Dictionary) -> void:
	if mi.mesh == null:
		return
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for s in range(mi.mesh.get_surface_count()):
		var src := mi.mesh.surface_get_material(s)
		var tag := src.resource_name if src else ""
		var cls := tag.get_slice(":", 0) if tag.contains(":") else "other"
		match cls:
			"paint":
				if livery_mode != "" and src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
					paint.set_shader_parameter("livery", (src as BaseMaterial3D).albedo_texture)
					paint.set_shader_parameter("use_livery", true)
					paint.set_shader_parameter("tint_livery", livery_mode == "tint")
				mi.set_surface_override_material(s, paint)
			"glass":
				mi.set_surface_override_material(s, glass_material())
			"light_head", "light_tail", "light_reverse", "light_signal":
				var m := _lamp_material(src, cls)
				mi.set_surface_override_material(s, m)
				lamps[cls.substr(6)].append(m)
			"tyre":
				if src is BaseMaterial3D:
					var t := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
					t.metallic = 0.0
					t.roughness = maxf(t.roughness, 0.82)
					mi.set_surface_override_material(s, t)
			_:
				pass

## Per-car emissive copy of a lamp material (keeps the lens texture when the model has one).
static func _lamp_material(src: Material, cls: String) -> StandardMaterial3D:
	var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
	m.emission_enabled = true
	match cls:
		"light_head":
			m.emission = Color(0.95, 0.97, 1.0)
		"light_tail":
			m.emission = Color(1.0, 0.03, 0.02)
			if m.albedo_texture == null:
				m.albedo_color = Color(0.45, 0.02, 0.02, m.albedo_color.a)
		"light_reverse":
			m.emission = Color(1.0, 1.0, 1.0)
		_:
			m.emission = Color(1.0, 0.45, 0.02)
	if m.albedo_texture != null:
		m.emission_texture = m.albedo_texture
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.emission_energy_multiplier = 0.0
	return m

## Brake / tail / head / reverse lamp emission (called by CarView every physics tick).
static func set_light_state(root: Node3D, braking: bool, lights_on: bool, reversing := false) -> void:
	var lamps: Dictionary = root.get_meta("lamps", {})
	if lamps.is_empty():
		CarDetails.set_light_state(root, braking, lights_on)
		return
	var tail := LAMP_BRAKE if braking else (LAMP_TAIL_ON if lights_on else LAMP_TAIL_IDLE)
	for m in lamps.tail:
		(m as StandardMaterial3D).emission_energy_multiplier = tail
	for m in lamps.head:
		(m as StandardMaterial3D).emission_energy_multiplier = LAMP_HEAD_ON if lights_on else 0.15
	for m in lamps.reverse:
		(m as StandardMaterial3D).emission_energy_multiplier = LAMP_REVERSE if reversing else 0.0

static func wheel_list(data: PackedFloat32Array) -> Array:
	var out := []
	var stride := 16
	for i in range(4):
		var o := i * stride
		out.append({
			"pos": Vector3(data[o], data[o + 1], data[o + 2]),
			"radius": data[o + 5],
			"width": 0.22 if i < 2 else 0.24,
		})
	return out
