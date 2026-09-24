class_name CarBuilder
extends RefCounted
## Assembles a car's visual rig from the builder modules:
##   CarBody      (car_body.gd)      body loft + greenhouse meshes
##   CarMaterials (car_materials.gd) paint + shared material library
##   CarDetails   (car_details.gd)   lights, grille, plates, mirrors, wing, exhaust, interior
##   CarWheels    (car_wheels.gd)    tyres, rims, brakes
## All dimensions come from the physics spec so visuals always match the hull.
## Root metas used by CarView: "wheels" (4 pivots), "paint" (ShaderMaterial), "brake_lights",
## "exhaust_local".

static func shared_material(name: String) -> Material:
	return CarMaterials.shared(name)

static func paint_material(key: String, color_override = null, finish_override = "") -> ShaderMaterial:
	return CarMaterials.paint_material(key, color_override, finish_override)

## Builds the full visual rig. `spec` = NTSim.get_car_spec(), `wheels` = NTSim.get_wheel_data().
## `is_player` = true enables subdivision LOD 1 for smooth specular highlights.
static func build(key: String, spec: Dictionary, wheels: PackedFloat32Array, paint: Material = null, is_player := false) -> Node3D:
	var car := CarData.get_car(key)
	var b: Dictionary = car.body
	var he: Vector3 = spec.half_extents
	var cg: float = spec.cg_height
	var root := Node3D.new()
	root.name = "CarVisual"
	if paint == null:
		paint = paint_material(key)
	var dims := {"hx": he.x, "hz": he.z, "cg": cg, "wheels": wheel_list(wheels), "key": key}
	var lod := 1 if is_player else 0

	# Use external 3D model if registered, or default to standard model path for the car
	var model_path: String = car.get("model_path", "res://assets/models/cars/%s.tscn" % key)

	if model_path != "" and ResourceLoader.exists(model_path):
		var model_scene := load(model_path) as PackedScene
		if model_scene != null:
			var model_inst := model_scene.instantiate() as Node3D
			if model_inst != null:
				root.add_child(model_inst)
				model_inst.name = "ModelMesh"

				# In Neon Touge, all cars face -Z. Models from asset packs face +Z; rotate 180° around Y
				var faces_backward := (key != "kurogane_hyper")
				if faces_backward:
					model_inst.rotation.y = PI

				# Hide static wheel nodes in the model so dynamic CarWheels mount cleanly
				var brake_lights := []
				var headlights := []
				var min_v := Vector3(INF, INF, INF)
				var max_v := Vector3(-INF, -INF, -INF)
				var stack: Array[Node] = [model_inst]
				while not stack.is_empty():
					var n: Node = stack.pop_back()
					var n_name := n.name.to_lower()
					if n_name.begins_with("wheel") or n_name.contains("rim") or n_name.contains("tire") or n_name.contains("brakepad"):
						if n is Node3D:
							(n as Node3D).visible = false
					elif n_name.contains("brake") or n_name.contains("tail"):
						brake_lights.append(n)
					elif n_name.contains("head"):
						headlights.append(n)
					if n is MeshInstance3D:
						var mi := n as MeshInstance3D
						var aabb: AABB = mi.get_aabb()
						min_v.x = minf(min_v.x, aabb.position.x)
						min_v.y = minf(min_v.y, aabb.position.y)
						min_v.z = minf(min_v.z, aabb.position.z)
						max_v.x = maxf(max_v.x, aabb.end.x)
						max_v.y = maxf(max_v.y, aabb.end.y)
						max_v.z = maxf(max_v.z, aabb.end.z)
						# Enhance model with PBR automotive paint and material shaders
						if mi.mesh != null:
							for s in range(mi.mesh.get_surface_count()):
								var mat = mi.get_surface_override_material(s)
								if mat == null: mat = mi.mesh.surface_get_material(s)
								var m_name: String = mat.resource_name.to_lower() if mat != null else ""
								if m_name.contains("paint 1") or (key == "kurogane_hyper" and m_name.contains("paint")):
									mi.set_surface_override_material(s, paint)
								elif m_name.contains("glass") or m_name.contains("window"):
									mi.set_surface_override_material(s, CarMaterials.shared("glass"))
								elif m_name.contains("chrome") or m_name.contains("mirror"):
									mi.set_surface_override_material(s, CarMaterials.shared("chrome"))
								elif m_name.contains("trim") or m_name.contains("plastic") or m_name.contains("black") or m_name.contains("paint 2"):
									mi.set_surface_override_material(s, CarMaterials.shared("trim"))
								elif m_name.contains("headlight") or m_name.contains("head"):
									var hl_mat = CarMaterials.shared("headlight").duplicate()
									mi.set_surface_override_material(s, hl_mat)
									headlights.append(mi)
								elif m_name.contains("brakelight") or m_name.contains("tail") or m_name.contains("signallight"):
									var bl_mat = CarMaterials.shared("taillight").duplicate()
									mi.set_surface_override_material(s, bl_mat)
									brake_lights.append(mi)
								elif mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
									# Retain palette texture (windows, grilles, lights, decals) with PBR clearcoat
									var pbr_mat: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
									pbr_mat.roughness = 0.28
									pbr_mat.metallic = 0.2
									pbr_mat.clearcoat_enabled = true
									pbr_mat.clearcoat = 0.85
									pbr_mat.clearcoat_roughness = 0.06
									var p_col: Color = car.get("paint", Color.WHITE)
									pbr_mat.albedo_color = Color(1, 1, 1).lerp(p_col, 0.42)
									mi.set_surface_override_material(s, pbr_mat)
					for c in n.get_children():
						stack.push_back(c)

				var sz := max_v - min_v
				if sz.x > 0.1 and sz.z > 0.1:
					var target_w := he.x * 2.0
					var target_l := he.z * 2.0
					var s_factor := minf(target_w / sz.x, target_l / sz.z)
					model_inst.scale = Vector3(s_factor, s_factor, s_factor)
					var center := (min_v + max_v) * 0.5 * s_factor
					var local_center := (Basis(Vector3.UP, PI if faces_backward else 0.0) * center)
					model_inst.position = Vector3(-local_center.x, -cg + 0.12, -local_center.z)

				# Add full functional GT/Forza details (plates, exhausts, mirrors, lights)
				CarDetails.add(root, b, dims, paint, car)

				var wheel_nodes := []
				for i in range(4):
					var w := CarWheels.make_wheel(i, dims.wheels[i], car)
					root.add_child(w)
					wheel_nodes.append(w)

				root.set_meta("wheels", wheel_nodes)
				root.set_meta("paint", paint)
				if not root.has_meta("brake_lights") or (root.get_meta("brake_lights") as Array).is_empty():
					root.set_meta("brake_lights", brake_lights)
				if not root.has_meta("headlights") or (root.get_meta("headlights") as Array).is_empty():
					root.set_meta("headlights", headlights)
				return root

	var body := CarBody.build_body(b, dims, lod)
	var body_mi := MeshInstance3D.new()
	body_mi.name = "Body"
	body_mi.mesh = body
	for s in range(body.get_surface_count()):
		var role := body.surface_get_name(s)
		body_mi.set_surface_override_material(s, paint if (role == "" or role == "paint") else CarMaterials.shared(role))
	root.add_child(body_mi)

	var cabin := CarBody.build_greenhouse(b, dims, lod)
	if cabin:
		var cab_mi := MeshInstance3D.new()
		cab_mi.name = "Cabin"
		cab_mi.mesh = cabin
		for s in range(cabin.get_surface_count()):
			var role: String = cabin.surface_get_name(s)
			cab_mi.set_surface_override_material(s, paint if role == "paint" else CarMaterials.shared(role if role != "" else "glass"))
		root.add_child(cab_mi)

	CarDetails.add(root, b, dims, paint, car)
	var wheel_nodes := []
	for i in range(4):
		var w := CarWheels.make_wheel(i, dims.wheels[i], car)
		root.add_child(w)
		wheel_nodes.append(w)
	root.set_meta("wheels", wheel_nodes)
	root.set_meta("paint", paint)
	return root

## Brake lights / headlight emissive (called by CarView every physics tick).
static func set_light_state(root: Node3D, braking: bool, lights_on: bool) -> void:
	CarDetails.set_light_state(root, braking, lights_on)

static func wheel_list(data: PackedFloat32Array) -> Array:
	var out := []
	var stride := 16
	for i in range(4):
		var o := i * stride
		out.append({
			"pos": Vector3(data[o], data[o + 1], data[o + 2]),
			"radius": data[o + 5],
			"width": 0.2 if i < 2 else 0.22,
		})
	return out
