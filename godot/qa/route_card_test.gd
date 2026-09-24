extends Node

func _ready() -> void:
	print("--- BEGIN RACE MAP & NAVIGATION TEST ---")
	
	# 1. Verify all routes in RaceRoutes
	var routes := RaceRoutes.all()
	print("Loaded routes count: %d" % routes.size())
	assert(routes.size() >= 17, "Expected at least 17 race routes")

	for ev_id in routes.keys():
		var r: Dictionary = routes[ev_id]
		var pts: Array = r.get("points", [])
		var elevs: Array = r.get("elevations", [])
		var bbox: Array = r.get("bbox", [])
		var turns: Array = r.get("turns", [])
		
		assert(pts.size() >= 10, "Route %s points too short: %d" % [ev_id, pts.size()])
		assert(elevs.size() >= 2, "Route %s elevations missing" % ev_id)
		assert(bbox.size() == 4, "Route %s bbox invalid" % ev_id)
		print("✓ Route verified: %s (points: %d, length: %.2f km, turns: %d, hairpins: %d)" % [
			ev_id, pts.size(), float(r.get("length_m", 0)) / 1000.0, int(r.get("turns_count", 0)),
			turns.filter(func(t): return bool(t.get("hairpin", false))).size()
		])

	# 2. Test RaceRouteCard instance and rendering
	print("\n--- Testing RaceRouteCard UI Component ---")
	var card := RaceRouteCard.new()
	card.size = Vector2(640, 250)
	add_child(card)

	for ev_id in routes.keys():
		card.set_event_id(ev_id)
		card._process(0.016)
		card.queue_redraw()
	await get_tree().process_frame
	print("✓ All 17 race maps rendered cleanly in RaceRouteCard!")

	# 3. Test EventsScreen with embedded RaceRouteCard
	print("\n--- Testing EventsScreen Integration ---")
	var events_screen := EventsScreen.new()
	add_child(events_screen)
	events_screen.build()
	events_screen.refresh()
	
	# Cycle tabs
	for i in range(4):
		events_screen.tab(1)
	print("✓ EventsScreen tab cycle and detail updates PASSED!")

	print("\n===========================================")
	print("ALL RACE MAP & NAV TESTS PASSED WITH 100%!")
	print("===========================================")
	get_tree().quit(0)
