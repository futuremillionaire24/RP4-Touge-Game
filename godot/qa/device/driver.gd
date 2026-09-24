extends Node

const OUT := "D:/Android_RP4_Game/build/qa/device/"
var mode := "perf"

func _ready() -> void:
	print("QA device mode=", mode, "  refresh=", DisplayServer.screen_get_refresh_rate(), "  vsync=", DisplayServer.window_get_vsync_mode(), "  cpu=", OS.get_processor_name(), " x", OS.get_processor_count())
	match mode:
		"perf": await _perf()
		"nav": await _nav()
		"freeroam": await _freeroam()
		"input": _input_map()
		"edges": await _edges()
	get_tree().quit()

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame

func _perf_line(tag: String) -> void:
	print("PERF %-10s fps=%.1f avg=%.2f low=%.2f scale=%.2f level=%d vp_scale=%.2f thermal=%.2f" % [tag, Perf.fps, Perf.avg_ms, Perf.low1_ms, Perf.scale, Perf.level, get_viewport().scaling_3d_scale, Perf.thermal])

func _sample(tag: String, secs: int) -> void:
	for i in range(secs):
		await _secs(1.0)
		_perf_line("%s+%ds" % [tag, i + 1])

func _perf() -> void:
	Settings.set_value("graphics", "fps_target", 60)
	# Emulate the RP4's 60 Hz vsync'd panel on this 75 Hz monitor: vsync off + 60 FPS cap.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	print("PERF emulating 60 Hz panel: vsync off, Engine.max_fps=60")
	await _sample("idle", 6)
	print("PERF injecting 12 frames of 45 ms hitch (shader compile / streaming spike)")
	for i in range(12):
		OS.delay_msec(45)
		await get_tree().process_frame
	await _sample("after", 16)
	print("PERF switching fps_target=40")
	Settings.set_value("graphics", "fps_target", 40)
	await _sample("fps40", 14)
	Settings.set_value("graphics", "fps_target", 60)
	await _sample("back60", 6)

var _seen_process := 0
var _seen_physics := 0
var _counting := false

func _process(_d: float) -> void:
	if _counting and Pad.pressed("pause"):
		_seen_process += 1

func _physics_process(_d: float) -> void:
	if _counting and Pad.pressed("pause"):
		_seen_physics += 1

## Taps Esc (Pad "pause", same edge logic as Start) 40 times at an emulated 60 FPS and counts
## how many edges a _process() consumer (freeroam pause / reset / event start) actually sees.
func _edges() -> void:
	var cap := 60
	for a in OS.get_cmdline_user_args():
		if a.begins_with("cap="):
			cap = int(a.substr(4))
	if cap > 0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = cap
	await _secs(1.0)
	process_physics_priority = 100
	_counting = true
	var taps := 40
	for i in range(taps):
		var k := InputEventKey.new()
		k.keycode = KEY_ESCAPE
		k.physical_keycode = KEY_ESCAPE
		k.pressed = true
		Input.parse_input_event(k)
		await _frames(4)
		var ku := InputEventKey.new()
		ku.keycode = KEY_ESCAPE
		ku.physical_keycode = KEY_ESCAPE
		ku.pressed = false
		Input.parse_input_event(ku)
		await _frames(4 + (i % 3))
	_counting = false
	print("EDGES taps=%d  seen_in_physics=%d  seen_in_process=%d  (physics %d Hz, fps %d)" % [taps, _seen_physics, _seen_process, Engine.physics_ticks_per_second, Engine.get_frames_per_second()])

func _input_map() -> void:
	for a in ["ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_page_up"]:
		var evs := []
		for e in InputMap.action_get_events(a):
			evs.append(e.as_text())
		print("INPUTMAP ", a, " -> ", ", ".join(evs))

func _back() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(10)

func _action(a: String) -> void:
	var e := InputEventAction.new()
	e.action = a
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	var r := InputEventAction.new()
	r.action = a
	r.pressed = false
	Input.parse_input_event(r)
	await _frames(8)

func _joy(button: int) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	var r := InputEventJoypadButton.new()
	r.device = 0
	r.button_index = button
	r.pressed = false
	Input.parse_input_event(r)
	await _frames(8)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("SHOT ", name)

func _scene_desc() -> String:
	var s := get_tree().current_scene
	if s == null:
		return "<none>"
	var d := s.name
	if s.has_method("top") and s.top() != null:
		d += " top=" + s.top().get_script().get_global_name()
	return d

func _nav() -> void:
	# Festival title.
	get_tree().change_scene_to_file("res://scenes/festival.tscn")
	await _secs(2.0)
	print("NAV festival: ", _scene_desc())
	await _back()
	print("NAV festival after BACK: ", _scene_desc())
	await _joy(JOY_BUTTON_A)
	var title = get_tree().current_scene.top()
	print("NAV title menu visible after A: ", title._menu.visible)
	await _back()
	print("NAV title menu visible after BACK: ", title._menu.visible)
	var f0 = get_viewport().gui_get_focus_owner()
	print("NAV focus after menu open: ", f0._title.text if f0 and "_title" in f0 else str(f0))
	await _joy(JOY_BUTTON_DPAD_DOWN)
	var f1 = get_viewport().gui_get_focus_owner()
	print("NAV focus after joy D-pad down: ", f1._title.text if f1 and "_title" in f1 else str(f1))
	await _joy(JOY_BUTTON_DPAD_UP)
	print("NAV pressing joypad A (JOY_BUTTON_A) on focused row...")
	await _joy(JOY_BUTTON_A)
	await _frames(20)
	print("NAV after joypad A on NEW FESTIVAL: ", _scene_desc())
	await _joy(JOY_BUTTON_B)
	print("NAV title menu visible after joypad B: ", title._menu.visible)
	await _action("ui_cancel")
	print("NAV title menu visible after ui_cancel action: ", title._menu.visible)
	await _joy(JOY_BUTTON_A)
	await _action("ui_accept")
	await _frames(20)
	print("NAV after ui_accept ACTION on NEW FESTIVAL: ", _scene_desc())
	await _joy(JOY_BUTTON_B)
	await _frames(20)
	print("NAV after joypad B on starter screen: ", _scene_desc())
	# Launcher (reachable from title -> DEVELOPER TOOLS).
	get_tree().change_scene_to_file("res://scenes/launcher.tscn")
	await _secs(1.0)
	await _shot("launcher")
	print("NAV launcher: ", _scene_desc())
	await _back()
	await _action("ui_cancel")
	await _joy(JOY_BUTTON_B)
	print("NAV launcher after BACK + ui_cancel + B: ", _scene_desc())
	# Input test.
	get_tree().change_scene_to_file("res://scenes/input_test.tscn")
	await _secs(1.0)
	await _shot("input_test")
	await _back()
	await _action("ui_cancel")
	await _joy(JOY_BUTTON_B)
	print("NAV input_test after BACK + ui_cancel + B: ", _scene_desc())

func _freeroam() -> void:
	get_tree().root.set_meta("launch", {"car": "sylph_s2"})
	var t0 := Time.get_ticks_msec()
	get_tree().change_scene_to_file("res://scenes/freeroam.tscn")
	await _frames(2)
	var fr = get_tree().current_scene
	var last := ""
	var t_build := -1
	while fr._state != "playing" and Time.get_ticks_msec() - t0 < 120000:
		if fr._state != last:
			if last == "building":
				t_build = Time.get_ticks_msec() - t0
			last = fr._state
		await get_tree().process_frame
	var t_play := Time.get_ticks_msec() - t0
	print("FREEROAM world build %d ms, playable after %d ms (state=%s)" % [t_build, t_play, fr._state])
	await _secs(5.0)
	_perf_line("freeroam")
	await _shot("freeroam_hud")
	var prof := ProjectSettings.globalize_path(Profile.PATH)
	var m0 := FileAccess.get_modified_time(Profile.PATH)
	await _secs(1.2)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_PAUSED)
	await _frames(5)
	print("LIFECYCLE after APPLICATION_PAUSED: tree.paused=%s  profile saved=%s (%s)" % [get_tree().paused, FileAccess.get_modified_time(Profile.PATH) != m0, prof])
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(5)
	print("LIFECYCLE after FOCUS_OUT: tree.paused=", get_tree().paused)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_RESUMED)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames(5)
	await _back()
	print("BACK #1 in freeroam: tree.paused=", get_tree().paused)
	await _shot("freeroam_pause")
	await _back()
	print("BACK #2 while pause menu open: tree.paused=", get_tree().paused)
	# Open the pause menu the keyboard way (Esc = Pad "pause") to test pad input inside it.
	var k := InputEventKey.new()
	k.keycode = KEY_ESCAPE
	k.physical_keycode = KEY_ESCAPE
	k.pressed = true
	Input.parse_input_event(k)
	await _frames(4)
	var ku := InputEventKey.new()
	ku.keycode = KEY_ESCAPE
	ku.physical_keycode = KEY_ESCAPE
	ku.pressed = false
	Input.parse_input_event(ku)
	await _frames(10)
	print("Esc (Pad pause): tree.paused=", get_tree().paused)
	await _shot("freeroam_pause_menu")
	await _back()
	print("BACK while pause menu open: tree.paused=", get_tree().paused)
	await _joy(JOY_BUTTON_B)
	print("joypad B while pause menu open: tree.paused=", get_tree().paused)
	await _joy(JOY_BUTTON_DPAD_DOWN)
	await _joy(JOY_BUTTON_A)
	print("joypad A on 'RECOVER CAR' while pause menu open: tree.paused=", get_tree().paused)
	await _action("ui_cancel")
	print("ui_cancel while pause menu open: tree.paused=", get_tree().paused)
	await _secs(8.0)
	_perf_line("freeroam2")
