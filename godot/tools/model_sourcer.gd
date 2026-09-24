extends SceneTree
## Model Sourcer Engine Tool: Inspects, validates, extracts, and packages 3D car models for Godot.
## Usage:
##   godot --headless -s res://tools/model_sourcer.gd -- inspect <path>
##   godot --headless -s res://tools/model_sourcer.gd -- extract <pack_path> <node_name> <out_tscn>
##   godot --headless -s res://tools/model_sourcer.gd -- list <pack_path>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_print_help()
		quit(0)
		return

	var cmd: String = args[0]
	match cmd:
		"inspect":
			if args.size() < 2:
				printerr("Error: Missing model path. Usage: inspect <path>")
				quit(1)
				return
			_inspect(args[1])
		"list":
			if args.size() < 2:
				printerr("Error: Missing pack path. Usage: list <pack_path>")
				quit(1)
				return
			_list_pack(args[1])
		"extract":
			if args.size() < 4:
				printerr("Error: Missing arguments. Usage: extract <pack_path> <node_name> <out_tscn>")
				quit(1)
				return
			_extract_car(args[1], args[2], args[3])
		_:
			printerr("Unknown command: ", cmd)
			_print_help()
			quit(1)

func _print_help() -> void:
	print("=== MODEL SOURCER CLI (Godot Engine Tool) ===")
	print("Commands:")
	print("  inspect <path>                     - Inspect model node tree, tri counts, and bounds")
	print("  list <pack_path>                   - List all vehicle sub-nodes in a multi-model pack")
	print("  extract <pack> <node_name> <out>   - Extract a vehicle sub-node into an independent .tscn")

func _inspect(path: String) -> void:
	print("--- Inspecting: %s ---" % path)
	var scene: PackedScene = load(path)
	if scene == null:
		printerr("Failed to load scene: ", path)
		quit(1)
		return
	var inst: Node = scene.instantiate()
	var total_tris := 0
	var total_verts := 0
	var meshes := 0
	var min_b := Vector3(INF, INF, INF)
	var max_b := Vector3(-INF, -INF, -INF)

	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			meshes += 1
			var mi: MeshInstance3D = n
			var m: Mesh = mi.mesh
			if m != null:
				for s in range(m.get_surface_count()):
					var arr := m.surface_get_arrays(s)
					if arr.size() > Mesh.ARRAY_VERTEX:
						total_verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
					if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
						total_tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				var aabb := mi.get_aabb()
				min_b.x = minf(min_b.x, aabb.position.x)
				min_b.y = minf(min_b.y, aabb.position.y)
				min_b.z = minf(min_b.z, aabb.position.z)
				max_b.x = maxf(max_b.x, aabb.end.x)
				max_b.y = maxf(max_b.y, aabb.end.y)
				max_b.z = maxf(max_b.z, aabb.end.z)
		for c in n.get_children():
			stack.push_back(c)

	var sz := max_b - min_b
	print("Meshes: %d | Vertices: %d | Triangles: %d" % [meshes, total_verts, total_tris])
	print("Dimensions: %.2f m x %.2f m x %.2f m" % [sz.x, sz.y, sz.z])
	if total_tris <= 40000:
		print("Status: [PASS] Model is within mobile budget (<= 40,000 tris).")
	else:
		print("Status: [WARNING] Model exceeds mobile budget (%.1f k tris)." % (total_tris / 1000.0))
	inst.free()
	quit(0)

func _list_pack(path: String) -> void:
	print("--- Listing vehicles in pack: %s ---" % path)
	var scene: PackedScene = load(path)
	if scene == null:
		printerr("Failed to load pack: ", path)
		quit(1)
		return
	var inst: Node = scene.instantiate()
	for c in inst.get_children():
		var child_meshes := 0
		var stack: Array[Node] = [c]
		while not stack.is_empty():
			var curr: Node = stack.pop_back()
			if curr is MeshInstance3D:
				child_meshes += 1
			for sub in curr.get_children():
				stack.push_back(sub)
		print("  • %s (Child meshes: %d)" % [c.name, child_meshes])
	inst.free()
	quit(0)

func _extract_car(pack_path: String, car_name: String, out_tscn: String) -> void:
	print("--- Extracting '%s' from '%s' to '%s' ---" % [car_name, pack_path, out_tscn])
	var scene: PackedScene = load(pack_path)
	if scene == null:
		printerr("Failed to load pack: ", pack_path)
		quit(1)
		return
	var root: Node = scene.instantiate()
	var target: Node = root.find_child(car_name, true, false)
	if target == null:
		printerr("Car node '%s' not found in pack." % car_name)
		root.free()
		quit(1)
		return

	# Duplicate target into a clean standalone root Node3D
	var new_root := Node3D.new()
	new_root.name = car_name
	var clone := target.duplicate(Node.DUPLICATE_USE_INSTANTIATION)
	clone.position = Vector3.ZERO
	clone.rotation = Vector3.ZERO
	clone.scale = Vector3.ONE
	new_root.add_child(clone)
	clone.owner = new_root

	# Recursively set owner for all children so PackedScene serializes them
	var stack: Array[Node] = [clone]
	while not stack.is_empty():
		var curr: Node = stack.pop_back()
		curr.owner = new_root
		for c in curr.get_children():
			stack.push_back(c)

	var packed := PackedScene.new()
	var err := packed.pack(new_root)
	if err != OK:
		printerr("Failed to pack scene: ", err)
		new_root.free()
		root.free()
		quit(1)
		return

	err = ResourceSaver.save(packed, out_tscn)
	if err != OK:
		printerr("Failed to save extracted scene to: ", out_tscn, " (Error: %d)" % err)
		new_root.free()
		root.free()
		quit(1)
		return

	print("✓ Successfully extracted '%s' to %s" % [car_name, out_tscn])
	new_root.free()
	root.free()
	quit(0)
