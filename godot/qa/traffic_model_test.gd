extends SceneTree

func _init() -> void:
	print("================================================================")
	print("       AUDITING TRAFFIC 3D MODELS (6/6 VEHICLE CLASSES)        ")
	print("================================================================")
	var names := ["Kei Car", "Sedan", "Tokyo Taxi", "Delivery Van", "Box Truck", "Transit Bus"]
	for m in range(TrafficView.MODELS):
		var mesh: Mesh = TrafficView._build_model(m)
		assert(mesh != null, "Mesh for traffic vehicle %d (%s) must not be null!" % [m, names[m]])
		var sc := mesh.get_surface_count()
		assert(sc > 0, "Mesh %s has 0 surfaces!" % names[m])
		var aabb := mesh.get_aabb()
		var mat = mesh.surface_get_material(0)
		print("  [%d/6] %-14s: AABB = %s | Surfaces = %d | HasMat = %s" % [
			m + 1, names[m], str(aabb.size), sc, str(mat != null)
		])
		assert(aabb.size.x > 0.5 and aabb.size.y > 0.5 and aabb.size.z > 0.5, "Traffic model %s is degenerate!" % names[m])
	print("================================================================")
	print("       ALL 6 TRAFFIC 3D MODELS SUCCESSFULLY AUDITED & VERIFIED! ")
	print("================================================================")
	quit(0)
