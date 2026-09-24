extends Node
## Career QA: free-roam integration (class/level gates, stats commit, race result recording).
## godot --path . --resolution 1334x750 res://qa/career/fr.tscn -- profile=qa_career_fr autodrive

var args := {}
var fr: Node
var _t0 := 0
var near_miss_skills := 0
var skill_counts := {}
var banked := []

func log_(m: String) -> void:
	print("CFR| %7.2f  %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, m])

func frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func fast(ff: float) -> void:
	Engine.time_scale = ff
	Engine.physics_ticks_per_second = int(120 * ff)
	Engine.max_physics_steps_per_frame = int(8 * ff)

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	get_tree().create_timer(float(args.get("timeout", "900")), true, false, true).timeout.connect(func():
		log_("GLOBAL TIMEOUT")
		get_tree().quit(3))
	# Fresh career: sylph starter + raijin (true PI) + titan with a stale PI of 100.
	Profile.reset()
	Profile.choose_starter("sylph_s2")
	var ri := Profile.add_car("raijin_r", "qa", false)
	var ti := Profile.add_car("titan_rz", "qa", false)
	Profile.data.garage[ti].pi = 100
	Profile.data.current_car = 0
	Profile.save()
	log_("garage %s level %d credits %d" % [str(Profile.data.garage.map(func(c): return "%s:%d" % [c.key, int(c.pi)])), int(Profile.data.level), int(Profile.data.credits)])
	get_tree().root.set_meta("launch", {"car": "sylph_s2", "garage_index": 0})
	fr = load("res://scenes/freeroam.tscn").instantiate()
	add_child(fr)
	while fr.get("_state") != "playing":
		await frames(1)
	log_("playing; autodrive=%s" % str(args.has("autodrive")))
	fr.skills.skill.connect(func(n, p):
		skill_counts[n] = int(skill_counts.get(n, 0)) + 1)
	fr.skills.chain_banked.connect(func(p): banked.append(p))
	var seq: String = args.get("seq", "stats,gates,race")
	for step in seq.split(","):
		match step:
			"stats": await _stats_phase()
			"gates": await _gates_phase(ri, ti)
			"race": await _race_phase(args.get("event", "route1_sprint"))
			"donut": await _donut_phase()
	log_("DONE")
	Engine.time_scale = 1.0
	get_tree().quit()

func _stats_phase() -> void:
	var dist0 := float(Profile.data.stats.distance_km)
	var play0 := float(Profile.data.stats.play_seconds)
	var km0 := float(Profile.data.garage[0].km)
	var ms0 := Time.get_ticks_msec()
	var odo_sum := 0.0
	var ff := float(args.get("ff", "3"))
	fast(ff)
	var secs := float(args.get("roam", "60"))
	var sim_t := 0.0
	var max_speed := 0.0
	while sim_t < secs:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		sim_t += dt
		var t: Dictionary = fr.player.telemetry
		odo_sum += float(t.get("speed", 0.0)) * dt
		max_speed = maxf(max_speed, float(t.get("speed_kmh", 0.0)))
	fast(1.0)
	var odo_pending: float = fr._odo_m
	var play_pending: float = fr._play_s
	fr._commit_stats()
	log_("STATS roamed sim %.1f s (wall %.1f s, ff %.1f), max %.0f km/h; own odometer integral %.3f km; freeroam _odo_m %.3f km, _play_s %.1f s" % [sim_t, (Time.get_ticks_msec() - ms0) / 1000.0, ff, max_speed, odo_sum / 1000.0, odo_pending / 1000.0, play_pending])
	log_("STATS after commit: distance_km %.3f (+%.3f) play_seconds %.1f (+%.1f) garage[0].km %.3f (+%.3f)" % [float(Profile.data.stats.distance_km), float(Profile.data.stats.distance_km) - dist0, float(Profile.data.stats.play_seconds), float(Profile.data.stats.play_seconds) - play0, float(Profile.data.garage[0].km), float(Profile.data.garage[0].km) - km0])
	log_("STATS skills seen %s ; chains banked %s ; stats.near_misses=%d stats.drift_score=%d credits=%d xp=%d level=%d" % [str(skill_counts), str(banked), int(Profile.data.stats.near_misses), int(Profile.data.stats.drift_score), int(Profile.data.credits), int(Profile.data.xp), int(Profile.data.level)])

func _try_event(label: String, entry: Dictionary, ev_id: String) -> void:
	fr._entry = entry
	var ev := EventData.get_event(ev_id)
	fr.hud.toast("", 0.0)
	fr.start_event(ev)
	await frames(3)
	var toast: String = str(fr.hud.get("toast_text"))
	var started: bool = fr.race != null
	log_("GATE %s: car=%s pi=%s level=%d event=%s (class<=%s, lvl %d) -> %s  toast='%s'" % [label, entry.get("key", "<dev/no entry>"), str(entry.get("pi", "-")), int(Profile.data.level), ev_id, CarData.CLASS_NAMES[int(ev.class_max)], int(ev.level), "RACE STARTED" if started else "blocked", toast])
	if started:
		var t0 := Time.get_ticks_msec()
		while fr.race != null and fr.race.state == RaceManager.State.IDLE and Time.get_ticks_msec() - t0 < 30000:
			await frames(1)
		if fr.race != null:
			fr.race.abort()
		await frames(10)

func _gates_phase(ri: int, ti: int) -> void:
	var g: Array = Profile.data.garage
	await _try_event("starter C545 into B event", g[0], "docks_circuit")
	await _try_event("raijin A690 into B event", g[ri], "docks_circuit")
	await _try_event("titan true B617 but saved pi=100 into D-limit? (docks B)", g[ti], "docks_circuit")
	await _try_event("level-1 player, level-5 event", g[0], "wangan_duel")
	await _try_event("dev launch (no garage entry, e.g. event= arg) level-5 event", {}, "wangan_duel")
	fr._entry = g[0]

func _donut_phase() -> void:
	# Hold full lock + part throttle in the festival car park and watch the skill chain grow.
	var id: int = fr.player.car_id
	fr.driver.enabled = false
	fr.sim.set_ai(id, false)
	if args.has("noassist"):
		fr.sim.set_assists(id, {"abs": true, "tcs": false, "stm": false, "steering": 2, "gearbox": 0, "countersteer": 0.0, "mechanical_damage": false})
	var c0 := int(Profile.data.credits)
	var x0 := int(Profile.data.xp)
	var ff := float(args.get("ff", "3"))
	fast(ff)
	var secs := float(args.get("donut", "180"))
	var sim_t := 0.0
	var next_log := 0.0
	var steer := float(args.get("steer", "1.0"))
	var thr := float(args.get("thr", "0.8"))
	var hb_t := 0.0
	var max_mult := 0
	var max_chain := 0.0
	while sim_t < secs:
		# brief handbrake pulse every 4 s to initiate/maintain rotation
		hb_t += get_physics_process_delta_time()
		var hb := 1.0 if fmod(hb_t, 4.0) < 0.15 else 0.0
		fr.sim.set_input(id, steer, thr, 0.0, hb, 0.0)
		await get_tree().physics_frame
		sim_t += get_physics_process_delta_time()
		max_mult = maxi(max_mult, fr.skills.multiplier)
		max_chain = maxf(max_chain, fr.skills.chain_points)
		if sim_t >= next_log:
			next_log += 15.0
			var t: Dictionary = fr.player.telemetry
			log_("DONUT t=%.0f s speed %.0f km/h drift %.0f° in_drift=%s chain %.0f x%d (combo %.1f) banked %s" % [sim_t, float(t.get("speed_kmh", 0.0)), rad_to_deg(absf(float(t.get("drift_angle", 0.0)))), str(fr.skills.in_drift), fr.skills.chain_points, fr.skills.multiplier, fr.skills.combo_timer, str(banked)])
	fr.sim.set_input(id, 0.0, 0.0, 1.0, 1.0, 0.0)
	# Let it bank (4 s after drift ends).
	var w := 0.0
	while w < 8.0:
		await get_tree().physics_frame
		w += get_physics_process_delta_time()
	fast(1.0)
	log_("DONUT result: %.0f sim s, max chain %.0f, max mult x%d, banked %s -> credits %+d xp %+d level %d, stats.drift_score %d" % [secs, max_chain, max_mult, str(banked), int(Profile.data.credits) - c0, int(Profile.data.xp) - x0, int(Profile.data.level), int(Profile.data.stats.drift_score)])
	fr.driver.enabled = true

func _race_phase(ev_id: String) -> void:
	for run in range(int(args.get("runs", "2"))):
		var c0 := int(Profile.data.credits)
		var x0 := int(Profile.data.xp)
		var l0 := int(Profile.data.level)
		fr._entry = Profile.data.garage[0]
		fr.start_event(EventData.get_event(ev_id))
		var t0 := Time.get_ticks_msec()
		while fr.race == null or fr.race.state == RaceManager.State.IDLE:
			await frames(1)
		var race = fr.race
		var got := {}
		race.race_finished.connect(func(r): got.merge(r))
		while race.state == RaceManager.State.COUNTDOWN:
			await frames(1)
		fr.sim.set_ai(fr.player.car_id, true)
		fr.sim.set_ai_difficulty(fr.player.car_id, int(args.get("pai", "6")))
		fast(float(args.get("ff", "3")))
		while is_instance_valid(race) and race.state != RaceManager.State.RESULTS and Time.get_ticks_msec() - t0 < 400000:
			await frames(1)
		fast(1.0)
		await frames(5)
		log_("RACE %s run %d: result pos %s/%s time %.2f credits %s xp %s ; profile credits %+d xp %+d (level %d->%d) ; record %s ; stats %s" % [ev_id, run + 1, str(got.get("position")), str(got.get("cars")), float(got.get("time", -1.0)), str(got.get("credits")), str(got.get("xp")), int(Profile.data.credits) - c0, int(Profile.data.xp) - x0, l0, int(Profile.data.level), JSON.stringify(Profile.data.records.get(ev_id, {})), JSON.stringify(Profile.data.stats)])
		if is_instance_valid(race):
			await get_tree().create_timer(0.5).timeout
			var e := InputEventAction.new()
			e.action = "ui_accept"
			e.pressed = true
			Input.parse_input_event(e)
			await frames(3)
			var r := InputEventAction.new()
			r.action = "ui_accept"
			r.pressed = false
			Input.parse_input_event(r)
		var tw := Time.get_ticks_msec()
		while fr.race != null and Time.get_ticks_msec() - tw < 10000:
			await frames(1)
		log_("after results: race=%s skills.enabled=%s traffic=%s" % [str(fr.race), str(fr.skills.enabled), str(fr.sim.is_traffic_enabled())])
		await frames(30)
