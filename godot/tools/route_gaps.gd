extends SceneTree
## Diagnostic: for each event route, report junction gaps between chained roads (> 15 m) and
## roads whose driving direction looks reversed (their start is far from the previous end).
## godot --headless --path . --script res://tools/route_gaps.gd

func _init() -> void:
	var world := NTWorld.new()
	MapData.build(world)
	for ev in EventData.all():
		var last := Vector3.INF
		var bad := []
		for entry in ev.roads:
			var name: String = entry
			var rev := name.begins_with("~")
			var rs := world.road_samples(name.substr(1) if rev else name)
			if rs.is_empty():
				bad.append("missing %s" % name)
				continue
			var c: PackedVector3Array = rs.centers
			var first: Vector3 = c[c.size() - 1] if rev else c[0]
			var end: Vector3 = c[0] if rev else c[c.size() - 1]
			if last != Vector3.INF and last.distance_to(first) > 15.0:
				bad.append("%s gap %.0f m (other end %.0f m)" % [name, last.distance_to(first), last.distance_to(end)])
			last = end
		print("%s: %d roads, %d issues %s" % [ev.id, ev.roads.size(), bad.size(), str(bad.slice(0, 6))])
	quit(0)
