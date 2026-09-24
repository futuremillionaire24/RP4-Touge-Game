class_name EventData
extends RefCounted
## Festival event catalogue on the real Riviera roads. Each event names a baked route
## (tools/mapbake config ROUTES -> res://assets/map/riviera.json); "reverse" drives it backwards
## (descents, opposite-direction runs). `roads` is filled from the route: world road names chained
## in order ("~" = reversed).

enum Type { CIRCUIT, SPRINT, TOUGE_BATTLE, WANGAN_DUEL, TIME_ATTACK, DRIFT_ZONE, SPEED_TRAP, SPEED_ZONE, DANGER_SIGN, SHOWCASE }

const TYPE_NAMES := ["Circuit", "Sprint", "Hillclimb Duel", "Autoroute Duel", "Time Attack", "Drift Zone", "Speed Trap", "Speed Zone", "Danger Sign", "Showcase"]

## class_max: 0 D, 1 C, 2 B, 3 A, 4 S1, 5 S2, 6 X. time = hour of day. weather: SkyWeather.W.
const EVENTS := [
	# ---- Circuits ----
	{"id": "monaco_gp", "name": "Grand Prix de Monaco", "type": Type.CIRCUIT, "route": "monaco_gp", "laps": 3,
		"rivals": 7, "class_max": 3, "time": 14.5, "weather": 0, "credits": 32000, "xp": 1600, "level": 1, "district": "Monte-Carlo"},
	{"id": "monaco_night", "name": "Monte-Carlo by Night", "type": Type.CIRCUIT, "route": "monaco_gp", "laps": 2,
		"rivals": 7, "class_max": 4, "time": 22.5, "weather": 0, "credits": 44000, "xp": 2100, "level": 3, "district": "Monte-Carlo"},
	{"id": "monaco_wet", "name": "Monaco in the Wet", "type": Type.CIRCUIT, "route": "monaco_gp", "laps": 2,
		"rivals": 5, "class_max": 2, "time": 16.0, "weather": 3, "credits": 26000, "xp": 1300, "level": 2, "district": "La Condamine"},
	# ---- Sprints ----
	{"id": "basse_corniche", "name": "Basse Corniche Coast Run", "type": Type.SPRINT, "route": "basse_corniche",
		"rivals": 5, "class_max": 2, "time": 9.5, "weather": 0, "credits": 12000, "xp": 600, "level": 0, "district": "Cap d'Ail"},
	{"id": "moyenne_corniche", "name": "Moyenne Corniche Sprint", "type": Type.SPRINT, "route": "moyenne_corniche",
		"rivals": 7, "class_max": 3, "time": 18.0, "weather": 0, "credits": 22000, "xp": 1100, "level": 1, "district": "Èze-sur-Mer"},
	{"id": "turbie_descent", "name": "Route de La Turbie Descent", "type": Type.SPRINT, "route": "route_turbie", "reverse": true,
		"rivals": 5, "class_max": 1, "time": 8.0, "weather": 6, "credits": 9000, "xp": 450, "level": 0, "district": "La Turbie"},
	{"id": "corniche_descent", "name": "Grande Corniche Descent", "type": Type.SPRINT, "route": "grande_corniche", "reverse": true,
		"rivals": 5, "class_max": 4, "time": 19.0, "weather": 0, "credits": 24000, "xp": 1200, "level": 2, "district": "Grande Corniche"},
	{"id": "mont_agel_climb", "name": "Col du Mont Agel Time Attack", "type": Type.TIME_ATTACK, "route": "col_mont_agel",
		"rivals": 0, "class_max": 6, "time": 11.0, "weather": 0, "credits": 15000, "xp": 800, "level": 1, "district": "Mont Agel"},
	# ---- Rival duels ----
	{"id": "duel_monte_carlo", "name": "Monte-Carlo Street Duel", "type": Type.TOUGE_BATTLE, "route": "monaco_gp", "laps": 2,
		"rivals": 1, "class_max": 3, "time": 21.0, "weather": 0, "credits": 20000, "xp": 1000, "level": 1, "district": "Monte-Carlo", "rival": "mika"},
	{"id": "duel_grande_corniche", "name": "Grande Corniche Hillclimb", "type": Type.TOUGE_BATTLE, "route": "grande_corniche",
		"rivals": 1, "class_max": 3, "time": 7.0, "weather": 0, "credits": 28000, "xp": 1500, "level": 2, "district": "Grande Corniche", "rival": "takumi"},
	{"id": "duel_port", "name": "Port Hercule Duel", "type": Type.TOUGE_BATTLE, "route": "monaco_gp", "laps": 2,
		"rivals": 1, "class_max": 3, "time": 19.5, "weather": 0, "credits": 24000, "xp": 1200, "level": 3, "district": "La Condamine", "rival": "goro"},
	{"id": "duel_moyenne", "name": "Moyenne Corniche Duel", "type": Type.TOUGE_BATTLE, "route": "moyenne_corniche", "reverse": true,
		"rivals": 1, "class_max": 4, "time": 6.0, "weather": 6, "credits": 30000, "xp": 1600, "level": 4, "district": "Èze-sur-Mer", "rival": "keisuke"},
	{"id": "duel_mont_agel", "name": "Mont Agel Rally Duel", "type": Type.TOUGE_BATTLE, "route": "col_mont_agel",
		"rivals": 1, "class_max": 4, "time": 17.0, "weather": 4, "credits": 34000, "xp": 1700, "level": 5, "district": "Mont Agel", "rival": "yuna"},
	{"id": "duel_a8", "name": "A8 Autoroute Duel", "type": Type.WANGAN_DUEL, "route": "a8_sprint",
		"rivals": 1, "class_max": 6, "time": 1.5, "weather": 0, "credits": 45000, "xp": 2000, "level": 5, "district": "Autoroute A8", "rival": "blackbird"},
	# ---- Championship finale ----
	{"id": "festival_grand_prix", "name": "Euro GT Festival Grand Prix", "type": Type.SHOWCASE, "route": "monaco_gp", "laps": 3,
		"rivals": 1, "class_max": 6, "time": 20.5, "weather": 0, "credits": 100000, "xp": 5000, "level": 6, "district": "Monte-Carlo", "rival": "champion", "reward_car": "ferrari_laferrari"},
	# ---- Police pursuits ----
	{"id": "police_a8", "name": "Autoroute Gendarmerie Pursuit", "type": Type.SPRINT, "route": "a8_sprint",
		"rivals": 0, "class_max": 6, "time": 23.0, "weather": 0, "credits": 38000, "xp": 1900, "level": 3, "district": "Autoroute A8", "police_heat": 3},
	{"id": "police_corniche", "name": "Corniche Outrun", "type": Type.SPRINT, "route": "grande_corniche", "reverse": true,
		"rivals": 0, "class_max": 5, "time": 2.0, "weather": 3, "credits": 32000, "xp": 1600, "level": 2, "district": "Grande Corniche", "police_heat": 2},
]

static var _cache: Array = []

## Every event with `roads`, `closed` and `length` resolved from the baked map.
static func all() -> Array:
	if not _cache.is_empty():
		return _cache
	for e in EVENTS:
		var ev: Dictionary = e.duplicate(true)
		var r := MapData.route(ev.route)
		var roads: Array = (r.get("roads", []) as Array).duplicate() # never reverse the cached route in place
		if ev.get("reverse", false):
			roads.reverse()
			roads = roads.map(func(n): return n.substr(1) if n.begins_with("~") else "~" + n)
		ev["roads"] = roads
		ev["closed"] = bool(r.get("closed", false))
		ev["length"] = float(r.get("length_m", 0))
		if not ev.has("laps"):
			ev["laps"] = 1
		_cache.append(ev)
	return _cache

static func get_event(id: String) -> Dictionary:
	for e in all():
		if e.id == id:
			return e
	return {}

## One-lap length in metres (from the map bake).
static func length_of(id: String) -> float:
	return float(get_event(id).get("length", 0.0))
