class_name CarWheels
extends RefCounted
## Wheel assemblies. Contract: make_wheel() returns a pivot Node3D (positioned/steered by CarView)
## whose FIRST child is the spinning node (rotation.x driven by CarView); brakes attach to the pivot.
## Procedural rims generated via WheelGeo with authentic GT/Forza spoke families and rounded tyre sidewalls.

const WheelDesigns := preload("res://scripts/vehicle/wheel_designs.gd")
const WheelGeo := preload("res://scripts/vehicle/wheel_geo.gd")

static var _wheel_meshes := {}

static func _cyl(radius: float, width: float, segments: int) -> CylinderMesh:
	var key := "%0.3f_%0.3f_%d" % [radius, width, segments]
	if _wheel_meshes.has(key):
		return _wheel_meshes[key]
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = width
	c.radial_segments = segments
	c.rings = 1
	_wheel_meshes[key] = c
	return c

static func _get_design_id(car: Dictionary) -> String:
	var id: String = car.get("wheel_design", "")
	if id != "":
		return id
	var name: String = car.get("name", "")
	match name:
		"Hachi GT": return "watanabe8"
		"Sylph S2": return "forged6"
		"Tatsu IX": return "rally8"
		"Rotora FD": return "split5"
		"Mame K": return "sport5"
		"Kyudo Type-S": return "spoke5"
		_: return "forged6"

static func make_wheel(index: int, w: Dictionary, car: Dictionary) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Wheel%d" % index
	pivot.position = w.pos
	var spin := Node3D.new()
	spin.name = "Spin"
	pivot.add_child(spin)
	var side := -1.0 if index % 2 == 0 else 1.0
	var r: float = w.radius
	var width: float = w.width
	var rot := Vector3(0.0, -side * PI * 0.5, 0.0)

	# Realistic tyre with rounded shoulder and curved sidewall profile.
	var tire := MeshInstance3D.new()
	tire.name = "Tire"
	tire.mesh = WheelGeo.build_tyre(r, width)
	tire.material_override = CarMaterials.shared("tire")
	tire.rotation = rot
	spin.add_child(tire)

	# Procedural rim with spoke geometry, hub, dish, face ring, assembly bolts, and stepped lip.
	var design_id := _get_design_id(car)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var rim_mesh := WheelGeo.build_rim(design_id, r * 0.68, width + 0.012)
	rim.mesh = rim_mesh
	rim.rotation = rot
	# Apply surface materials: surface 0 = spoke face/hub, surface 1 = outer polished barrel/lip.
	if rim_mesh.get_surface_count() > 1:
		rim.set_surface_override_material(0, CarMaterials.shared("rim"))
		rim.set_surface_override_material(1, CarMaterials.shared("chrome"))
	else:
		rim.material_override = CarMaterials.shared("rim")
	spin.add_child(rim)

	# High-detail brake disc + multi-piston caliper (attached to pivot, does not spin).
	var disc := MeshInstance3D.new()
	disc.name = "BrakeDisc"
	disc.mesh = _cyl(r * 0.56, 0.032, 24)
	disc.material_override = CarMaterials.shared("disc")
	disc.rotation = Vector3(0, 0, PI * 0.5)
	disc.position = Vector3(-side * 0.038, 0, 0)
	pivot.add_child(disc)

	var cal := MeshInstance3D.new()
	cal.name = "Caliper"
	var cb := BoxMesh.new()
	cb.size = Vector3(0.055, 0.15, 0.085)
	cal.mesh = cb
	cal.material_override = CarMaterials.shared("caliper")
	cal.position = Vector3(-side * 0.022, r * 0.35, -r * 0.28 if index < 2 else r * 0.28)
	pivot.add_child(cal)

	return pivot
