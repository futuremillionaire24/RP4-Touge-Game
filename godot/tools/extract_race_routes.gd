extends SceneTree

func _init() -> void:
	print("--- EXTRACTING RACE ROUTE MAPS ---")
	var world: NTWorld = NTWorld.new()
	MapData.build(world)
	print("NTWorld built successfully.")

	var all_events := EventData.all()
	var routes_data := {}

	for ev in all_events:
		var ev_id: String = ev.id
		var route := Route.from_roads(world, ev.roads, ev.get("closed", false))
		if route.centers.size() < 2:
			print("Warning: route for ", ev_id, " has fewer than 2 points")
			continue
		
		var raw_pts := route.centers
		var n := raw_pts.size()
		
		# Downsample to ~80-120 smooth points for instant lightweight vector rendering
		var step := maxi(1, int(n / 100))
		var sampled_2d: Array = []
		var elevations: Array = []
		var min_y := 99999.0
		var max_y := -99999.0
		var min_x := 99999.0
		var max_x := -99999.0
		var min_z := 99999.0
		var max_z := -99999.0

		for i in range(0, n, step):
			var p: Vector3 = raw_pts[i]
			sampled_2d.append([snappedf(p.x, 0.1), snappedf(p.z, 0.1)])
			elevations.append(snappedf(p.y, 0.1))
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_z = minf(min_z, p.z)
			max_z = maxf(max_z, p.z)
		
		# Always ensure the last point is included
		var last_p: Vector3 = raw_pts[n - 1]
		if sampled_2d.is_empty() or Vector2(sampled_2d.back()[0], sampled_2d.back()[1]).distance_to(Vector2(last_p.x, last_p.z)) > 2.0:
			sampled_2d.append([snappedf(last_p.x, 0.1), snappedf(last_p.z, 0.1)])
			elevations.append(snappedf(last_p.y, 0.1))
		
		# Detect significant turns & hairpins
		var turns: Array = []
		var t_n := sampled_2d.size()
		for i in range(1, t_n - 1):
			var p0 = Vector2(sampled_2d[i-1][0], sampled_2d[i-1][1])
			var p1 = Vector2(sampled_2d[i][0], sampled_2d[i][1])
			var p2 = Vector2(sampled_2d[i+1][0], sampled_2d[i+1][1])
			var v1 := (p1 - p0).normalized()
			var v2 := (p2 - p1).normalized()
			var dot := clampf(v1.dot(v2), -1.0, 1.0)
			var angle_deg := rad_to_deg(acos(dot))
			if angle_deg > 28.0:
				turns.append({
					"idx": i,
					"pos": [snappedf(p1.x, 0.1), snappedf(p1.y, 0.1)],
					"angle": roundi(angle_deg),
					"hairpin": angle_deg > 65.0
				})
		
		routes_data[ev_id] = {
			"id": ev_id,
			"name": ev.name,
			"district": ev.district,
			"closed": ev.get("closed", false),
			"length_m": roundi(route.length),
			"elev_min": roundi(min_y),
			"elev_max": roundi(max_y),
			"elev_gain": roundi(max_y - min_y),
			"bbox": [roundi(min_x), roundi(min_z), roundi(max_x - min_x), roundi(max_z - min_z)],
			"points": sampled_2d,
			"elevations": elevations,
			"turns_count": turns.size(),
			"turns": turns
		}
		print("Extracted route: ", ev_id, " (", sampled_2d.size(), " pts, ", turns.size(), " turns, ", roundi(route.length), "m, elev gain: ", roundi(max_y - min_y), "m)")

	# Write out to GDScript constant file for instantaneous zero-overhead loading
	var script_content := "class_name RaceRoutes\nextends RefCounted\n## Auto-generated vectorized race route maps and telemetry.\n\nconst ROUTES := %s\n\nstatic func get_route(id: String) -> Dictionary:\n\treturn ROUTES.get(id, {})\n" % JSON.stringify(routes_data, "\t")
	
	var file := FileAccess.open("res://scripts/data/race_routes.gd", FileAccess.WRITE)
	if file:
		file.store_string(script_content)
		file.close()
		print("Successfully wrote res://scripts/data/race_routes.gd!")
	else:
		printerr("Failed to open file for writing!")
	
	quit(0)
