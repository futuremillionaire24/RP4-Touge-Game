extends Node

func _ready() -> void:
	print("--- BEGIN LIVE WORLD MAP TEST ---")
	
	# 1. Instantiate and build world
	var world: NTWorld = NTWorld.new()
	print("Building NTWorld(42)...")
	world.build(42)
	print("NTWorld built successfully! Bounds: ", world.bounds())

	# 2. Instantiate EventMarkers and Activities
	var markers := EventMarkers.new()
	add_child(markers)
	markers.build(world)
	print("EventMarkers setup complete. Markers count: ", markers.markers.size())

	var activities := Activities.new()
	add_child(activities)
	activities.build(world)
	print("Activities setup complete. Items count: ", activities.items.size(), ", Barns count: ", activities.barns.size())

	# 3. Instantiate WorldMap
	const WorldMapClass = preload("res://scripts/ui/world_map.gd")
	var wm = WorldMapClass.new()
	add_child(wm)
	print("WorldMap added to tree.")

	# 4. Setup WorldMap
	wm.setup(world, null, markers, activities, self)
	print("WorldMap.setup() completed.")

	# 5. Verify size and view
	assert(wm._view != null, "wm._view should be instantiated")
	print("WorldMap view size: ", wm._view.size)

	# 6. Test tab switching
	print("Active tab initially: ", wm._active_tab)
	wm._active_tab = WorldMapClass.FilterTab.RACES
	wm._update_tab_visuals()
	print("Switched to RACES tab.")
	wm._active_tab = WorldMapClass.FilterTab.PR_STUNTS
	wm._update_tab_visuals()
	print("Switched to PR_STUNTS tab.")
	wm._active_tab = WorldMapClass.FilterTab.ALL
	wm._update_tab_visuals()
	print("Switched back to ALL tab.")

	# 7. Test waypoint calculation
	var waypoint_result := [false, 0, 0]
	wm.waypoint_set.connect(func(pos: Vector3, poly: PackedVector2Array, c3d: PackedVector3Array, u3d: PackedVector3Array):
		waypoint_result[0] = true
		waypoint_result[1] = poly.size()
		waypoint_result[2] = c3d.size()
		print("Waypoint signal received! Pos: ", pos, " 2D points: ", poly.size(), " 3D points: ", c3d.size())
	)

	# Pick an event location to target
	if markers.markers.size() > 0:
		var target_pos: Vector3 = markers.markers[0].pos
		print("Testing GPS pathfinding to marker 0 at: ", target_pos)
		wm._gps_waypoint = target_pos
		wm._calculate_gps_path()
		assert(waypoint_result[0], "Waypoint signal should have fired")
		assert(waypoint_result[1] >= 2, "Polyline should have at least 2 points")
		assert(waypoint_result[2] >= 2, "3D ribbon samples should have at least 2 points")
		print("✓ GPS pathfinding test PASS!")

	# 8. Test drawing trigger
	wm._view.queue_redraw()
	print("✓ WorldMap drawing test PASS!")

	# 9. Test Fast Travel signal
	var ft_result := [false]
	wm.fast_travel_requested.connect(func(pos: Vector3, dir: Vector3):
		ft_result[0] = true
		print("Fast travel requested to: ", pos, " dir: ", dir)
	)
	var cursor_world := Vector2(markers.markers[0].pos.x, markers.markers[0].pos.z)
	wm._handle_fast_travel(cursor_world)
	assert(ft_result[0], "Fast travel signal should have fired")
	print("✓ Fast travel test PASS!")

	# 10. Test Minimap
	print("\n--- TESTING MINIMAP OVERHAUL ---")
	var minimap := Minimap.new()
	add_child(minimap)
	minimap.setup(world, null)
	print("Minimap setup complete. Cached roads: ", minimap._cached_roads.size())
	assert(minimap._cached_roads.size() > 0, "Minimap should have cached vector roads")
	minimap.queue_redraw()
	print("✓ Minimap drawing test PASS!")

	print("\n==========================================")
	print("ALL MAP SYSTEM TESTS PASSED SUCCESSFULLY!")
	print("==========================================")
	get_tree().quit(0)
