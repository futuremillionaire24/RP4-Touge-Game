class_name EventData
extends RefCounted
## Festival event catalogue. Routes are world road names chained in order ("~" = reversed).

enum Type { CIRCUIT, SPRINT, TOUGE_BATTLE, WANGAN_DUEL, TIME_ATTACK, DRIFT_ZONE, SPEED_TRAP, SPEED_ZONE, DANGER_SIGN, SHOWCASE }

const TYPE_NAMES := ["Circuit", "Sprint", "Hillclimb Duel", "Highway Duel", "Time Attack", "Drift Zone", "Speed Trap", "Speed Zone", "Danger Sign", "Showcase"]

## One-lap route lengths (m) in the seed-1 world, from tools/event_lengths.gd.
const LENGTHS := {"shuto_c1_night": 8583, "shibuya_gp": 2843, "docks_circuit": 4485, "coast_sprint": 6443,
	"satoyama_sprint": 3327, "route1_sprint": 1425, "akina_downhill": 4364, "akina_uphill": 4364,
	"akina_north": 3026, "wangan_duel": 4857, "akina_time_attack": 4364}

static func _city_loop() -> Array:
	# Four-block loop around central Monte-Carlo, counter-clockwise from the west avenue.
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
		{"id": "shuto_c1_night", "name": "Autoroute A8 Midnight Run", "type": Type.CIRCUIT, "roads": ["shuto_loop"], "closed": true, "laps": 2,
			"rivals": 7, "class_max": 4, "time": 23.5, "weather": 0, "credits": 48000, "xp": 2200, "level": 3, "district": "A8 Autoroute"},
		{"id": "shibuya_gp", "name": "Monaco Street GP", "type": Type.CIRCUIT, "roads": _city_loop(), "closed": true, "laps": 3,
			"rivals": 7, "class_max": 3, "time": 21.0, "weather": 3, "credits": 26000, "xp": 1300, "level": 1, "district": "Monte-Carlo"},
		{"id": "docks_circuit", "name": "Port Hercule Harbour Circuit", "type": Type.CIRCUIT, "roads": _docks_loop(), "closed": true, "laps": 3,
			"rivals": 5, "class_max": 2, "time": 16.0, "weather": 0, "credits": 24000, "xp": 1200, "level": 0, "district": "Port Hercule"},
		{"id": "coast_sprint", "name": "Cap d'Ail Coast Sprint", "type": Type.SPRINT, "roads": ["coast_road"], "closed": false,
			"rivals": 7, "class_max": 4, "time": 17.5, "weather": 0, "credits": 22000, "xp": 1100, "level": 2, "district": "Cap d'Ail"},
		{"id": "satoyama_sprint", "name": "La Turbie Alpine Dash", "type": Type.SPRINT, "roads": ["rural_main"], "closed": false,
			"rivals": 5, "class_max": 2, "time": 7.5, "weather": 6, "credits": 11000, "xp": 550, "level": 0, "district": "La Turbie"},
		{"id": "route1_sprint", "name": "Basse Corniche Sprint", "type": Type.SPRINT, "roads": ["~route1"], "closed": false,
			"rivals": 5, "class_max": 3, "time": 12.0, "weather": 2, "credits": 5000, "xp": 250, "level": 0, "district": "Corniche Coast"},
		# ---- Rival Boss Battles (6 Rivals) ----
		{"id": "shibuya_duel_mika", "name": "Monte-Carlo Street Duel", "type": Type.TOUGE_BATTLE, "roads": _city_loop(), "closed": true, "laps": 2,
			"rivals": 1, "class_max": 3, "time": 22.0, "weather": 3, "credits": 20000, "xp": 1000, "level": 1, "district": "Monte-Carlo", "rival": "mika"},
		{"id": "akina_downhill", "name": "Grande Corniche Downhill", "type": Type.TOUGE_BATTLE, "roads": ["~touge_ascent"], "closed": false,
			"rivals": 1, "class_max": 3, "time": 2.0, "weather": 0, "credits": 28000, "xp": 1500, "level": 2, "district": "Grande Corniche", "rival": "takumi"},
		{"id": "docks_duel_goro", "name": "Port Hercule Duel", "type": Type.TOUGE_BATTLE, "roads": _docks_loop(), "closed": true, "laps": 2,
			"rivals": 1, "class_max": 3, "time": 18.0, "weather": 0, "credits": 24000, "xp": 1200, "level": 3, "district": "Port Hercule", "rival": "goro"},
		{"id": "akina_uphill", "name": "Grande Corniche Hillclimb", "type": Type.TOUGE_BATTLE, "roads": ["touge_ascent"], "closed": false,
			"rivals": 1, "class_max": 4, "time": 5.0, "weather": 6, "credits": 30000, "xp": 1600, "level": 4, "district": "Grande Corniche", "rival": "keisuke"},
		{"id": "satoyama_duel_yuna", "name": "La Turbie Ridge Duel", "type": Type.TOUGE_BATTLE, "roads": ["rural_main"], "closed": false,
			"rivals": 1, "class_max": 4, "time": 6.5, "weather": 4, "credits": 34000, "xp": 1700, "level": 5, "district": "La Turbie", "rival": "yuna"},
		{"id": "wangan_duel", "name": "A8 High-Speed Autoroute Duel", "type": Type.WANGAN_DUEL, "roads": ["wangan_spur"], "closed": false,
			"rivals": 1, "class_max": 6, "time": 1.5, "weather": 0, "credits": 45000, "xp": 2000, "level": 5, "district": "A8 Autoroute", "rival": "blackbird"},
		# ---- Euro GT Festival Grand Prix (Championship Finale) ----
		{"id": "touge_crown_championship", "name": "Euro GT Festival Grand Prix", "type": Type.SHOWCASE, "roads": ["shuto_loop"], "closed": true, "laps": 3,
			"rivals": 1, "class_max": 6, "time": 0.0, "weather": 0, "credits": 100000, "xp": 5000, "level": 6, "district": "Monaco & Riviera", "rival": "champion", "reward_car": "kurogane_hyper"},
		# ---- Time Attack & Other Runs ----
		{"id": "akina_north", "name": "Col de la Madone Descent", "type": Type.SPRINT, "roads": ["touge_descent"], "closed": false,
			"rivals": 3, "class_max": 4, "time": 18.0, "weather": 3, "credits": 14000, "xp": 700, "level": 3, "district": "Grande Corniche"},
		{"id": "akina_time_attack", "name": "Grande Corniche Time Attack", "type": Type.TIME_ATTACK, "roads": ["touge_ascent"], "closed": false,
			"rivals": 0, "class_max": 6, "time": 15.0, "weather": 0, "credits": 15000, "xp": 800, "level": 1, "district": "Grande Corniche"},
		# ---- Dedicated Police Outrun Events ----
		{"id": "shuto_police_outrun", "name": "Autoroute Police Pursuit", "type": Type.SPRINT, "roads": ["shuto_loop"], "closed": false,
			"rivals": 0, "class_max": 6, "time": 23.0, "weather": 0, "credits": 38000, "xp": 1900, "level": 3, "district": "A8 Autoroute", "police_heat": 3},
		{"id": "akina_police_outrun", "name": "Corniche Outrun", "type": Type.SPRINT, "roads": ["~touge_ascent"], "closed": false,
			"rivals": 0, "class_max": 5, "time": 2.0, "weather": 3, "credits": 32000, "xp": 1600, "level": 2, "district": "Grande Corniche", "police_heat": 2},
	]

static func get_event(id: String) -> Dictionary:
	for e in all():
		if e.id == id:
			return e
	return {}
