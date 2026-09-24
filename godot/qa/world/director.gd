extends Node
## QA director (tester "world"): lives on the root across scene changes and drives scenarios.

var args = {}
var shot_dir = "D:/Android_RP4_Game/build/qa/world/shots"
var fr: Node = null
var _t0 = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_msec()
	if args.has("maxfps"):
		Engine.max_fps = int(args.maxfps)
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var sc: String = args.get("sc", "none")
	log_("scenario " + sc)
	var timeout = float(args.get("timeout", "600"))
	get_tree().create_timer(timeout, true, false, true).timeout.connect(func():
		log_("GLOBAL TIMEOUT")
		get_tree().quit())
	match sc:
		"events": await sc_events()
		"pause": await sc_pause()
		"beacon": await sc_beacon()
		"roam": await sc_roam()
		"activities": await sc_activities()
		"hud": await sc_hud()
		"grid": await sc_grid()
		"conditions": await sc_conditions()
		"backnav": await sc_backnav()
		"misc": await sc_misc()
		"routeinfo": await sc_routeinfo()
		"finishline": await sc_finishline()
		"refusal": await sc_refusal()
		"tunnel": await sc_tunnel()
		"water": await sc_water()
		"ticks": await sc_ticks()
		_: log_("unknown scenario")
	log_("DONE")
	await frames(5)
	get_tree().quit()

# ---------------------------------------------------------------- helpers

func log_(m: String) -> void:
	print("QA| %7.2f  %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, m])

func frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var p = shot_dir.path_join(name + ".png")
	img.save_png(p)
	log_("SHOT " + p)

func key(k: Key, down: bool) -> void:
	var e = InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func tap(k: Key, hold_frames = 4) -> void:
	key(k, true)
	await frames(hold_frames)
	key(k, false)
	await frames(2)

func action(a: String, hold_frames = 3) -> void:
	var e = InputEventAction.new()
	e.action = a
	e.pressed = true
	Input.parse_input_event(e)
	await frames(hold_frames)
	var r = InputEventAction.new()
	r.action = a
	r.pressed = false
	Input.parse_input_event(r)
	await frames(2)

func wait_playing() -> void:
	while true:
		fr = get_tree().current_scene
		if fr and fr.get("_state") == "playing":
			break
		await frames(1)
	log_("free roam playing; spawn at %s" % fr.player.global_position)

func fast(ff: float) -> void:
	Engine.time_scale = ff
	Engine.physics_ticks_per_second = int(120 * ff)
	Engine.max_physics_steps_per_frame = int(8 * ff)

func pause_menu() -> Node:
	for c in fr.get_children():
		if c is CanvasLayer and c.get_script() and c.get_script().get_global_name() == "PauseMenu":
			return c
	return null

func pause_menus() -> int:
	var n = 0
	for c in fr.get_children():
		if c is CanvasLayer and c.get_script() and c.get_script().get_global_name() == "PauseMenu" and not c.is_queued_for_deletion():
			n += 1
	return n

func teleport(pos: Vector3, dir: Vector3, speed = 0.0) -> void:
	var xf = Transform3D(Basis.looking_at(dir, Vector3.UP), pos + Vector3(0, 1.0, 0))
	fr.streamer.focus = pos
	var waited = 0.0
	fr._follow_player = false
	fr.sim.set_frozen(fr.player.car_id, true)
	fr.sim.reset_car(fr.player.car_id, xf, 0.0)
	while not fr.streamer.has_collision_at(pos) and waited < 20.0:
		await frames(1)
		waited += get_process_delta_time()
	fr.sim.reset_car(fr.player.car_id, xf, speed)
	fr.sim.set_frozen(fr.player.car_id, false)
	fr._follow_player = true
	fr.camera.snap()
	await frames(2)

func state_summary() -> String:
	var t: Dictionary = fr.player.telemetry
	return "pos=%s spd=%.1fkmh gear=%s district=%s toast='%s'(%.1f) race_text='%s' paused=%s" % [
		fr.player.global_position, float(t.get("speed_kmh", 0.0)), t.get("gear", "?"),
		fr.world.district_name(fr._district), fr.hud.toast_text, fr.hud._toast_t, fr.hud.race_text, get_tree().paused]

func freeroam_checks(tag: String) -> void:
	var sky = fr.sky
	log_("%s CHECK: race=%s weather=%s(%s) time=%.2f tscale=%.2f wlock=%s markers_vis=%s traffic_en=%s traffic_n=%d skills_en=%s racehud_vis=%s driver_en=%s cars=%d ai=%s route_line=%d frozen?spd=%.1f" % [
		tag, fr.race, sky.weather, SkyWeather.W_NAMES[sky.weather], sky.time_of_day, sky.time_scale, sky.weather_lock,
		fr.markers.visible, fr.sim.is_traffic_enabled(), fr.sim.traffic_active_count(), fr.skills.enabled,
		fr.race_hud.visible, fr.driver.enabled, fr.sim.car_count(), fr.sim.is_ai(fr.player.car_id),
		fr.minimap.route_line.size(), float(fr.player.telemetry.get("speed_kmh", 0.0))])

# ---------------------------------------------------------------- race runner

func run_race(id: String, opts = {}) -> Dictionary:
	var out = {"id": id}
	var ev = EventData.get_event(id)
	var credits0 = int(Profile.data.credits)
	var xp0 = int(Profile.data.xp)
	var lvl0 = int(Profile.data.level)
	var races0 = int(Profile.data.stats.races)
	var t_start = Time.get_ticks_msec()
	# Wait for the race node + countdown.
	while fr.race == null or fr.race.state != RaceManager.State.COUNTDOWN:
		await frames(1)
		if Time.get_ticks_msec() - t_start > 40000:
			log_("%s: NO COUNTDOWN after 40 s (race=%s)" % [id, fr.race])
			await shot(id + "_nocountdown")
			return out
	var race: RaceManager = fr.race
	log_("%s: countdown after %.2f s; grid size %d, laps %d, route len %.0f closed=%s start_dist=%.1f finish_dist=%.1f" % [
		id, (Time.get_ticks_msec() - t_start) / 1000.0, race.cars.size(), race.laps, race.route.length, race.route.closed, race.start_distance, race.finish_distance])
	await frames(3)
	_log_grid(race)
	await shot(id + "_grid")
	var go_logged = false
	while race.state == RaceManager.State.COUNTDOWN:
		await frames(1)
	if args.has("pai"):
		fr.sim.set_ai(fr.player.car_id, true)
		fr.sim.set_ai_difficulty(fr.player.car_id, int(args.pai))
	var pt = fr.player.telemetry
	log_("%s: GO. player speed %.1f km/h gear %s" % [id, float(pt.speed_kmh), pt.gear])
	for c in race.cars:
		var tt = fr.sim.get_telemetry(c.car_id)
		log_("   car %d %s speed at GO %.1f km/h lap=%d prog=%.1f" % [c.car_id, c.key, float(tt.speed_kmh), int(tt.lap), race.progress_of(c.car_id)])
	await wait(0.4)
	await shot(id + "_go")
	await wait(3.0)
	await shot(id + "_race_early")
	var ff = float(args.get("ff", "1"))
	if ff > 1.0:
		fast(ff)
	var last_log = -10.0
	var mid_shot = false
	var stuck = {}
	var last_prog = {}
	var total_len = race.route.length * race.laps if race.route.closed else race.finish_distance - race.start_distance
	var max_time = total_len / 12.0 + 90.0
	var prev_pos = -1
	var pos_changes = 0
	while race.state == RaceManager.State.RACING:
		await frames(1)
		if not is_instance_valid(race):
			log_("%s: race node vanished mid-race" % id)
			return out
		if race.race_time - last_log >= 5.0:
			last_log = race.race_time
			var line = "%s t=%.1f P%d/%d |" % [id, race.race_time, race.position_of(fr.player.car_id), race.cars.size()]
			for c in race.cars:
				var tt = fr.sim.get_telemetry(c.car_id)
				var pr = race.progress_of(c.car_id)
				line += " [%d %s lap%d prog%.0f %.0fkmh ww%s rs%d]" % [c.car_id, c.key.substr(0, 6), int(tt.lap), pr, float(tt.speed_kmh), tt.wrong_way, int(tt.respawns)]
				if last_prog.has(c.car_id) and not race.finish_times.has(c.car_id):
					if pr - float(last_prog[c.car_id]) < 10.0:
						stuck[c.car_id] = int(stuck.get(c.car_id, 0)) + 1
						if stuck[c.car_id] >= 2:
							log_("   STUCK? car %d %s at %s prog %.0f (no progress for %d s)" % [c.car_id, c.key, c.global_position, pr, stuck[c.car_id] * 5])
							if stuck[c.car_id] == 2:
								fast(1.0)
								await shot("%s_stuck_%d" % [id, c.car_id])
								if ff > 1.0: fast(ff)
					else:
						stuck[c.car_id] = 0
				last_prog[c.car_id] = pr
			log_(line)
		var p = race.position_of(fr.player.car_id)
		if p != prev_pos:
			pos_changes += 1
			prev_pos = p
		if not mid_shot and race.progress_of(fr.player.car_id) > total_len * 0.5:
			mid_shot = true
			fast(1.0)
			await wait(0.3)
			await shot(id + "_mid")
			if ff > 1.0: fast(ff)
		if race.race_time > max_time:
			fast(1.0)
			log_("%s: RACE TIMEOUT at %.1f s (player prog %.0f / %.0f)" % [id, race.race_time, race.progress_of(fr.player.car_id), total_len])
			await shot(id + "_timeout")
			out["timeout"] = true
			race.abort()
			await frames(5)
			return out
	fast(1.0)
	log_("%s: player finished at %.3f in P%d (state %s); lap_times=%s best_lap=%s pos changes %d" % [id, race.race_time, race.finish_order.find(fr.player.car_id) + 1, race.state, race.lap_times.get(fr.player.car_id), race.best_lap, pos_changes])
	await wait(0.5)
	await shot(id + "_finish")
	var t_fin = race.race_time
	while race.state != RaceManager.State.RESULTS:
		await frames(1)
		if not is_instance_valid(race):
			return out
	log_("%s: results after %.1f s post-finish; finish_order=%s" % [id, race.race_time - t_fin, race.finish_order])
	await wait(1.0)
	await shot(id + "_results")
	var res: Dictionary = race.hud._result
	log_("%s: RESULT pos=%s time=%s best=%s credits=%s xp=%s rows=%d" % [id, res.get("position"), res.get("time"), res.get("best_lap"), res.get("credits"), res.get("xp"), res.get("rows", []).size()])
	for r in res.get("rows", []):
		log_("    row %s" % r)
	log_("%s: profile credits %d->%d (+%d) xp %d->%d lvl %d->%d races %d->%d record=%s" % [id, credits0, int(Profile.data.credits), int(Profile.data.credits) - credits0, xp0, int(Profile.data.xp), lvl0, int(Profile.data.level), races0, int(Profile.data.stats.races), Profile.data.records.get(id)])
	out["result"] = res
	if opts.get("no_continue", false):
		return out
	await wait(float(opts.get("results_wait", 1.0)))
	# Continue with A (handbrake / Space).
	key(KEY_SPACE, true)
	await wait(0.25)
	key(KEY_SPACE, false)
	var tw = 0.0
	while fr.race != null and tw < 5.0:
		await frames(1)
		tw += get_process_delta_time()
	if fr.race != null:
		log_("%s: RESULTS DID NOT CLOSE with A/Space; trying ui_accept" % id)
		await action("ui_accept")
		await wait(0.5)
	await wait(0.5)
	await shot(id + "_after0")
	await wait(3.0)
	freeroam_checks(id + " after")
	log_("   " + state_summary())
	await shot(id + "_after")
	return out

func _log_grid(race: RaceManager) -> void:
	var cars = race.cars
	for c in cars:
		var xf: Transform3D = fr.sim.get_transform(c.car_id)
		var tt = fr.sim.get_telemetry(c.car_id)
		var li = int(tt.line_index)
		var tan: Vector3 = race.route.tangents[clampi(li, 0, race.route.tangents.size() - 1)]
		var fwd = -xf.basis.z
		log_("   grid car %d %s%s pos=%s off=%.2f heading_dot=%.3f lap=%d prog=%.1f spd=%.1f" % [c.car_id, c.key, " (YOU)" if c == fr.player else "", xf.origin, float(tt.line_offset), fwd.dot(tan), int(tt.lap), race.progress_of(c.car_id), float(tt.speed_kmh)])
	for i in range(cars.size()):
		for j in range(i + 1, cars.size()):
			var d: float = cars[i].global_position.distance_to(cars[j].global_position)
			if d < 3.5:
				log_("   GRID OVERLAP cars %d & %d only %.2f m apart" % [cars[i].car_id, cars[j].car_id, d])
	log_("   standings at grid: %s  player P%d" % [race.standings(), race.position_of(fr.player.car_id)])

# ---------------------------------------------------------------- scenarios

func sc_events() -> void:
	await wait_playing()
	var list: PackedStringArray = String(args.get("list", "route1_sprint")).split(",")
	for i in range(list.size()):
		var id = list[i]
		if i > 0 or not args.has("event"):
			await wait(2.0)
			log_("starting %s via start_event (from free roam at %s)" % [id, fr.player.global_position])
			fr.start_event(EventData.get_event(id))
		if args.has("autodrive_player"):
			pass
		# Autodrive for the player: freeroam only sets it when the 'autodrive' arg exists.
		await run_race(id)
	freeroam_checks("final")

## Grid formation only for each event launched via event= (no race).
func sc_grid() -> void:
	await wait_playing()
	var id: String = args.get("event", "")
	var t_start = Time.get_ticks_msec()
	await wait(0.2)
	await shot(id + "_launch_toast")
	while fr.race == null or fr.race.state != RaceManager.State.COUNTDOWN:
		await frames(1)
		if Time.get_ticks_msec() - t_start > 40000:
			log_("%s: NO COUNTDOWN" % id)
			return
	var race: RaceManager = fr.race
	log_("%s: countdown after %.2f s" % [id, (Time.get_ticks_msec() - t_start) / 1000.0])
	_log_grid(race)
	await shot(id + "_gridA")
	await wait(1.2)
	await shot(id + "_gridB")
	while race.state == RaceManager.State.COUNTDOWN:
		await frames(1)
	for c in race.cars:
		var tt = fr.sim.get_telemetry(c.car_id)
		log_("   car %d %s speed at GO %.1f km/h" % [c.car_id, c.key, float(tt.speed_kmh)])
	await wait(0.3)
	await shot(id + "_go")
	await wait(4.0)
	log_("%s after 4s: P%d, player spd %.1f" % [id, race.position_of(fr.player.car_id), float(fr.player.telemetry.speed_kmh)])
	await shot(id + "_4s")

func sc_pause() -> void:
	await wait_playing()
	await wait(3.0)
	log_("fps now %.1f" % Engine.get_frames_per_second())
	# 1) Esc tap in free roam (keyboard Start fallback).
	var opened = 0
	for trial in range(10):
		await tap(KEY_ESCAPE, 1)
		await frames(3)
		if pause_menus() > 0:
			opened += 1
			await tap(KEY_ESCAPE, 1)
			await frames(5)
			if pause_menus() > 0:
				log_("pause did not close with Esc (trial %d), menus=%d" % [trial, pause_menus()])
				pause_menu()._pick("resume")
				await frames(3)
		await frames(10)
	log_("PAUSE Esc tap(1 frame) opened %d/10 times at %.0f fps" % [opened, Engine.get_frames_per_second()])
	opened = 0
	for trial in range(10):
		await tap(KEY_ESCAPE, 6)
		await frames(3)
		if pause_menus() > 0:
			opened += 1
			if pause_menus() > 1:
				log_("DOUBLE pause menus: %d" % pause_menus())
			await tap(KEY_ESCAPE, 1)
			await frames(5)
			if pause_menus() > 0:
				log_("pause reopened/stayed after Esc resume (trial %d) menus=%d" % [trial, pause_menus()])
				pause_menu()._pick("resume")
				await frames(3)
		await frames(10)
	log_("PAUSE Esc hold(6 frames) opened %d/10 times" % opened)
	# 2) Open pause directly and screenshot.
	fr._open_pause()
	await frames(10)
	await shot("pause_freeroam")
	# Does pause freeze everything?
	var tod: float = fr.sky.time_of_day
	var sim_t: float = fr.sim.get_sim_time()
	var trafpos = fr.sim.traffic_buffer(0)
	var toast_t: float = fr.hud._toast_t
	var skill_t: float = fr.skills.combo_timer
	await wait(2.0)
	log_("while paused 2s: tod %.4f->%.4f sim_t %.3f->%.3f toast_t %.2f->%.2f traffic_same=%s" % [tod, fr.sky.time_of_day, sim_t, fr.sim.get_sim_time(), toast_t, fr.hud._toast_t, trafpos == fr.sim.traffic_buffer(0)])
	# Audio: are engine audio players still playing?
	_log_audio("paused")
	# ui navigation: down then accept on RECOVER CAR
	await action("ui_down")
	await frames(3)
	var fo = get_viewport().gui_get_focus_owner()
	log_("focus after ui_down: %s" % (fo.get("_title").text if fo and fo.get("_title") else str(fo)))
	await shot("pause_freeroam_focus2")
	await action("ui_accept")
	await frames(5)
	log_("after RECOVER: paused=%s menus=%d %s" % [get_tree().paused, pause_menus(), state_summary()])
	# ui_cancel closes
	fr._open_pause()
	await frames(5)
	await action("ui_cancel")
	await frames(5)
	log_("after ui_cancel: paused=%s menus=%d" % [get_tree().paused, pause_menus()])
	# Back button (Android) twice: opens, then second?
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(5)
	log_("after GO_BACK #1: paused=%s menus=%d" % [get_tree().paused, pause_menus()])
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(5)
	log_("after GO_BACK #2 (menu open): paused=%s menus=%d" % [get_tree().paused, pause_menus()])
	await shot("pause_after_back2")
	while pause_menus() > 0:
		pause_menu()._pick("resume")
		await frames(3)
	await frames(5)
	log_("closed all: paused=%s" % get_tree().paused)
	# 3) Mid-race pause: start the shortest event.
	fr.start_event(EventData.get_event(args.get("pevent", "route1_sprint")))
	while fr.race == null or fr.race.state != RaceManager.State.COUNTDOWN:
		await frames(1)
	await wait(1.0)
	# Pause during countdown.
	var cd: float = fr.race.countdown
	fr._open_pause()
	await frames(5)
	await shot("pause_countdown")
	await wait(1.5)
	log_("countdown while paused: %.3f -> %.3f" % [cd, fr.race.countdown])
	pause_menu()._pick("resume")
	while fr.race.state == RaceManager.State.COUNTDOWN:
		await frames(1)
	# Drive a bit with keyboard W.
	key(KEY_W, true)
	await wait(4.0)
	var rt: float = fr.race.race_time
	fr._open_pause()
	await frames(5)
	await shot("pause_race")
	_log_audio("race paused")
	var opts = []
	for r in pause_menu()._rows:
		opts.append(r._title.text)
	log_("race pause options: %s" % [opts])
	await wait(1.0)
	log_("race_time while paused: %.3f -> %.3f" % [rt, fr.race.race_time])
	# Restart event
	var ev_before: Dictionary = fr.race.event
	pause_menu()._pick("restart")
	await wait(0.2)
	log_("after restart pick: race=%s state=%s" % [fr.race, fr.race.state if fr.race else -1])
	var t0 = Time.get_ticks_msec()
	while (fr.race == null or fr.race.state != RaceManager.State.COUNTDOWN) and Time.get_ticks_msec() - t0 < 20000:
		await frames(1)
	log_("restart -> countdown: race=%s state=%s cars=%d sim cars=%d weather=%s saved_cond=%s" % [fr.race, fr.race.state if fr.race else -1, fr.race.cars.size() if fr.race else 0, fr.sim.car_count(), fr.sky.weather, fr._saved_conditions])
	await shot("pause_after_restart")
	key(KEY_W, false)
	# Quit event mid-countdown
	fr._open_pause()
	await frames(3)
	pause_menu()._pick("quit_event")
	await wait(1.0)
	freeroam_checks("after quit_event during countdown")
	await shot("pause_after_quit_event")
	# Restart during results? start a race, finish with autodrive, pause at results.
	if args.has("results_pause"):
		fr.start_event(EventData.get_event(args.get("pevent", "route1_sprint")))
		while fr.race == null or fr.race.state != RaceManager.State.COUNTDOWN:
			await frames(1)
		fr.sim.set_ai(fr.player.car_id, true)
		fr.sim.set_ai_difficulty(fr.player.car_id, 6)
		fast(3.0)
		while fr.race.state != RaceManager.State.RESULTS:
			await frames(1)
		fast(1.0)
		var credits = int(Profile.data.credits)
		var races = int(Profile.data.stats.races)
		fr._open_pause()
		await frames(5)
		await shot("pause_results")
		pause_menu()._pick("restart")
		await wait(0.5)
		log_("restart at results: credits delta %d races delta %d race=%s" % [int(Profile.data.credits) - credits, int(Profile.data.stats.races) - races, fr.race])
		var t1 = Time.get_ticks_msec()
		while (fr.race == null or fr.race.state != RaceManager.State.COUNTDOWN) and Time.get_ticks_msec() - t1 < 20000:
			await frames(1)
		await wait(1.0)
		await shot("pause_results_restarted")
		fr._open_pause()
		await frames(3)
		pause_menu()._pick("quit_event")
		await wait(1.0)
	# Festival from mid race.
	fr.start_event(EventData.get_event(args.get("pevent", "route1_sprint")))
	while fr.race == null or fr.race.state != RaceManager.State.COUNTDOWN:
		await frames(1)
	await wait(1.0)
	fr._open_pause()
	await frames(3)
	var dist0 = float(Profile.data.stats.distance_km)
	pause_menu()._pick(args.get("exit", "festival"))
	await wait(3.0)
	var cs = get_tree().current_scene
	log_("after exit to %s: scene=%s paused=%s distance_km %.3f->%.3f time_scale=%.2f" % [args.get("exit", "festival"), cs.name if cs else "null", get_tree().paused, dist0, float(Profile.data.stats.distance_km), Engine.time_scale])
	await shot("pause_exit_" + args.get("exit", "festival"))
	# Level up after coming back: does the stale Profile.level_up lambda error?
	Profile.add_xp(Profile.xp_for_level(int(Profile.data.level)) + 10)
	await frames(10)
	log_("level-up after leaving freeroam emitted (check for errors above)")

func _log_audio(tag: String) -> void:
	var playing = 0
	var total = 0
	for n in fr.find_children("*", "AudioStreamPlayer3D", true, false):
		total += 1
		if n.playing and not n.stream_paused:
			playing += 1
	for n in fr.find_children("*", "AudioStreamPlayer", true, false):
		total += 1
		if n.playing and not n.stream_paused:
			playing += 1
	log_("AUDIO %s: %d/%d players playing; process_mode of player car audio=%s" % [tag, playing, total, fr.player.audio.process_mode if fr.player.audio else -1])

func sc_beacon() -> void:
	await wait_playing()
	await wait(1.0)
	log_("garage entry: %s  pi=%s class=%s  level=%d" % [fr._entry.get("key", "-"), fr._entry.get("pi", "-"), CarData.class_label(int(fr._entry.get("pi", 0))) if not fr._entry.is_empty() else "-", int(Profile.data.level)])
	for m in fr.markers.markers:
		log_("beacon %s at %s dir %s" % [m.event.id, m.pos, m.dir])
	var ids: PackedStringArray = String(args.get("list", "docks_circuit,shuto_c1_night,wangan_duel")).split(",")
	for id in ids:
		var m: Dictionary = {}
		for mm in fr.markers.markers:
			if mm.event.id == id:
				m = mm
		if m.is_empty():
			log_("no beacon for %s" % id)
			continue
		# Drive into beacon from 60 m before at 50 km/h, brake.
		var start: Vector3 = m.pos - m.dir * 60.0
		var road = fr.world.nearest_road(start, 50.0)
		await teleport(road.position if not road.is_empty() else start, m.dir, 14.0)
		await wait(2.0)
		await shot("beacon_%s_approach" % id)
		key(KEY_S, true)
		var tw = 0.0
		while float(fr.player.telemetry.get("speed", 99.0)) > 1.0 and tw < 8.0:
			await frames(1)
			tw += get_process_delta_time()
		key(KEY_S, false)
		await frames(3)
		var d: float = fr.player.global_position.distance_to(m.pos)
		log_("%s: stopped %.1f m from beacon, prompt=%s toast='%s'" % [id, d, fr._prompt_event.get("id", "none"), fr.hud.toast_text])
		if fr._prompt_event.is_empty():
			await teleport(m.pos, m.dir, 0.0)
			await wait(1.0)
			log_("%s: teleported into beacon, prompt=%s toast='%s'" % [id, fr._prompt_event.get("id", "none"), fr.hud.toast_text])
		await shot("beacon_%s_prompt" % id)
		# Press A (Space = handbrake) with a short tap.
		var hits = 0
		for trial in range(5):
			await tap(KEY_SPACE, 2)
			await frames(2)
			if fr.race != null:
				hits += 1
				break
			if fr.hud.toast_text.find("ONLY") >= 0 or fr.hud.toast_text.find("REACH") >= 0:
				log_("%s refusal toast shown: '%s'" % [id, fr.hud.toast_text])
				await shot("beacon_%s_refusal_t0" % id)
				await wait(0.5)
				log_("%s 0.5 s later toast: '%s'" % [id, fr.hud.toast_text])
				await shot("beacon_%s_refusal_t05" % id)
				hits = -1
				break
		log_("%s: A-tap result: race=%s hits=%d" % [id, fr.race, hits])
		if fr.race == null and hits == 0:
			# try holding
			key(KEY_SPACE, true)
			await wait(0.5)
			key(KEY_SPACE, false)
			await frames(3)
			log_("%s: A-hold result: race=%s toast='%s'" % [id, fr.race, fr.hud.toast_text])
			await shot("beacon_%s_after_hold" % id)
		if fr.race != null:
			await wait(1.0)
			await shot("beacon_%s_started" % id)
			while fr.race != null and fr.race.state != RaceManager.State.COUNTDOWN:
				await frames(1)
			fr.race.abort()
			await wait(1.0)
			freeroam_checks("after beacon abort")

func sc_roam() -> void:
	await wait_playing()
	await wait(0.2)
	await shot("roam_spawn_t0")
	log_("spawn: " + state_summary())
	var p0: Vector3 = fr.player.global_position
	log_("spawn nearest road: %s  sea? %s" % [fr.world.nearest_road(p0, 50.0), fr.world.is_sea(p0.x, p0.z)])
	await wait(3.0)
	log_("3 s after spawn: moved %.2f m  %s" % [fr.player.global_position.distance_to(p0), state_summary()])
	# Traffic near player
	await _traffic_report("spawn")
	# Drive forward with W for 15 s, log district toasts and headlights.
	key(KEY_W, true)
	var t = 0.0
	var last_d = -2
	while t < 15.0:
		await wait(0.5)
		t += 0.5
		if fr._district != last_d:
			last_d = fr._district
			log_("district -> %s toast '%s'" % [fr.world.district_name(last_d), fr.hud.toast_text])
	key(KEY_W, false)
	log_("after 15 s drive: " + state_summary() + " lights_on=%s night=%.2f" % [fr.player.lights_on, fr.sky.night])
	await shot("roam_drive15")
	await _traffic_report("after drive")
	# Recover with Backspace (reset_car)
	var pb: Vector3 = fr.player.global_position
	await tap(KEY_BACKSPACE, 1)
	await frames(3)
	log_("reset_car tap(1): moved %.2f m" % fr.player.global_position.distance_to(pb))
	await tap(KEY_BACKSPACE, 6)
	await frames(3)
	log_("reset_car tap(6): moved %.2f m" % fr.player.global_position.distance_to(pb))
	# Fall in the sea: find a sea point near the spawn.
	var sea = Vector3.INF
	for r in range(60, 800, 40):
		for a in range(0, 360, 30):
			var q = p0 + Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a))) * r
			if fr.world.is_sea(q.x, q.z):
				sea = q
				break
		if sea != Vector3.INF:
			break
	log_("sea point %s" % sea)
	if sea != Vector3.INF:
		var xf = Transform3D(Basis(), Vector3(sea.x, 5.0, sea.z))
		fr.sim.reset_car(fr.player.car_id, xf, 0.0)
		fr.camera.snap()
		var tw = 0.0
		var minY = 99.0
		while tw < 8.0:
			await frames(1)
			tw += get_process_delta_time()
			minY = minf(minY, fr.player.global_position.y)
			if tw > 0.8 and tw < 0.9:
				await shot("roam_sea_fall")
		log_("sea fall: minY=%.2f final %s" % [minY, state_summary()])
		await shot("roam_after_sea")
	# Fall off world edge
	var b: Rect2 = fr.world.bounds()
	log_("world bounds %s" % b)
	# Spawn at every POI type spawn= check later via args. List POIs.
	var types = {}
	for p in fr.world.pois():
		types[p.type] = int(types.get(p.type, 0)) + 1
	log_("POI types: %s" % types)
	var pid = []
	for p in fr.world.pois():
		if p.type != 7:
			pid.append("%s(t%d)" % [p.id, p.type])
	log_("POIs: %s" % [pid])

func _traffic_report(tag: String) -> void:
	var near = []
	for m in range(6):
		var b = fr.sim.traffic_buffer(m)
		for i in range(0, b.size(), 16):
			var p = Vector3(b[i + 3], b[i + 7], b[i + 11])
			var d = p.distance_to(fr.player.global_position)
			if d < 120.0:
				near.append(snappedf(d, 0.1))
	near.sort()
	log_("traffic %s: active=%d within120m=%d nearest=%s" % [tag, fr.sim.traffic_active_count(), near.size(), near.slice(0, 5)])

func sc_activities() -> void:
	await wait_playing()
	await wait(1.0)
	var acts = fr.activities
	log_("activities: %d items, %d omamori" % [acts.items.size(), acts.omamori.size()])
	for it in acts.items:
		log_("  %s %s road=%s pos=%s" % [Activities.KIND_NAMES[it.kind], it.id, it.road, it.pos])
	var done = {}
	for it in acts.items:
		if done.has(it.kind):
			continue
		done[it.kind] = true
		var kind: int = it.kind
		var dir: Vector3 = it.dir
		match kind:
			Activities.Kind.SPEED_TRAP:
				await teleport(it.pos - dir * 150.0, dir, 45.0)
				key(KEY_W, true)
				var tw = 0.0
				while tw < 8.0 and fr.player.global_position.distance_to(it.pos) > 3.0:
					await frames(1); tw += get_process_delta_time()
				await wait(0.3)
				key(KEY_W, false)
				log_("SPEED TRAP: toast='%s' rec=%s" % [fr.hud.toast_text, Profile.data.records.get(it.id)])
				await shot("act_speed_trap")
			Activities.Kind.SPEED_ZONE:
				await teleport(it.pos - dir * 100.0, dir, 40.0)
				fr.sim.set_racing_line(fr.world.road_samples(it.road).centers, fr.world.road_samples(it.road).ups, fr.world.road_samples(it.road).width_left, fr.world.road_samples(it.road).width_right, false)
				fr.sim.set_ai(fr.player.car_id, true)
				fr.sim.set_ai_difficulty(fr.player.car_id, 6)
				var tw = 0.0
				while tw < 40.0 and fr.player.global_position.distance_to(it.end) > 30.0:
					await frames(1); tw += get_process_delta_time()
				await wait(1.5)
				log_("SPEED ZONE: active=%s toast='%s' rec=%s (took %.1f s)" % [not acts._active.is_empty(), fr.hud.toast_text, Profile.data.records.get(it.id), tw])
				await shot("act_speed_zone")
				fr.sim.set_ai(fr.player.car_id, false)
				fr.sim.clear_racing_line()
			Activities.Kind.DRIFT_ZONE:
				await teleport(it.pos - dir * 60.0, dir, 20.0)
				var rs = fr.world.road_samples(it.road)
				fr.sim.set_racing_line(rs.centers, rs.ups, rs.width_left, rs.width_right, false)
				fr.sim.set_ai(fr.player.car_id, true)
				fr.sim.set_ai_personality(fr.player.car_id, {"drift_style": true})
				fr.sim.set_ai_difficulty(fr.player.car_id, 5)
				var tw = 0.0
				var entered = false
				var maxchain = 0.0
				while tw < 60.0:
					await frames(1); tw += get_process_delta_time()
					if not acts._active.is_empty(): entered = true
					maxchain = maxf(maxchain, fr.skills.chain_points)
					if entered and acts._active.is_empty(): break
				await wait(0.3)
				log_("DRIFT ZONE: entered=%s maxchain=%.0f toast='%s' rec=%s t=%.1f" % [entered, maxchain, fr.hud.toast_text, Profile.data.records.get(it.id), tw])
				await shot("act_drift_zone")
				fr.sim.set_ai(fr.player.car_id, false)
				fr.sim.clear_racing_line()
			Activities.Kind.DANGER_SIGN:
				await teleport(it.pos - dir * 200.0, dir, 50.0)
				key(KEY_W, true)
				var tw = 0.0
				var armed = false
				var maxair = 0.0
				while tw < 12.0:
					await frames(1); tw += get_process_delta_time()
					if not acts._jump.is_empty(): armed = true
					maxair = maxf(maxair, float(fr.player.telemetry.get("airborne", 0.0)))
					if armed and acts._jump.is_empty(): break
				key(KEY_W, false)
				await wait(0.3)
				log_("DANGER SIGN: armed=%s maxair=%.2f toast='%s' rec=%s" % [armed, maxair, fr.hud.toast_text, Profile.data.records.get(it.id)])
				await shot("act_danger_sign")
	# Omamori
	if acts.omamori.size() > 0:
		var o: Dictionary = acts.omamori[0]
		var road = fr.world.nearest_road(o.pos, 200.0)
		log_("omamori %s at %s; nearest road %.1f m away" % [o.id, o.pos, road.position.distance_to(o.pos) if not road.is_empty() else -1.0])
		var dists = []
		for oo in acts.omamori:
			var rr = fr.world.nearest_road(oo.pos, 300.0)
			dists.append(snappedf(rr.position.distance_to(oo.pos), 0.1) if not rr.is_empty() else -1.0)
		log_("omamori road distances: %s" % [dists])
		await teleport(o.pos - Vector3(0, 1.5, 0) - Vector3(10, 0, 0), Vector3(1, 0, 0), 0.0)
		await wait(1.0)
		await shot("act_omamori_near")
		var n0: int = Profile.data.omamori.size()
		await teleport(o.pos - Vector3(0, 1.5, 0), Vector3(1, 0, 0), 0.0)
		await wait(0.5)
		log_("OMAMORI: count %d->%d toast='%s'" % [n0, Profile.data.omamori.size(), fr.hud.toast_text])
		await shot("act_omamori_pick")
	# Skills: drift chain ticker via handbrake turn at speed.
	var sk_road = fr.world.nearest_road(fr.player.global_position, 400.0)
	await teleport(sk_road.position, sk_road.tangent, 25.0)
	key(KEY_W, true)
	key(KEY_SPACE, true)
	key(KEY_D, true)
	await wait(0.6)
	key(KEY_SPACE, false)
	await wait(1.2)
	await shot("skills_ticker")
	log_("skills: chain=%.0f mult=%d recent=%s" % [fr.skills.chain_points, fr.skills.multiplier, fr.skills.recent])
	key(KEY_D, false)
	key(KEY_W, false)
	await wait(5.0)
	log_("skills after 5 s: chain=%.0f banked=%d toast='%s'" % [fr.skills.chain_points, fr.skills.total_banked, fr.hud.toast_text])

func sc_hud() -> void:
	await wait_playing()
	await wait(1.0)
	var road = fr.world.nearest_road(fr.player.global_position, 400.0)
	await teleport(road.position, road.tangent, 30.0)
	key(KEY_W, true)
	await wait(3.0)
	await shot("hud_driving_" + args.get("tag", "default"))
	key(KEY_W, false)
	fr.hud.toast("A — SHIBUYA STREET GP  (Circuit)", 3.0)
	await frames(2)
	await shot("hud_toast_" + args.get("tag", "default"))
	fr.hud.toast("SHUTO C1 MIDNIGHT — CLASS A OR LOWER ONLY (YOUR CAR: S1 812)", 3.0)
	await frames(2)
	await shot("hud_longtoast_" + args.get("tag", "default"))

func sc_conditions() -> void:
	await wait_playing()
	await wait(float(args.get("settle", "2")))
	log_("conditions: time=%.2f weather=%s night=%.2f fog=%.2f rain=%.2f lights_on=%s" % [fr.sky.time_of_day, SkyWeather.W_NAMES[fr.sky.weather], fr.sky.night, fr.sky.fog_amount, fr.sky.rain, fr.player.lights_on])
	await shot("cond_" + args.get("tag", "x"))
	if args.has("drive"):
		key(KEY_W, true)
		await wait(float(args.drive))
		key(KEY_W, false)
		await shot("cond_" + args.get("tag", "x") + "_drive")
		log_("after drive: " + state_summary())
		await _traffic_report("cond")

## Festival -> events screen -> launch (tests meta 'launch' with garage_index + event).
func sc_backnav() -> void:
	# Starts in festival hub; push events screen and accept first eligible event.
	await frames(30)
	var fest = get_tree().current_scene
	log_("festival scene %s" % fest)
	fest.drive({"event": args.get("fevent", "docks_circuit")})
	await frames(5)
	await wait_playing()
	log_("launch meta: %s  entry=%s" % [get_tree().root.get_meta("launch", {}), fr._entry.get("key", "-")])
	if args.has("race"):
		await run_race(args.get("fevent", "docks_circuit"), {"results_wait": 1.0})
	else:
		await wait(8.0)
	await shot("backnav_" + args.get("fevent", "docks_circuit"))
	freeroam_checks("backnav")
	# Exit to festival via pause, then drive again: does event auto-start again?
	fr._open_pause()
	await frames(3)
	pause_menu()._pick("festival")
	await wait(2.0)
	fest = get_tree().current_scene
	log_("back in festival: %s ; launch meta still %s" % [fest.name, get_tree().root.get_meta("launch", {})])
	await shot("backnav_festival_return")
	fest.drive()
	await frames(5)
	await wait_playing()
	await wait(3.0)
	log_("drive again: race=%s args.event=%s" % [fr.race, fr.args.get("event", "-")])
	await shot("backnav_drive_again")
	Profile.add_xp(Profile.xp_for_level(int(Profile.data.level)) + 10)
	await frames(10)
	log_("level-up after re-entering freeroam; toast='%s'" % fr.hud.toast_text)
	await shot("backnav_levelup")

func sc_ticks() -> void:
	await wait_playing()
	await wait(2.0)
	var hist = {}
	var last = Engine.get_physics_frames()
	for i in range(300):
		await get_tree().process_frame
		var now = Engine.get_physics_frames()
		var d = now - last
		last = now
		hist[d] = int(hist.get(d, 0)) + 1
	log_("physics ticks per process frame at %.0f fps: %s" % [Engine.get_frames_per_second(), hist])
	# Direct Pad edge visibility test from _process context
	var seq = []
	var cb_p = func(): seq.append("P%d%d" % [int(Pad.pressed("pause")), int(Input.is_key_pressed(KEY_ESCAPE))])
	var cb_f = func(): seq.append("F%d%d" % [int(Pad.pressed("pause")), int(get_tree().paused)])
	get_tree().physics_frame.connect(cb_p)
	get_tree().process_frame.connect(cb_f)
	await frames(3)
	seq.append("KEYDOWN")
	key(KEY_ESCAPE, true)
	await frames(1)
	seq.append("KEYUP")
	key(KEY_ESCAPE, false)
	await frames(4)
	get_tree().physics_frame.disconnect(cb_p)
	get_tree().process_frame.disconnect(cb_f)
	log_("sequence (P=physics_frame signal: pressed,keydown  F=process_frame: pressed,paused): %s" % [seq])
	if pause_menus() > 0:
		pause_menu()._pick("resume")
		await frames(3)
	# Same, but key down issued from a timer callback (after _process), like the pause scenario.
	seq.clear()
	get_tree().physics_frame.connect(cb_p)
	get_tree().process_frame.connect(cb_f)
	await wait(0.2)
	seq.append("KEYDOWN(timer)")
	key(KEY_ESCAPE, true)
	await frames(1)
	seq.append("KEYUP")
	key(KEY_ESCAPE, false)
	await frames(4)
	get_tree().physics_frame.disconnect(cb_p)
	get_tree().process_frame.disconnect(cb_f)
	log_("sequence timer-issued: %s  menus=%d" % [seq, pause_menus()])
	if pause_menus() > 0:
		pause_menu()._pick("resume")
		await frames(3)
	var seen = 0
	var opened = 0
	for trial in range(20):
		key(KEY_ESCAPE, true)
		var saw = false
		var trace = []
		for f in range(int(args.get("hold", "6"))):
			var pf0 = Engine.get_physics_frames()
			await get_tree().process_frame
			trace.append("%s/%s/%d" % [int(Pad.pressed("pause")), int(get_tree().paused), Engine.get_physics_frames() - pf0])
			if Pad.pressed("pause") and not get_tree().paused:
				saw = true
		key(KEY_ESCAPE, false)
		await frames(4)
		if pause_menus() > 0:
			opened += 1
			pause_menu()._pick("resume")
			await frames(3)
		if saw:
			seen += 1
		if trial < 5:
			log_("trial %d trace pressed/paused/ticks: %s" % [trial, trace])
		await frames(int(args.get("gap", "7")) + trial % 3)
	log_("Pad.pressed('pause') visible while unpaused on %d/20 presses; pause menu opened %d/20" % [seen, opened])

func sc_water() -> void:
	await wait_playing()
	var p = Vector3(float(args.get("wx", "2364")), 3.7, float(args.get("wz", "-7")))
	var dir = Vector3(float(args.get("dx", "0")), 0, float(args.get("dz", "1"))).normalized()
	await teleport(p, dir, 15.0)
	key(KEY_W, true)
	for i in range(24):
		await wait(0.5)
		var surf = []
		for w in range(4):
			surf.append(int(fr.player.wheel_value(w, 10)))
		var q = fr.player.global_position
		log_("t=%.1f pos=%s spd=%.1f surf=%s is_sea=%s h=%.2f nearest_road=%.1f m" % [i * 0.5, q, float(fr.player.telemetry.speed_kmh), surf, fr.world.is_sea(q.x, q.z), fr.world.height_at(q.x, q.z), fr.world.nearest_road(q, 400.0).get("distance", -1.0)])
		if i == 8:
			await shot("water_drive")
	key(KEY_W, false)

func sc_tunnel() -> void:
	await wait_playing()
	var probe = Vector3(float(args.get("tx", "-1472")), -4.0, float(args.get("tz", "169")))
	var road = fr.world.nearest_road(probe, 80.0)
	log_("nearest road to probe: %s" % road)
	var rs = fr.world.road_samples(road.road)
	var n = rs.centers.size()
	var lo = 1e9
	var lo_i = 0
	for i in range(n):
		if rs.centers[i].y < lo:
			lo = rs.centers[i].y
			lo_i = i
	log_("road %s: %d samples, min y %.2f at sample %d %s; samples below -3: %d" % [road.road, n, lo, lo_i, rs.centers[lo_i], Array(rs.centers).filter(func(c): return c.y < -1.8).size()])
	var k = maxi(0, int(road.sample) - int(args.get("back", "40")))
	await teleport(rs.centers[k], rs.tangents[k], 20.0)
	key(KEY_W, true)
	var last = Vector3.ZERO
	var jumps = 0
	for i in range(30):
		await wait(0.5)
		var p = fr.player.global_position
		if last != Vector3.ZERO and p.distance_to(last) < 0.05:
			jumps += 1
		last = p
		log_("t=%.1f pos=%s spd=%.0f" % [i * 0.5, p, float(fr.player.telemetry.get("speed_kmh", 0))])
		if i == 12:
			await shot("tunnel_drive")
	key(KEY_W, false)
	log_("frames without movement: %d" % jumps)
	await shot("tunnel_end")

func sc_refusal() -> void:
	await wait_playing()
	await wait(1.0)
	log_("entry %s pi %s level %d" % [fr._entry.get("key"), fr._entry.get("pi"), int(Profile.data.level)])
	for id in String(args.get("list", "docks_circuit")).split(","):
		var m = {}
		for mm in fr.markers.markers:
			if mm.event.id == id:
				m = mm
		await teleport(m.pos, m.dir, 0.0)
		await wait(1.0)
		log_("%s in beacon: prompt=%s toast='%s'" % [id, fr._prompt_event.get("id", "none"), fr.hud.toast_text])
		fr.start_event(m.event)
		log_("%s start_event called: race=%s toast='%s'" % [id, fr.race, fr.hud.toast_text])
		for i in range(6):
			await frames(1)
			log_("   frame %d toast='%s' t=%.2f" % [i + 1, fr.hud.toast_text, fr.hud._toast_t])
			if i == 0:
				await shot("refusal_%s_f1" % id)
		await wait(0.5)
		await shot("refusal_%s_later" % id)
		if fr.race != null:
			while fr.race.state != RaceManager.State.COUNTDOWN:
				await frames(1)
			fr.race.abort()
			await wait(1.0)

## Put the player near the end of an open route and see whether the finish triggers.
func sc_finishline() -> void:
	await wait_playing()
	var id: String = args.get("pevent", "akina_downhill")
	for mode in ["ai", "manual"]:
		fr.start_event(EventData.get_event(id))
		while fr.race == null or fr.race.state != RaceManager.State.COUNTDOWN:
			await frames(1)
		var race: RaceManager = fr.race
		while race.state == RaceManager.State.COUNTDOWN:
			await frames(1)
		var n = race.route.centers.size()
		var k = n - int(args.get("back", "60"))
		for c in race.cars:
			if c != fr.player:
				fr.sim.set_frozen(c.car_id, true)
		await teleport(race.route.centers[k], race.route.tangents[k], 12.0)
		if mode == "ai":
			fr.sim.set_ai(fr.player.car_id, true)
			fr.sim.set_ai_difficulty(fr.player.car_id, 4)
		else:
			key(KEY_W, true)
		var tw = 0.0
		var shot_done = false
		while tw < 25.0 and race.state == RaceManager.State.RACING:
			await wait(0.5)
			tw += 0.5
			var t = fr.sim.get_telemetry(fr.player.car_id)
			log_("%s %s t=%.1f pos=%s line_d=%.1f (finish %.1f) idx=%d/%d off=%.1f spd=%.0f rs=%d ww=%s" % [id, mode, tw, fr.player.global_position, float(t.line_distance), race.finish_distance, int(t.line_index), n, float(t.line_offset), float(t.speed_kmh), int(t.respawns), t.wrong_way])
			if mode == "manual":
				# crude steering toward the route tangent
				var li = clampi(int(t.line_index) + 4, 0, n - 1)
				var to = race.route.centers[li] - fr.player.global_position
				var fwd = -fr.player.global_basis.z
				var side = fwd.cross(to.normalized()).y
				key(KEY_A, side > 0.05)
				key(KEY_D, side < -0.05)
			if not shot_done and tw >= 6.0:
				shot_done = true
				await shot("finishline_%s_%s" % [id, mode])
		key(KEY_W, false)
		key(KEY_A, false)
		key(KEY_D, false)
		log_("%s %s: state=%s finish_order=%s" % [id, mode, race.state, race.finish_order])
		await shot("finishline_%s_%s_end" % [id, mode])
		race.abort()
		await wait(1.0)

func sc_routeinfo() -> void:
	await wait_playing()
	for ev in EventData.all():
		var r = Route.from_roads(fr.world, ev.roads, ev.closed)
		var n = r.centers.size()
		var gs = int(ev.rivals) + 1
		var si = r.start_index(gs)
		log_("ROUTE %s n=%d len=%.0f closed=%s start_idx=%d start=%s end=%s" % [ev.id, n, r.length, r.closed, si, r.centers[si], r.centers[n - 1]])
		# junction gaps / sharp tangent changes
		for i in range(1, n):
			var dd = r.centers[i].distance_to(r.centers[i - 1])
			var dt = r.tangents[i].dot(r.tangents[i - 1])
			if dd > 6.0 or dt < 0.8:
				log_("   %s seam at %d: step %.1f m tangent dot %.2f at %s" % [ev.id, i, dd, dt, r.centers[i]])
		if r.closed:
			log_("   %s loop closure gap %.1f m" % [ev.id, r.centers[n - 1].distance_to(r.centers[0])])
		else:
			var fin = r.length - 20.0
			var k = 0
			while k < n - 1 and r.distance[k] < fin:
				k += 1
			log_("   %s finish sample %d at %s ; last 12 samples:" % [ev.id, k, r.centers[k]])
			for i in range(maxi(0, n - 12), n):
				var c = r.centers[i]
				var road = fr.world.nearest_road(c, 30.0)
				log_("      %d d=%.0f c=%s h_terrain=%.2f wl=%.1f wr=%.1f road=%s" % [i, r.distance[i], c, fr.world.height_at(c.x, c.z), r.width_left[i], r.width_right[i], road.get("road", "-")])
		# Grid start samples for open routes
		for i in range(maxi(0, si - 20), mini(n, si + 3)):
			pass

func sc_misc() -> void:
	await wait_playing()
	await wait(1.0)
	# Rewind during race; recover in race; wrong-way driving.
	fr.start_event(EventData.get_event(args.get("pevent", "docks_circuit")))
	while fr.race == null or fr.race.state != RaceManager.State.COUNTDOWN:
		await frames(1)
	var race: RaceManager = fr.race
	while race.state == RaceManager.State.COUNTDOWN:
		await frames(1)
	# Drive backwards: turn around.
	var tan: Vector3 = race.route.tangents[int(fr.player.telemetry.get("line_index", 0))]
	var xf: Transform3D = fr.sim.get_transform(fr.player.car_id)
	fr.sim.reset_car(fr.player.car_id, Transform3D(Basis.looking_at(-tan, Vector3.UP), xf.origin + Vector3(0, 0.5, 0)), 0.0)
	key(KEY_W, true)
	await wait(6.0)
	key(KEY_W, false)
	var t = fr.sim.get_telemetry(fr.player.car_id)
	log_("WRONG WAY driving: wrong_way=%s lap=%d P%d prog=%.1f" % [t.wrong_way, int(t.lap), race.position_of(fr.player.car_id), race.progress_of(fr.player.car_id)])
	await shot("misc_wrong_way")
	# Recover mid-race (Backspace): where does it put us?
	var before: Vector3 = fr.player.global_position
	key(KEY_BACKSPACE, true)
	await wait(0.2)
	key(KEY_BACKSPACE, false)
	await frames(3)
	var t2 = fr.sim.get_telemetry(fr.player.car_id)
	log_("RECOVER mid-race: moved %.1f m, line_offset %.1f, heading vs route %.2f" % [before.distance_to(fr.player.global_position), float(t2.line_offset), (-fr.sim.get_transform(fr.player.car_id).basis.z).dot(race.route.tangents[int(t2.line_index)])])
	# Rewind: hold R 2 s; race_time keeps running?
	var rt = race.race_time
	key(KEY_R, true)
	await wait(2.0)
	await shot("misc_rewind")
	key(KEY_R, false)
	await frames(3)
	log_("REWIND 2 s: race_time %.2f -> %.2f" % [rt, race.race_time])
	# Leave the player parked: rivals all finish; does the race ever end?
	fast(4.0)
	var tw = 0.0
	while race.finish_order.size() < race.cars.size() - 1 and tw < 150.0:
		await frames(1)
		tw += get_process_delta_time()
	await wait(20.0)
	fast(1.0)
	log_("PARKED PLAYER: rivals finished %d/%d, state=%s race_time=%.1f" % [race.finish_order.size(), race.cars.size() - 1, race.state, race.race_time])
	await shot("misc_parked_after_rivals_finish")
	race.abort()
	await wait(1.0)
