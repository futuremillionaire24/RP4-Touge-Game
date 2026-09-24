class_name EventData
extends RefCounted
## Festival event catalogue. Routes are world road names chained in order ("~" = reversed).

enum Type { CIRCUIT, SPRINT, TOUGE_BATTLE, WANGAN_DUEL, TIME_ATTACK, DRIFT_ZONE, SPEED_TRAP, SPEED_ZONE, DANGER_SIGN, SHOWCASE }

const TYPE_NAMES := ["Circuit", "Sprint", "Touge Battle", "Wangan Duel", "Time Attack", "Drift Zone", "Speed Trap", "Speed Zone", "Danger Sign", "Showcase"]

## One-lap route lengths (m) in the seed-1 world, from tools/event_lengths.gd.
const LENGTHS := {"shuto_c1_night": 8583, "shibuya_gp": 2843, "docks_circuit": 4485, "coast_sprint": 6443,
	"satoyama_sprint": 3327, "route1_sprint": 1425, "akina_downhill": 4364, "akina_uphill": 4364,
	"akina_north": 3026, "wangan_duel": 4857, "akina_time_attack": 4364}

static func _city_loop() -> Array:
	# Four-block loop around central Shibuya, counter-clockwise from the west avenue.
	var r := []
	for j in range(2, 6):
		r.append("city_ns_2_%d" % j)
	for i in range(2, 6):
		r.append("city_ew_6_%d" % i)
	for j in range(5, 1, -1):
		r.append("~city_ns_6_%d" % j)
	for i in range(5, 1, -1):
		r.append("~city_ew_2_%d" % i)
	return r

static func _docks_loop() -> Array:
	return ["dock_ns_0_0", "dock_ns_0_1", "dock_ew_2_0", "dock_ew_2_1", "dock_ew_2_2", "~dock_ns_3_1", "~dock_ns_3_0", "~dock_ew_0_2", "~dock_ew_0_1", "~dock_ew_0_0"]

static func all() -> Array:
	return [
		{"id": "shuto_c1_night", "name": "Shuto C1 Midnight", "type": Type.CIRCUIT, "roads": ["shuto_loop"], "closed": true, "laps": 2,
			"rivals": 7, "class_max": 4, "time": 23.5, "weather": 0, "credits": 48000, "xp": 2200, "level": 3, "district": "Shuto Expressway"},
		{"id": "shibuya_gp", "name": "Shibuya Street GP", "type": Type.CIRCUIT, "roads": _city_loop(), "closed": true, "laps": 3,
			"rivals": 7, "class_max": 3, "time": 21.0, "weather": 3, "credits": 26000, "xp": 1300, "level": 1, "district": "Neon Shibuya"},
		{"id": "docks_circuit", "name": "Container Canyon", "type": Type.CIRCUIT, "roads": _docks_loop(), "closed": true, "laps": 3,
			"rivals": 5, "class_max": 2, "time": 16.0, "weather": 0, "credits": 24000, "xp": 1200, "level": 0, "district": "Bayshore Docks"},
		{"id": "coast_sprint", "name": "Coastline Sprint", "type": Type.SPRINT, "roads": ["coast_road"], "closed": false,
			"rivals": 7, "class_max": 4, "time": 17.5, "weather": 0, "credits": 22000, "xp": 1100, "level": 2, "district": "Coastal Road"},
		{"id": "satoyama_sprint", "name": "Satoyama Morning Run", "type": Type.SPRINT, "roads": ["rural_main"], "closed": false,
			"rivals": 5, "class_max": 2, "time": 7.5, "weather": 6, "credits": 11000, "xp": 550, "level": 0, "district": "Satoyama"},
		{"id": "route1_sprint", "name": "Route 1 Dash", "type": Type.SPRINT, "roads": ["~route1"], "closed": false,
			"rivals": 5, "class_max": 3, "time": 12.0, "weather": 2, "credits": 5000, "xp": 250, "level": 0, "district": "Coastal Road"},
		# ---- Rival Boss Battles (6 Rivals) ----
		{"id": "shibuya_duel_mika", "name": "Shibuya Neon Duel", "type": Type.TOUGE_BATTLE, "roads": _city_loop(), "closed": true, "laps": 2,
			"rivals": 1, "class_max": 3, "time": 22.0, "weather": 3, "credits": 20000, "xp": 1000, "level": 1, "district": "Neon Shibuya", "rival": "mika"},
		{"id": "akina_downhill", "name": "Akina Downhill Battle", "type": Type.TOUGE_BATTLE, "roads": ["~touge_ascent"], "closed": false,
			"rivals": 1, "class_max": 3, "time": 2.0, "weather": 0, "credits": 28000, "xp": 1500, "level": 2, "district": "Mt. Akina Touge", "rival": "takumi"},
		{"id": "docks_duel_goro", "name": "Docks Heavy Battle", "type": Type.TOUGE_BATTLE, "roads": _docks_loop(), "closed": true, "laps": 2,
			"rivals": 1, "class_max": 3, "time": 18.0, "weather": 0, "credits": 24000, "xp": 1200, "level": 3, "district": "Bayshore Docks", "rival": "goro"},
		{"id": "akina_uphill", "name": "Akina Uphill Attack", "type": Type.TOUGE_BATTLE, "roads": ["touge_ascent"], "closed": false,
			"rivals": 1, "class_max": 4, "time": 5.0, "weather": 6, "credits": 30000, "xp": 1600, "level": 4, "district": "Mt. Akina Touge", "rival": "keisuke"},
		{"id": "satoyama_duel_yuna", "name": "Satoyama Rally Duel", "type": Type.TOUGE_BATTLE, "roads": ["rural_main"], "closed": false,
			"rivals": 1, "class_max": 4, "time": 6.5, "weather": 4, "credits": 34000, "xp": 1700, "level": 5, "district": "Satoyama", "rival": "yuna"},
		{"id": "wangan_duel", "name": "Bayshore Wangan Duel", "type": Type.WANGAN_DUEL, "roads": ["wangan_spur"], "closed": false,
			"rivals": 1, "class_max": 6, "time": 1.5, "weather": 0, "credits": 45000, "xp": 2000, "level": 5, "district": "Shuto Expressway", "rival": "blackbird"},
		# ---- Touge Crown Grand Prix (Championship Finale) ----
		{"id": "touge_crown_championship", "name": "Touge Crown Grand Prix", "type": Type.SHOWCASE, "roads": ["shuto_loop"], "closed": true, "laps": 3,
			"rivals": 1, "class_max": 6, "time": 0.0, "weather": 0, "credits": 100000, "xp": 5000, "level": 6, "district": "Shuto Expressway", "rival": "champion", "reward_car": "kurogane_hyper"},
		# ---- Time Attack & Other Runs ----
		{"id": "akina_north", "name": "North Face Descent", "type": Type.SPRINT, "roads": ["touge_descent"], "closed": false,
			"rivals": 3, "class_max": 4, "time": 18.0, "weather": 3, "credits": 14000, "xp": 700, "level": 3, "district": "Mt. Akina Touge"},
		{"id": "akina_time_attack", "name": "Akina Time Attack", "type": Type.TIME_ATTACK, "roads": ["touge_ascent"], "closed": false,
			"rivals": 0, "class_max": 6, "time": 15.0, "weather": 0, "credits": 15000, "xp": 800, "level": 1, "district": "Mt. Akina Touge"},
		# ---- Dedicated Police Outrun Events ----
		{"id": "shuto_police_outrun", "name": "Shuto Midnight Outrun", "type": Type.SPRINT, "roads": ["shuto_loop"], "closed": false,
			"rivals": 0, "class_max": 6, "time": 23.0, "weather": 0, "credits": 38000, "xp": 1900, "level": 3, "district": "Shuto Expressway", "police_heat": 3},
		{"id": "akina_police_outrun", "name": "Akina Downhill Outrun", "type": Type.SPRINT, "roads": ["~touge_ascent"], "closed": false,
			"rivals": 0, "class_max": 5, "time": 2.0, "weather": 3, "credits": 32000, "xp": 1600, "level": 2, "district": "Mt. Akina Touge", "police_heat": 2},
	]

static func get_event(id: String) -> Dictionary:
	for e in all():
		if e.id == id:
			return e
	return {}
