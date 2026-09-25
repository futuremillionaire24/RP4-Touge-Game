extends SceneTree
## Audits the six baked European traffic models (TrafficView.MODEL_KEYS): each must load as a
## mesh with the lite surfaces and real-car proportions, plus its far LOD.
## godot --headless --path . --script res://qa/traffic_model_test.gd

func _init() -> void:
	print("================================================================")
	print("       AUDITING TRAFFIC 3D MODELS (%d VEHICLES)" % TrafficView.MODEL_KEYS.size())
	print("================================================================")
	var ok := true
	for m in range(TrafficView.MODEL_KEYS.size()):
		var key: String = TrafficView.MODEL_KEYS[m]
		var meta := TrafficView._meta(key)
		for suffix in ["", "_lod1"]:
			var mesh := TrafficView._load_mesh("res://assets/cars/%s/%s%s.gltf" % [key, key, suffix], meta, m)
			var aabb := mesh.get_aabb()
			var good := mesh is ArrayMesh and mesh.get_surface_count() > 0 and aabb.size.x > 1.4 and aabb.size.y > 1.2 and aabb.size.z > 3.0
			ok = ok and good
			print("  [%d/%d] %-14s%-6s AABB %s | surfaces %d | %s" % [m + 1, TrafficView.MODEL_KEYS.size(), key, suffix, str(aabb.size), mesh.get_surface_count(), "OK" if good else "FAIL"])
	print("================================================================")
	print("TRAFFIC MODELS: %s" % ("ALL OK" if ok else "FAILURES"))
	quit(0 if ok else 1)
