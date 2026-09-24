extends Node
## QA career harness. Run: godot --headless --path . res://qa/career/harness.tscn -- profile=qa_career test=<name>

var args := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	# Watchdog: a script error aborts _ready before quit(); leave after N seconds anyway.
	get_tree().create_timer(float(args.get("watchdog", "120"))).timeout.connect(func():
		print("=== WATCHDOG QUIT (test aborted by an error?)")
		get_tree().quit(3))
	var t: String = args.get("test", "pi")
	print("=== HARNESS test=%s profile_path=%s" % [t, Profile.PATH])
	match t:
		"pi": _test_pi()
		"pi_combo": _test_pi_combo()
		"economy": _test_economy()
		"omikuji": _test_omikuji()
		"tune": _test_tune()
		"dump": _dump()
		"saveops": _test_saveops()
		"write": _write_profile()
		"rivals": _test_rivals()
		"params":
			for k in CarData.keys():
				var p := NTSim.car_params(k, {})
				print("PARAM|%s|tire_compound=%s diff_rear=%s lsd_accel=%s lsd_decel=%s gear_count=%s shift_time=%s lift f/r=%s/%s" % [k, p.get("tire_compound"), p.get("diff_rear"), p.get("lsd_accel"), p.get("lsd_decel"), p.get("gear_count"), p.get("shift_time"), p.get("lift_front"), p.get("lift_rear")])
			var t0 := Time.get_ticks_msec()
			for i in range(5):
				Profile.compute_pi({"key": "raijin_r", "upgrades": {"intake": 3}, "tune": {}})
			print("PARAM|Profile.compute_pi main-thread cost: %.0f ms per call" % ((Time.get_ticks_msec() - t0) / 5.0))
		"reset":
			Profile.reset()
			Profile.choose_starter("sylph_s2")
			Profile.data.credits = 999999
			Profile.data.level = 9
			Profile.save()
			Profile.reset()
			for p in [Profile.PATH, Profile.PATH + ".bak1", Profile.PATH + ".bak2", Profile.PATH + ".bak3"]:
				var d = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
				print("RESET|%s credits=%s level=%s garage=%s onboarded=%s" % [p.get_file(), str(d.credits) if d else "-", str(d.level) if d else "-", str(d.garage.size()) if d else "-", str(d.onboarded) if d else "-"])
			for i in range(3):
				Profile.save()
			var found := false
			for p in [Profile.PATH, Profile.PATH + ".bak1", Profile.PATH + ".bak2", Profile.PATH + ".bak3"]:
				var d = JSON.parse_string(FileAccess.get_file_as_string(p))
				if d and int(d.credits) == 999999:
					found = true
			print("RESET|after 3 more saves, pre-reset progress still recoverable: %s" % str(found))
	print("=== DONE")
	get_tree().quit()

func _bench(key: String, upg: Dictionary, tune := {}) -> Dictionary:
	return NTSim.benchmark(key, UpgradeData.build_overrides(key, upg, tune))

func _cls(pi: int) -> String:
	return CarData.CLASS_NAMES[CarData.pi_class(pi)]

# ---------------------------------------------------------------------------------------------
func _test_pi() -> void:
	var t0 := Time.get_ticks_msec()
	print("## STOCK PI: CarData.STOCK_PI vs NTSim.benchmark")
	for key in CarData.keys():
		var b := _bench(key, {})
		var sp := int(CarData.STOCK_PI[key])
		print("STOCK|%s|table=%d %s|measured=%d %s|diff=%d|0-100=%.2f|top=%.1f|brake=%.1f|latg=%.3f|kw=%.0f|kg=%.0f" % [key, sp, _cls(sp), int(b.pi), _cls(int(b.pi)), int(b.pi) - sp, b.t_0_100, b.top_speed, b.brake_100_0, b.lateral_g, b.power_kw, b.weight_kg])
	print("bench time per call ~%d ms" % ((Time.get_ticks_msec() - t0) / 12))
	print("## PER-CATEGORY LEVELS (single upgrade on stock car)")
	for key in CarData.keys():
		var base := _bench(key, {})
		var bpi := int(base.pi)
		for cat in UpgradeData.CATEGORIES:
			var row := []
			var prev := bpi
			var nonmono := false
			for lvl in range(1, cat.levels.size()):
				var b := _bench(key, {cat.id: lvl})
				var pi := int(b.pi)
				var price := UpgradeData.price_of(cat.id, lvl)
				row.append("L%d %s=%d(%+d)%s ¥%d" % [lvl, cat.levels[lvl].name, pi, pi - bpi, "" if _cls(pi) == _cls(bpi) else "->" + _cls(pi), price])
				if cat.id != "compound" and pi < prev:
					nonmono = true
				prev = pi
			print("LVL|%s|%s|base %d|%s%s" % [key, cat.id, bpi, " ; ".join(row), "  <<NON-MONOTONIC" if nonmono else ""])
		# swaps
		var donors: Array = UpgradeData.SWAPS.get(key, [])
		var srow := []
		for n in range(1, donors.size() + 1):
			var b := _bench(key, {"swap": n})
			srow.append("%s=%d(%+d)%s ¥%d" % [donors[n - 1], int(b.pi), int(b.pi) - bpi, _cls(int(b.pi)), UpgradeData.SWAP_PRICE[n]])
		print("SWAP|%s|base %d|%s" % [key, bpi, " ; ".join(srow)])
	print("total ms %d" % (Time.get_ticks_msec() - t0))

func _max_build(swap := 0, compound := 2) -> Dictionary:
	var u := {}
	for cat in UpgradeData.CATEGORIES:
		if cat.id == "compound":
			u[cat.id] = compound
		elif cat.id == "awd":
			continue
		else:
			u[cat.id] = cat.levels.size() - 1
	if swap > 0:
		u["swap"] = swap
	return u

func _cost(u: Dictionary) -> int:
	var c := 0
	for k in u:
		if k == "swap":
			c += UpgradeData.SWAP_PRICE[int(u[k])]
		else:
			c += UpgradeData.price_of(k, int(u[k]))
	return c

func _test_pi_combo() -> void:
	print("## MAX BUILDS (all top parts, semi-slicks, no AWD) and with each swap, plus AWD")
	for key in CarData.keys():
		var base := int(_bench(key, {}).pi)
		var parts := []
		for sw in range(0, UpgradeData.SWAPS.get(key, []).size() + 1):
			var u := _max_build(sw)
			var b := _bench(key, u)
			parts.append("sw%d=%d %s ¥%d" % [sw, int(b.pi), _cls(int(b.pi)), _cost(u) + int(CarData.get_car(key).price)])
		var u2 := _max_build(0)
		u2["awd"] = 1
		var b2 := _bench(key, u2)
		parts.append("max+awd=%d" % int(b2.pi))
		print("MAX|%s|stock %d %s|%s" % [key, base, _cls(base), " ; ".join(parts)])
	print("## CUMULATIVE PATH (add categories one by one, top level) - monotonic check")
	for key in ["mame_k", "hachi_gt", "sylph_s2", "kaido_van", "mugen_proto", "raijin_r"]:
		var u := {}
		var prev := int(_bench(key, {}).pi)
		var steps := []
		for cat in UpgradeData.CATEGORIES:
			if cat.id in ["awd", "compound"]:
				continue
			u[cat.id] = cat.levels.size() - 1
			var pi := int(_bench(key, u).pi)
			steps.append("%s:%d%s" % [cat.id, pi, "!" if pi < prev else ""])
			prev = pi
		print("PATH|%s|%s" % [key, " ".join(steps)])
	print("## LOWEST-CLASS REACH: min PI via tyre compounds (drift/snow/rally) on stock")
	for key in CarData.keys():
		var r := []
		for c in [1, 2, 3, 4, 5]:
			r.append("%d=%d" % [c, int(_bench(key, {"compound": c}).pi)])
		print("TYRE|%s|%s" % [key, " ".join(r)])
	print("## AWD on already-AWD cars: layout param")
	for key in CarData.keys():
		var p := NTSim.car_params(key, {})
		print("LAYOUT|%s|layout=%s|awd_split=%s|max_boost=%s|engine_kind=%s|mass=%s" % [key, p.get("layout"), p.get("awd_front_split"), p.get("max_boost"), p.get("engine_kind"), p.get("mass")])

# ---------------------------------------------------------------------------------------------
func _payout(ev: Dictionary, pos: int, diff: int, rewind: bool) -> Array:
	# Copy of RaceManager._show_results math.
	var mult := 1.0 + 0.12 * diff
	if not rewind:
		mult += 0.1
	var share: float = [1.0, 0.6, 0.45, 0.35][mini(pos - 1, 3)] if pos <= 4 else 0.25
	var credits := int(round(float(ev.credits) * share * mult / 100.0) * 100)
	var xp := int(float(ev.xp) * (1.0 if pos == 1 else 0.5) * mult)
	return [credits, xp]

func _test_economy() -> void:
	print("## EVENT PAYOUTS (credits/xp) by difficulty & position")
	for ev in EventData.all():
		var len_km := float(EventData.LENGTHS.get(ev.id, 0)) * (int(ev.get("laps", 1)) if ev.closed else 1) / 1000.0
		var line := "PAY|%s|lvl %d|cls<=%s|rivals %d|%.1f km|" % [ev.id, int(ev.level), CarData.CLASS_NAMES[int(ev.class_max)], int(ev.rivals), len_km]
		var cells := []
		for d in [0, 3, 6]:
			var w := _payout(ev, 1, d, true)
			var l := _payout(ev, int(ev.rivals) + 1, d, true)
			cells.append("d%d win %d/%dxp last %d/%dxp" % [d, w[0], w[1], l[0], l[1]])
		var wmax := _payout(ev, 1, 6, false)
		cells.append("d6+norewind win %d/%dxp" % [wmax[0], wmax[1]])
		cells.append("credits/km(win,d3)=%d" % int(_payout(ev, 1, 3, true)[0] / maxf(len_km, 0.01)))
		print(line + " | ".join(cells))
	print("## XP CURVE")
	var cum := 0
	for lv in range(1, 31):
		var need := Profile.xp_for_level(lv)
		print("XPL|L%d->L%d need %d cumulative %d" % [lv, lv + 1, need, cum + need])
		cum += need
	print("## CAR AFFORDABILITY (default difficulty 3, rewind on) from 25,000 start")
	var best_early := _payout(EventData.get_event("akina_time_attack"), 1, 3, true)
	var docks := _payout(EventData.get_event("docks_circuit"), 1, 3, true)
	for key in CarData.keys():
		var car := CarData.get_car(key)
		var price := int(car.price)
		var need := maxi(0, price - 25000)
		print("AFF|%s|%s|¥%d|need ¥%d|time-attack wins %.1f|docks wins %.1f|docks last-place %.1f" % [key, car.unlock, price, need, need / float(best_early[0]), need / float(docks[0]), need / float(_payout(EventData.get_event("docks_circuit"), 6, 3, true)[0])])
	# Full upgrade cost per car.
	var all_cost := 0
	for cat in UpgradeData.CATEGORIES:
		var mx := 0
		for l in range(1, cat.levels.size()):
			mx = maxi(mx, UpgradeData.price_of(cat.id, l))
		all_cost += mx
	print("UPG|sum of top-level parts (every category) = ¥%d ; top swap ¥%d" % [all_cost, UpgradeData.SWAP_PRICE[3]])
	# Career simulation: always win every unlocked event once, then repeat the best credits/km event.
	print("## CAREER SIM: player wins each unlocked event once per 'loop' at difficulty 3")
	var credits := 25000
	var lvl := 1
	var xp := 0
	var draws := 0
	var races := 0
	var level_at_race := {}
	for loop in range(8):
		for ev in EventData.all():
			if int(ev.level) > lvl:
				continue
			var p := _payout(ev, 1, 3, true)
			credits += p[0]
			xp += p[1]
			races += 1
			while xp >= Profile.xp_for_level(lvl):
				xp -= Profile.xp_for_level(lvl)
				lvl += 1
				draws += 1
				level_at_race[lvl] = races
		print("SIM|loop %d|races %d|credits %d|level %d|draws %d" % [loop + 1, races, credits, lvl, draws])
	print("SIM|level reached at race#: %s" % str(level_at_race))
	# Loser sim: finishing last in every event.
	credits = 25000
	lvl = 1
	xp = 0
	races = 0
	for loop in range(4):
		for ev in EventData.all():
			if int(ev.level) > lvl:
				continue
			var p := _payout(ev, int(ev.rivals) + 1, 0, true)
			credits += p[0]
			xp += p[1]
			races += 1
			while xp >= Profile.xp_for_level(lvl):
				xp -= Profile.xp_for_level(lvl)
				lvl += 1
		print("LOSER|loop %d|races %d|credits %d|level %d" % [loop + 1, races, credits, lvl])
	# Skill chain payout model
	print("## SKILL CHAIN MODEL: continuous drift at angle/speed (points/s = (angle-10)*kmh*0.08)")
	for combo in [[30.0, 50.0, 60.0], [40.0, 60.0, 180.0], [40.0, 60.0, 600.0], [35.0, 80.0, 1800.0]]:
		var ang: float = combo[0]
		var kmh: float = combo[1]
		var secs: float = combo[2]
		var pts := (ang - 10.0) * kmh * 0.08 * secs
		var mult := mini(1 + int(pts / 1500.0), 10)
		var total := int(pts * mult)
		print("CHAIN|angle %.0f° %.0f km/h for %.0f s: raw %d x%d = %d  -> +%d credits +%d XP" % [ang, kmh, secs, int(pts), mult, total, total / 10, total / 20])

# ---------------------------------------------------------------------------------------------
func _test_omikuji() -> void:
	# Uses the qa profile; resets it first.
	Profile.reset()
	Profile.choose_starter("sylph_s2")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(args.get("seed", "12345"))
	var counts := {}
	var credits0 := int(Profile.data.credits)
	var n := int(args.get("n", "400"))
	Profile.data.omikuji = n
	var car_order := []
	var dupes := 0
	var car_draw_after_full := 0
	var t0 := Time.get_ticks_msec()
	for i in range(n):
		var r := Profile.draw_omikuji(rng)
		var name: String = r.fortune.name
		counts[name] = int(counts.get(name, 0)) + 1
		if r.kind == "car":
			if car_order.has(r.car):
				dupes += 1
			car_order.append(r.car)
		elif r.fortune.kind == "car":
			car_draw_after_full += 1
	print("OMI|draws %d in %d ms (each draw = 1 save)" % [n, Time.get_ticks_msec() - t0])
	for k in counts:
		print("OMI|%s|%d|%.1f%%" % [k, counts[k], 100.0 * counts[k] / n])
	print("OMI|cars won in order: %s" % str(car_order))
	print("OMI|duplicate cars: %d ; great-blessing after roster exhausted -> credits: %d" % [dupes, car_draw_after_full])
	var keys := []
	for c in Profile.data.garage:
		keys.append(c.key)
	print("OMI|garage now: %s" % str(keys))
	print("OMI|owns kurogane: %s" % str(Profile.owns("kurogane_hyper")))
	print("OMI|credits gained %d ; level %d xp %d omikuji left %d" % [int(Profile.data.credits) - credits0, int(Profile.data.level), int(Profile.data.xp), int(Profile.data.omikuji)])
	# expected value
	var total_w := 0
	for f in Profile.FORTUNES:
		total_w += int(f.weight)
	var ev_cred := 0.0
	for f in Profile.FORTUNES:
		if f.kind == "credits":
			ev_cred += float(f.weight) / total_w * (float(f.min) + float(f.max)) / 2.0
	var pool_val := 0.0
	var pool_n := 0
	for k in CarData.keys():
		if CarData.get_car(k).unlock != "championship" and k != "sylph_s2":
			pool_val += float(CarData.get_car(k).price)
			pool_n += 1
	print("OMI|EV credits per draw %.0f ; car chance 6%% avg car price %.0f (sell 60%% = %.0f)" % [ev_cred, pool_val / pool_n, 0.6 * pool_val / pool_n])
	# odds text as shown
	var parts := []
	var sum := 0
	for f in Profile.FORTUNES:
		var p := roundi(100.0 * f.weight / total_w)
		sum += p
		parts.append("%s %d%%" % [f.name, p])
	print("OMI|odds text: %s  (sum %d%%, total weight %d)" % [", ".join(parts), sum, total_w])
	Profile.reset()

# ---------------------------------------------------------------------------------------------
func _test_tune() -> void:
	print("## TUNE vs UPGRADE interaction")
	var key := "sylph_s2"
	# 1. Stock brakes, tune pressure to 110%, then buy Race brakes.
	var base := NTSim.car_params(key, UpgradeData.build_overrides(key, {}, {}))
	var tune := {"brake_torque": float(base.brake_torque) * 1.1}
	var p_before := NTSim.car_params(key, UpgradeData.build_overrides(key, {}, tune))
	var p_after := NTSim.car_params(key, UpgradeData.build_overrides(key, {"brakes": 3}, tune))
	var p_race_clean := NTSim.car_params(key, UpgradeData.build_overrides(key, {"brakes": 3}, {}))
	print("TUNE|brake_torque stock=%.0f tuned110%%=%.0f  +Race brakes with old tune=%.0f  Race brakes w/o tune=%.0f" % [base.brake_torque, p_before.brake_torque, p_after.brake_torque, p_race_clean.brake_torque])
	print("TUNE|PI tuned stock=%d  tuned+race brakes=%d  race brakes clean=%d" % [int(_bench(key, {}, tune).pi), int(_bench(key, {"brakes": 3}, tune).pi), int(_bench(key, {"brakes": 3}).pi)])
	# 2. Springs: tune street springs, then buy race springs
	var b1 := NTSim.car_params(key, UpgradeData.build_overrides(key, {"springs": 1}, {}))
	var t2 := {"spring_front": float(b1.spring_front) * 1.05, "spring_rear": float(b1.spring_rear) * 1.05}
	var s3 := NTSim.car_params(key, UpgradeData.build_overrides(key, {"springs": 3}, t2))
	var s3c := NTSim.car_params(key, UpgradeData.build_overrides(key, {"springs": 3}, {}))
	print("TUNE|spring_front street=%.0f tuned=%.0f ; after Race springs with tune=%.0f (clean race=%.0f)" % [b1.spring_front, t2.spring_front, s3.spring_front, s3c.spring_front])
	# 3. Aero: tune downforce with race wing, then revert wing to stock (free)
	var a2 := NTSim.car_params(key, UpgradeData.build_overrides(key, {"aero": 2}, {}))
	var t3 := {"lift_front": float(a2.lift_front) * 1.6, "lift_rear": float(a2.lift_rear) * 1.6}
	var a0 := NTSim.car_params(key, UpgradeData.build_overrides(key, {}, t3))
	var st := NTSim.car_params(key, {})
	print("TUNE|aero stock lift f/r=%.3f/%.3f drag=%.3f ; race wing lift=%.3f/%.3f drag=%.3f ; wing removed but tune kept lift=%.3f/%.3f drag=%.3f" % [st.lift_front, st.lift_rear, st.drag_area, a2.lift_front, a2.lift_rear, a2.drag_area, a0.lift_front, a0.lift_rear, a0.drag_area])
	# 4. Final drive tune kept after gearbox removed
	var g1 := NTSim.car_params(key, UpgradeData.build_overrides(key, {"gearbox": 1}, {"final_drive": 6.5}))
	var g0 := NTSim.car_params(key, UpgradeData.build_overrides(key, {}, {"final_drive": 6.5}))
	print("TUNE|final_drive stock=%.2f ; with tune after gearbox reverted=%.2f" % [st.final_drive, g0.final_drive])
	# 5. unknown tune keys / junk values
	var j1 := NTSim.car_params(key, UpgradeData.build_overrides(key, {}, {"bogus_param": 5.0}))
	print("TUNE|unknown key accepted, mass=%.0f (stock %.0f)" % [j1.mass, st.mass])
	var j2 := _bench(key, {}, {"mass": 1.0})
	print("TUNE|tampered mass=1 -> PI %d top %.0f 0-100 %.2f" % [int(j2.pi), j2.top_speed, j2.t_0_100])
	var j3 := _bench(key, {"intake": 9, "exhaust": -2, "nonsense": 3, "swap": 99}, {})
	print("TUNE|junk upgrade levels -> PI %d (stock %d)" % [int(j3.pi), int(_bench(key, {}).pi)])
	# 6. Unknown car key
	var j4 := NTSim.benchmark("ferrari_f40", {})
	print("TUNE|unknown car key benchmark PI %d top %.0f" % [int(j4.pi), j4.top_speed])
	print("TUNE|CarData.get_car('ferrari_f40').name=%s price=%d" % [CarData.get_car("ferrari_f40").name, int(CarData.get_car("ferrari_f40").price)])
	# 7. Downgrade pricing
	print("TUNE|price to go intake Race->Street = %d (price_of level 1)" % UpgradeData.price_of("intake", 1))

# ---------------------------------------------------------------------------------------------
func _dump() -> void:
	print("DUMP|path=%s" % Profile.PATH)
	print("DUMP|credits=%s (%s) level=%s xp=%s omikuji=%s current_car=%s onboarded=%s version=%s" % [str(Profile.data.get("credits")), type_string(typeof(Profile.data.get("credits"))), str(Profile.data.get("level")), str(Profile.data.get("xp")), str(Profile.data.get("omikuji")), str(Profile.data.get("current_car")), str(Profile.data.get("onboarded")), str(Profile.data.get("version"))])
	var g = Profile.data.get("garage")
	print("DUMP|garage type=%s" % type_string(typeof(g)))
	if typeof(g) == TYPE_ARRAY:
		for c in g:
			print("DUMP|car %s" % JSON.stringify(c))
	print("DUMP|stats=%s" % JSON.stringify(Profile.data.get("stats")))
	print("DUMP|records=%s" % JSON.stringify(Profile.data.get("records")))
	print("DUMP|current_index=%d current_car=%s drive_args=%s" % [Profile.current_index(), JSON.stringify(Profile.current_car()), JSON.stringify(Profile.drive_args())])
	# Exercise common calls.
	print("DUMP|owns sylph=%s" % str(Profile.owns("sylph_s2")))
	if typeof(g) == TYPE_ARRAY and not g.is_empty():
		print("DUMP|sell_value[0]=%d" % Profile.sell_value(g[0]))
	Profile.add_credits(100)
	print("DUMP|after add_credits(100): %s" % str(Profile.data.credits))
	print("DUMP|spend(1000): %s credits=%s" % [str(Profile.spend(1000)), str(Profile.data.credits)])
	Profile.record_result({"event": "docks_circuit", "position": 1, "time": 123.4, "credits": 1000, "xp": 100})
	print("DUMP|after record_result: stats=%s rec=%s" % [JSON.stringify(Profile.data.stats), JSON.stringify(Profile.data.records.get("docks_circuit"))])

func _write_profile() -> void:
	pass

func _test_rivals() -> void:
	for ev in EventData.all():
		var rm := RaceManager.new()
		rm.event = ev
		var keys: Array = rm._pick_rival_cars(int(ev.rivals))
		var pis := keys.map(func(k): return int(CarData.STOCK_PI[k]))
		var avg := 0.0
		for p in pis:
			avg += p
		avg = avg / maxf(1.0, pis.size())
		print("RIV|%s|cls<=%s (PI<=%d)|lvl %d|rivals %s|PIs %s|avg %.0f|gap vs starters mame 335 / hachi 376 / sylph 545: %+.0f / %+.0f / %+.0f" % [ev.id, CarData.CLASS_NAMES[int(ev.class_max)], CarData.CLASS_MAX_PI[int(ev.class_max)], int(ev.level), str(keys), str(pis), avg, avg - 335, avg - 376, avg - 545])
		rm.free()

# ---------------------------------------------------------------------------------------------
func _test_saveops() -> void:
	var dir := ProjectSettings.globalize_path("user://")
	print("SAVE|user dir %s" % dir)
	Profile.reset()
	Profile.choose_starter("hachi_gt")
	for i in range(5):
		Profile.data.credits = 1000 * (i + 1)
		Profile.save()
	for p in [Profile.PATH, Profile.PATH + ".bak1", Profile.PATH + ".bak2", Profile.PATH + ".bak3", Profile.PATH + ".bak4", Profile.PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			var d = JSON.parse_string(FileAccess.get_file_as_string(p))
			print("SAVE|%s exists credits=%s" % [p.get_file(), str(d.credits) if typeof(d) == TYPE_DICTIONARY else "?"])
		else:
			print("SAVE|%s missing" % p.get_file())
	# record_result best_time logic
	Profile.record_result({"event": "route1_sprint", "position": 3, "time": 90.0, "credits": 100, "xp": 10})
	Profile.record_result({"event": "route1_sprint", "position": 1, "time": 95.0, "credits": 100, "xp": 10})
	Profile.record_result({"event": "route1_sprint", "position": 2, "time": 80.0, "credits": 100, "xp": 10})
	print("SAVE|record route1 after P3 90s, P1 95s, P2 80s: %s ; stats %s" % [JSON.stringify(Profile.data.records.route1_sprint), JSON.stringify(Profile.data.stats)])
	Profile.record_result({"event": "akina_time_attack", "position": 1, "time": 200.0, "credits": 100, "xp": 10})
	print("SAVE|time attack solo counts as win: stats %s" % JSON.stringify(Profile.data.stats))
	Profile.record_result({"event": "akina_downhill", "position": 1, "time": 200.0, "credits": 100, "xp": 10})
	Profile.record_result({"event": "akina_downhill", "position": 1, "time": 190.0, "credits": 100, "xp": 10})
	print("SAVE|rivals_beaten %s" % str(Profile.data.rivals_beaten))
	# sell current-index logic
	Profile.add_car("senko")
	Profile.add_car("titan_rz")
	Profile.set_current(2)
	print("SAVE|garage %s current %d" % [str(Profile.data.garage.map(func(c): return c.key)), Profile.current_index()])
	var got := Profile.sell(2)
	print("SAVE|sold current (idx2) for %d -> current now %d (%s)" % [got, Profile.current_index(), Profile.current_car().key])
	Profile.set_current(1)
	got = Profile.sell(0)
	print("SAVE|sold idx0 while current=1 -> got %d current %d (%s)" % [got, Profile.current_index(), Profile.current_car().key])
	print("SAVE|sell last car -> %d" % Profile.sell(0))
	# add_xp big
	Profile.data.level = 1
	Profile.data.xp = 0
	Profile.data.omikuji = 0
	Profile.add_xp(1_000_000)
	print("SAVE|add_xp(1e6) -> level %d xp %d draws %d" % [int(Profile.data.level), int(Profile.data.xp), int(Profile.data.omikuji)])
	# negative credits award
	Profile.data.credits = 0
	Profile.add_credits(-5000)
	print("SAVE|add_credits(-5000) from 0 -> %d ; spend(1) -> %s" % [int(Profile.data.credits), str(Profile.spend(1))])
	print("SAVE|spend(-100000) -> %s credits %d" % [str(Profile.spend(-100000)), int(Profile.data.credits)])
	Profile.reset()
