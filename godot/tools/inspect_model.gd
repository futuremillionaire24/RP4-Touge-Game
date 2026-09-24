extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://assets/models/cars/car_concept.glb"
	if args.size() > 0:
		path = args[0]

	print("=== INSPECTING MODEL: %s ===" % path)
	var scene: PackedScene = load(path)
	if scene == null:
		printerr("Failed to load scene from: ", path)
		quit(1)
		return

	var inst: Node = scene.instantiate()
	if inst == null:
		printerr("Failed to instantiate scene from: ", path)
		quit(1)
		return

	var total_tris := 0
	var total_verts := 0
	var mesh_count := 0
	var nodes_count := 0
	var min_bound := Vector3(INF, INF, INF)
	var max_bound := Vector3(-INF, -INF, -INF)

	var stack: Array[Node] = [inst]
	while stack.size() > 0:
		var curr: Node = stack.pop_back()
		nodes_count += 1
		if curr is MeshInstance3D:
			mesh_count += 1
			var mi: MeshInstance3D = curr
			var m: Mesh = mi.mesh
			if m != null:
				for s in range(m.get_surface_count()):
					var arrays := m.surface_get_arrays(s)
					if arrays.size() > Mesh.ARRAY_VERTEX:
						var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
						total_verts += verts.size()
					if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
						var idxs: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
						total_tris += idxs.size() / 3
				var aabb := mi.get_aabb()
				min_bound.x = minf(min_bound.x, aabb.position.x)
				min_bound.y = minf(min_bound.y, aabb.position.y)
				min_bound.z = minf(min_bound.z, aabb.position.z)
				max_bound.x = maxf(max_bound.x, aabb.end.x)
				max_bound.y = maxf(max_bound.y, aabb.end.y)
				max_bound.z = maxf(max_bound.z, aabb.end.z)
				print("   [Mesh] '%s' (Surfaces: %d, Parent: '%s')" % [mi.name, m.get_surface_count(), mi.get_parent().name])
		for child in curr.get_children():
			stack.push_back(child)

	var size := max_bound - min_bound
	print("\n--- Model Summary ---")
	print("Nodes count:     %d" % nodes_count)
	print("Meshes count:    %d" % mesh_count)
	print("Total vertices:  %d" % total_verts)
	print("Total triangles: %d" % total_tris)
	print("Dimensions (XYZ): %.2fm x %.2fm x %.2fm" % [size.x, size.y, size.z])
	print("Bounding Box:    min: %s, max: %s" % [min_bound, max_bound])
	print("=== INSPECTION COMPLETE ===")
	inst.free()
	quit(0)
