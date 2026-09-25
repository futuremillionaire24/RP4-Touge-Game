extends SceneTree
## Diagnostic: counts world props per type in the chunks around a map position (default Port
## Hercule). godot --headless --path . --script res://tools/prop_census.gd -- [x=..] [z=..] [r=chunks]

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var world := NTWorld.new()
	MapData.build(world)
	var at := Vector3(float(args.get("x", "0")), 0, float(args.get("z", "0")))
	if not args.has("x"):
		for p in world.pois():
			if p.id == "festival":
				at = p.position
	var c: Vector2i = world.chunk_of(at)
	var r := int(args.get("r", "2"))
	var counts := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d: Dictionary = world.build_chunk(c.x + dx, c.y + dz, 0, false, true, 1.0)
			var props: Dictionary = d.get("props", {})
			for t in props.keys():
				var name: String = PropLibrary.Type.keys()[int(t)]
				counts[name] = int(counts.get(name, 0)) + (props[t] as PackedFloat32Array).size() / 8
	print("props around ", at, " (", (2 * r + 1) * (2 * r + 1), " chunks): ", counts)
	quit(0)
