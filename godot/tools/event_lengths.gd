extends SceneTree
## Prints each event route's length (m, one lap) in the seed-1 world, formatted for
## EventData.LENGTHS. Usage: godot --headless --path . --script res://tools/event_lengths.gd

func _init() -> void:
	var world := NTWorld.new()
	MapData.build(world)
	var out := []
	for ev in EventData.all():
		var route := Route.from_roads(world, ev.roads, ev.closed)
		var total := 0.0
		for i in range(1, route.centers.size()):
			total += route.centers[i].distance_to(route.centers[i - 1])
		if ev.closed and route.centers.size() > 1:
			total += route.centers[0].distance_to(route.centers[route.centers.size() - 1])
		out.append("\"%s\": %d" % [ev.id, roundi(total)])
	print("LENGTHS := {", ", ".join(out), "}")
	quit()
