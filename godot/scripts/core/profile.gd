extends Node
## Player career save: credits, XP / festival level, garage, event records, discovery, rivals.
## Saved as JSON with an atomic write (temp + rename) and 3 rotating backups; a corrupt save
## falls back to the newest backup that parses. `version` drives migrations.

signal changed
signal level_up(level: int)

var PATH := "user://profile.json" # "-- profile=<name>" isolates test runs
const VERSION := 3
const BACKUPS := 3
const STARTERS := ["abarth_500", "golf_gti", "bmw_m3_e30"]
const SELL_RATE := 0.6 # of purchase price + installed parts

var data := {}

func _defaults() -> Dictionary:
	return {
		"version": VERSION,
		"credits": 25_000,
		"xp": 0,
		"level": 1,
		# [{"uid", "key", "paint": [r,g,b], "finish", "upgrades": {cat: level, "swap": n},
		#   "tune": {override: value}, "pi", "spent", "km", "source"}]
		"garage": [],
		"next_uid": 1,
		"current_car": 0,
		"records": {}, # event id -> {"best_time": s, "best_pos": n, "wins": n}
		"discovered": [], # road names / fast-travel ids
		"omamori": [],
		"barns": [],
		"rivals_beaten": [],
		"omikuji": 0, # unopened fortune draws
		"stats": {"distance_km": 0.0, "drift_score": 0, "races": 0, "wins": 0, "near_misses": 0, "play_seconds": 0.0},
		"onboarded": false,
	}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("profile="):
			PATH = "user://profile_%s.json" % a.substr(8).validate_filename()
	load_profile()

func load_profile() -> void:
	data = _defaults()
	var candidates := [PATH]
	for i in range(1, BACKUPS + 1):
		candidates.append("%s.bak%d" % [PATH, i])
	for p in candidates:
		if not FileAccess.file_exists(p):
			continue
		var raw_str := FileAccess.get_file_as_string(p)
		if raw_str.strip_edges().is_empty():
			continue
		var parsed = JSON.parse_string(raw_str)
		if typeof(parsed) == TYPE_DICTIONARY:
			# Verify minimal schema sanity
			var cr = parsed.get("credits", null)
			var gr = parsed.get("garage", null)
			if cr != null and typeof(cr) in [TYPE_INT, TYPE_FLOAT] and gr != null and typeof(gr) == TYPE_ARRAY:
				_merge(parsed)
				if p != PATH:
					push_warning("Profile: main save unreadable, restored from %s" % p)
				break
	_migrate()

## New festival: wipe progress (the previous save stays in the backup rotation).
func reset() -> void:
	data = _defaults()
	save()
	changed.emit()

func _merge(parsed: Dictionary) -> void:
	for k in parsed.keys():
		data[k] = parsed[k]
	data.credits = clampi(int(data.get("credits", 25000)), 0, 1_000_000_000)
	data.xp = clampi(int(data.get("xp", 0)), 0, 100_000_000)
	data.level = clampi(int(data.get("level", 1)), 1, 1000)
	if not data.has("stats") or typeof(data.stats) != TYPE_DICTIONARY:
		data.stats = _defaults().stats

func _migrate() -> void:
	var v := int(data.get("version", 1))
	if v < 2:
		var uid := 1
		for c in data.garage:
			if typeof(c) == TYPE_DICTIONARY:
				c["uid"] = uid
				uid += 1
				c["pi"] = -1
				c["spent"] = 0
				c["km"] = 0.0
				c["source"] = "legacy"
		data["next_uid"] = uid
	var valid_garage := []
	for c in data.garage:
		if typeof(c) == TYPE_DICTIONARY and c.has("key") and typeof(c.key) == TYPE_STRING:
			if not CarData.CARS.has(c.key):
				# v3: the JDM roster became the European one; engine swaps pointed at JDM donors.
				c.key = CarData.resolve(c.key)
				if typeof(c.get("upgrades")) == TYPE_DICTIONARY:
					c.upgrades.erase("swap")
				c["pi"] = -1
			if not c.has("upgrades") or typeof(c.upgrades) != TYPE_DICTIONARY:
				c["upgrades"] = {}
			if not c.has("tune") or typeof(c.tune) != TYPE_DICTIONARY:
				c["tune"] = {}
			if int(c.get("pi", -1)) <= 0:
				c["pi"] = compute_pi(c)
			valid_garage.append(c)
	data.garage = valid_garage
	data.version = VERSION

func save() -> void:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Profile: cannot write save")
		return
	f.store_string(JSON.stringify(data))
	f.close()
	# Rotate backups: bak2 -> bak3, bak1 -> bak2, main -> bak1, tmp -> main.
	for i in range(BACKUPS - 1, 0, -1):
		var src := "%s.bak%d" % [PATH, i]
		if FileAccess.file_exists(src):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path("%s.bak%d" % [PATH, i + 1]))
	if FileAccess.file_exists(PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(PATH + ".bak1"))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH))
	changed.emit()

func _notification(what: int) -> void:
	# Android pause / app switch: flush the save.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()

# ---- Economy / progression -------------------------------------------------------------

static func xp_for_level(level: int) -> int:
	return int(1500.0 * pow(float(level), 1.35))

func add_credits(n: int) -> void:
	data.credits = int(data.credits) + n
	changed.emit()

func spend(n: int) -> bool:
	if int(data.credits) < n:
		return false
	data.credits = int(data.credits) - n
	changed.emit()
	return true

func add_xp(n: int) -> void:
	data.xp = int(data.xp) + n
	while int(data.xp) >= xp_for_level(int(data.level)):
		data.xp = int(data.xp) - xp_for_level(int(data.level))
		data.level = int(data.level) + 1
		data.omikuji = int(data.omikuji) + 1
		level_up.emit(int(data.level))
	changed.emit()

func record_result(result: Dictionary) -> void:
	var ev_id: String = result.get("event", "")
	var rec: Dictionary = data.records.get(ev_id, {"best_time": -1.0, "best_pos": 99, "wins": 0})
	var r_time: float = float(result.get("time", -1.0))
	var rec_best: float = float(rec.get("best_time", -1.0))
	if r_time > 0.0 and (rec_best < 0.0 or r_time < rec_best):
		rec["best_time"] = r_time
	var pos: int = int(result.get("position", 99))
	rec["best_pos"] = mini(int(rec.get("best_pos", 99)), pos)
	var bl: float = float(result.get("best_lap", -1.0))
	if bl > 0.0:
		var cur_bl: float = float(rec.get("best_lap", -1.0))
		rec["best_lap"] = bl if cur_bl <= 0.0 else minf(cur_bl, bl)
	if pos == 1:
		rec["wins"] = int(rec.get("wins", 0)) + 1
		data.stats.wins = int(data.stats.get("wins", 0)) + 1
	data.records[ev_id] = rec
	data.stats.races = int(data.stats.get("races", 0)) + 1
	add_credits(int(result.get("credits", 0)))
	add_xp(int(result.get("xp", 0)))
	var ev := EventData.get_event(ev_id)
	if pos == 1 and ev.has("rival") and not data.rivals_beaten.has(ev.rival):
		data.rivals_beaten.append(ev.rival)
	save()

# ---- Garage ------------------------------------------------------------------------------

func owns(key: String) -> bool:
	for c in data.garage:
		if c.key == key:
			return true
	return false

## Adds a stock car to the garage and returns its index.
func add_car(key: String, source := "dealer", do_save := true) -> int:
	var car := CarData.get_car(key)
	var entry := {
		"uid": int(data.get("next_uid", 1)), "key": key,
		"paint": [car.paint.r, car.paint.g, car.paint.b], "finish": car.get("finish", "gloss"),
		"upgrades": {}, "tune": {}, "pi": int(CarData.STOCK_PI.get(key, 500)),
		"spent": 0, "km": 0.0, "source": source,
	}
	data.next_uid = int(entry.uid) + 1
	data.garage.append(entry)
	if do_save:
		save()
	return data.garage.size() - 1

func current_index() -> int:
	return clampi(int(data.current_car), 0, maxi(0, data.garage.size() - 1))

func current_car() -> Dictionary:
	if data.garage.is_empty():
		return {}
	return data.garage[current_index()]

func set_current(index: int) -> void:
	data.current_car = clampi(index, 0, data.garage.size() - 1)
	save()

func sell_value(entry: Dictionary) -> int:
	var base := int(CarData.get_car(entry.key).get("price", 10000))
	return int((base + int(entry.get("spent", 0))) * SELL_RATE)

## Sells a car (never the last one). Returns the credits received, or -1.
func sell(index: int) -> int:
	if data.garage.size() <= 1 or index < 0 or index >= data.garage.size():
		return -1
	var value := sell_value(data.garage[index])
	data.garage.remove_at(index)
	if int(data.current_car) >= index:
		data.current_car = maxi(0, int(data.current_car) - 1)
	add_credits(value)
	save()
	return value

func overrides_for(entry: Dictionary) -> Dictionary:
	return UpgradeData.overrides_for(entry)

func compute_pi(entry: Dictionary) -> int:
	return int(NTSim.benchmark(entry.get("key", CarData.DEFAULT_KEY), overrides_for(entry)).pi)

func paint_for(entry: Dictionary) -> ShaderMaterial:
	var p: Array = entry.get("paint", [])
	var col = Color(p[0], p[1], p[2]) if p.size() >= 3 else null
	var m := CarBuilder.paint_material(entry.get("key", CarData.DEFAULT_KEY), col, entry.get("finish", ""))
	return m

## Onboarding: first car is free.
func choose_starter(key: String) -> void:
	if not STARTERS.has(key):
		return
	var i := add_car(key, "starter", false)
	data.current_car = i
	data.onboarded = true
	save()

## Launch args for driving the current car (freeroam reads "garage_entry").
func drive_args() -> Dictionary:
	var e := current_car()
	if e.is_empty():
		return {"car": CarData.DEFAULT_KEY}
	return {"car": e.key, "garage_index": current_index()}

# ---- Prize Spins (Festival level rewards) ----------------------------------------------------

const FORTUNES := [
	{"badge": "LEGENDARY", "name": "Grand Prize Car", "weight": 6, "kind": "car"},
	{"badge": "EPIC", "name": "Super Jackpot", "weight": 14, "kind": "credits", "min": 60000, "max": 150000},
	{"badge": "VERY RARE", "name": "Major Prize", "weight": 24, "kind": "credits", "min": 25000, "max": 60000},
	{"badge": "RARE", "name": "Cash Reward", "weight": 30, "kind": "credits", "min": 10000, "max": 25000},
	{"badge": "FESTIVAL XP", "name": "Bonus Festival XP", "weight": 18, "kind": "xp", "min": 800, "max": 2000},
	{"badge": "STANDARD", "name": "Consolation Prize", "weight": 8, "kind": "credits", "min": 5000, "max": 5000},
]

## Draws one fortune (consumes a draw). Returns {fortune, kind, amount|car, index}.
func draw_omikuji(rng: RandomNumberGenerator) -> Dictionary:
	if int(data.omikuji) <= 0:
		return {}
	data.omikuji = int(data.omikuji) - 1
	var total := 0
	for f in FORTUNES:
		total += int(f.weight)
	var roll := rng.randi_range(1, total)
	var pick: Dictionary = FORTUNES[0]
	for f in FORTUNES:
		roll -= int(f.weight)
		if roll <= 0:
			pick = f
			break
	var out := {"fortune": pick, "kind": pick.kind}
	match pick.kind:
		"car":
			# Any shop/barn car not yet owned (championship car excluded), cheapest odds highest.
			var pool := []
			for k in CarData.keys():
				var unlock: String = CarData.get_car(k).unlock
				if unlock != "championship" and not owns(k):
					pool.append(k)
			if pool.is_empty():
				out.kind = "credits"
				out.amount = 200000
				add_credits(200000)
			else:
				var key: String = pool[rng.randi_range(0, pool.size() - 1)]
				out.car = key
				out.index = add_car(key, "omikuji", false)
		"credits":
			var amount := int(snappedf(rng.randf_range(pick.min, pick.max), 500.0))
			out.amount = amount
			add_credits(amount)
		"xp":
			var xp := int(snappedf(rng.randf_range(pick.min, pick.max), 50.0))
			out.amount = xp
			add_xp(xp)
	save()
	return out
