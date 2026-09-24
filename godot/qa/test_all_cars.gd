extends SceneTree

func _init() -> void:
	print("--- Testing Visual Build for All 12 Cars ---")
	var sim = ClassDB.instantiate("NTSim")
	if sim == null:
		printerr("NTSim native class not found!")
		quit(1)
		return

	var keys: Array = CarData.keys()
	var pass_count := 0
	for key in keys:
		var car_id: int = sim.add_car(key, {}, false, 1)
		var spec: Dictionary = sim.get_car_spec(car_id)
		var wheels: PackedFloat32Array = sim.get_wheel_data(car_id)
		var car_node: Node3D = CarBuilder.build(key, spec, wheels, null, true)
		if car_node == null:
			printerr("FAILED to build car: ", key)
		else:
			var has_wheels = car_node.has_meta("wheels")
			var wheel_count = car_node.get_meta("wheels").size() if has_wheels else 0
			var has_model = car_node.has_node("ModelMesh")
			print("✓ Built car '%s' (ModelMesh: %s, Wheels: %d)" % [key, str(has_model), wheel_count])
			pass_count += 1
			car_node.free()

	print("Summary: %d / %d cars successfully built." % [pass_count, keys.size()])
	if pass_count == keys.size():
		print("ALL CARS PASS!")
		quit(0)
	else:
		quit(1)
