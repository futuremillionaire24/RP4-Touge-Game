class_name Festival
extends Node3D
## Festival front end: the car stage in 3D, a persistent top bar (level / XP / credits /
## Omikuji draws) and a stack of pad-navigable MenuScreens. Entry: title screen, or a screen
## named in the "festival_screen" root meta when returning from the world.
## Test args (after --): ui_shot=<dir> walks every screen and saves screenshots, then quits.

var stage: CarStage
var ui: CanvasLayer
var _stack: Array[MenuScreen] = []
var _top_bar: Control
var _lv_label: Label
var _xp_bar: ProgressBar
var _credits_label: Label
var _draws_label: Label
var _toast: Label
var _toast_time := 0.0
var _modal: Control
var args := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	stage = CarStage.new()
	add_child(stage)
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	root.name = "Root"
	ui.add_child(root)
	# Left-side legibility gradient over the 3D stage.
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.03, 0.05, 0.7))
	g.set_color(1, Color(0.03, 0.03, 0.05, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.position = Vector2.ZERO
	grad.size = Vector2(900, 750)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grad)
	_build_top_bar(root)
	_toast = UIKit.label("", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "heavy")
	_toast.position = Vector2(0, 640)
	_toast.size = Vector2(1334, 40)
	root.add_child(_toast)
	Profile.changed.connect(_refresh_top_bar)
	Profile.level_up.connect(func(lv): toast("FESTIVAL LEVEL %d  ·  +1 WHEELSPIN" % lv))
	_refresh_top_bar()
	AudioMix.set_tunnel(false)
	var start: String = get_tree().root.get_meta("festival_screen", "title")
	get_tree().root.remove_meta("festival_screen")
	if args.has("ui_shot"):
		_run_ui_shots(args.ui_shot)
		return
	if start == "hub" and bool(Profile.data.onboarded):
		push(HubScreen.new())
	else:
		push(TitleScreen.new())

func root_control() -> Control:
	return ui.get_node("Root")

# ---- Top bar ---------------------------------------------------------------------------------

func _build_top_bar(root: Control) -> void:
	_top_bar = Control.new()
	_top_bar.position = Vector2(0, 0)
	_top_bar.size = Vector2(1334, 60)
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_top_bar)
	# Dark fade behind the top row so tabs / level / credits read against a bright sky.
	var shade := TextureRect.new()
	var st := GradientTexture2D.new()
	var sg := Gradient.new()
	sg.set_color(0, Color(0, 0, 0, 0.55))
	sg.set_color(1, Color(0, 0, 0, 0.0))
	st.gradient = sg
	st.fill_from = Vector2(0.5, 0.0)
	st.fill_to = Vector2(0.5, 1.0)
	shade.texture = st
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.position = Vector2.ZERO
	shade.size = Vector2(1334, 96)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(shade)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	h.alignment = BoxContainer.ALIGNMENT_END
	h.position = Vector2(560, 16)
	h.size = Vector2(740, 36)
	_top_bar.add_child(h)
	_lv_label = UIKit.label("", 22, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, "heavy")
	h.add_child(_lv_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(150, 8)
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.show_percentage = false
	h.add_child(_xp_bar)
	_draws_label = UIKit.label("", 22, UIKit.AMBER, HORIZONTAL_ALIGNMENT_LEFT, "heavy")
	h.add_child(_draws_label)
	_credits_label = UIKit.label("", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, "heavy")
	h.add_child(_credits_label)

func _refresh_top_bar() -> void:
	if _lv_label == null:
		return
	var lv := int(Profile.data.level)
	_lv_label.text = "FESTIVAL LV %d" % lv
	_xp_bar.max_value = Profile.xp_for_level(lv)
	_xp_bar.value = int(Profile.data.xp)
	var draws := int(Profile.data.omikuji)
	_draws_label.text = "WHEELSPIN ×%d" % draws if draws > 0 else ""
	_credits_label.text = UIKit.money(int(Profile.data.credits))

func set_top_bar_visible(v: bool) -> void:
	_top_bar.visible = v

# ---- Screen stack ------------------------------------------------------------------------------

var _modal_open_time := 0

func push(screen: MenuScreen) -> void:
	if modal_open():
		_close_modal()
	if not _stack.is_empty():
		var prev: MenuScreen = _stack.back()
		prev.leave()
		prev.visible = false
		prev.process_mode = Node.PROCESS_MODE_DISABLED
	screen.festival = self
	screen.stage = stage
	screen.process_mode = Node.PROCESS_MODE_INHERIT
	root_control().add_child(screen)
	root_control().move_child(_toast, -1)
	_stack.append(screen)
	screen.enter()

func pop() -> void:
	if modal_open():
		_close_modal()
	if _stack.size() <= 1:
		return
	var s: MenuScreen = _stack.pop_back()
	s.leave()
	s.visible = false
	s.process_mode = Node.PROCESS_MODE_DISABLED
	s.queue_free()
	var current: MenuScreen = _stack.back()
	current.process_mode = Node.PROCESS_MODE_INHERIT
	current.visible = true
	current.enter()

## Replace the whole stack with one screen (e.g. title -> hub).
func reset_to(screen: MenuScreen) -> void:
	if modal_open():
		_close_modal()
	for s in _stack:
		s.leave()
		s.visible = false
		s.process_mode = Node.PROCESS_MODE_DISABLED
		s.queue_free()
	_stack.clear()
	push(screen)

func top() -> MenuScreen:
	return null if _stack.is_empty() else _stack.back()

# ---- Toast / modal ------------------------------------------------------------------------------

func toast(text: String, seconds := 2.5) -> void:
	_toast.text = text
	_toast_time = seconds
	_toast.modulate.a = 1.0

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time / 0.4, 0.0, 1.0)

func modal_open() -> bool:
	return _modal != null and is_instance_valid(_modal)

## Modal choice dialog. options = [[label, callable], ...]; B picks the last option.
func choose(title: String, body: String, options: Array) -> void:
	if modal_open():
		_close_modal()
	var prev_focus := get_viewport().gui_get_focus_owner()
	var current_top := top()
	if current_top != null:
		current_top.process_mode = Node.PROCESS_MODE_DISABLED
	_modal_open_time = Time.get_ticks_msec()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control().add_child(dim)
	_modal = dim
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	dim.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UIKit.label(title.to_upper(), 26, UIKit.NEON))
	if body != "":
		var b := UIKit.label(body, 19, UIKit.TEXT)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(528, 0)
		v.add_child(b)
	var buttons: Array[UIRow] = []
	for o in options:
		var row := UIRow.new(o[0])
		var cb: Callable = o[1]
		row.on_accept = func():
			if Time.get_ticks_msec() - _modal_open_time < 200:
				return
			_close_modal(prev_focus, current_top)
			if cb.is_valid():
				cb.call()
		v.add_child(row)
		buttons.append(row)
	var cancel: Callable = options.back()[1]
	dim.gui_input.connect(func(_e): pass)
	dim.set_meta("cancel", func():
		_close_modal(prev_focus, current_top)
		if cancel.is_valid():
			cancel.call())
	await get_tree().process_frame
	panel.position = (Vector2(1334, 750) - panel.size) * 0.5
	for i in range(buttons.size()):
		var b := buttons[i]
		var prev_btn := buttons[(i - 1 + buttons.size()) % buttons.size()]
		var next_btn := buttons[(i + 1) % buttons.size()]
		b.focus_neighbor_top = prev_btn.get_path()
		b.focus_neighbor_bottom = next_btn.get_path()
		b.focus_neighbor_left = b.get_path()
		b.focus_neighbor_right = b.get_path()
	if not buttons.is_empty():
		buttons[0].grab_focus()
	UIKit.fade_in(panel, 0.0)

func _close_modal(prev_focus: Control = null, bg_screen: MenuScreen = null) -> void:
	if bg_screen != null and is_instance_valid(bg_screen):
		bg_screen.process_mode = Node.PROCESS_MODE_INHERIT
	elif top() != null:
		top().process_mode = Node.PROCESS_MODE_INHERIT
	if modal_open():
		_modal.queue_free()
		_modal = null
	if prev_focus and is_instance_valid(prev_focus) and prev_focus.is_visible_in_tree() and (top() == bg_screen or bg_screen == null):
		prev_focus.call_deferred("grab_focus")

func _notification(what: int) -> void:
	# Android back button: close the dialog or go back one screen.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if modal_open():
			(_modal.get_meta("cancel") as Callable).call()
		elif top():
			top().back()

func _unhandled_input(event: InputEvent) -> void:
	if modal_open() and event.is_action_pressed("ui_cancel"):
		var c: Callable = _modal.get_meta("cancel")
		c.call()
		get_viewport().set_input_as_handled()

# ---- Transitions to gameplay -------------------------------------------------------------------

func drive(extra := {}) -> void:
	var launch := Profile.drive_args()
	for k in extra:
		launch[k] = extra[k]
	get_tree().root.set_meta("launch", launch)
	Haptics.clear()
	get_tree().change_scene_to_file("res://scenes/freeroam.tscn")

# ---- Automated UI walkthrough (screenshots) -----------------------------------------------------

func _run_ui_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	if Profile.data.garage.is_empty():
		Profile.choose_starter("bmw_m3_e30")
		Profile.add_car("porsche_930", "test", false)
		Profile.data.omikuji = 2
	var shots := [
		["title", func(): push(TitleScreen.new())],
		["starter", func(): reset_to(StarterScreen.new())],
		["hub", func(): reset_to(HubScreen.new())],
		["hub_cars", func(): top().tab(1)],
		["hub_festival", func(): top().tab(1)],
		["events", func(): push(EventsScreen.new())],
		["garage", func(): reset_to(GarageScreen.new())],
		["upgrades", func(): push(UpgradeScreen.new(Profile.current_index()))],
		["tuning", func(): reset_to(TuningScreen.new(Profile.current_index()))],
		["paint", func(): reset_to(PaintScreen.new(Profile.current_index()))],
		["dealer", func(): reset_to(DealerScreen.new())],
		["omikuji", func(): reset_to(OmikujiScreen.new())],
		["records", func(): reset_to(RecordsScreen.new())],
		["settings", func(): reset_to(SettingsScreen.new())],
		["credits", func(): reset_to(CreditsScreen.new())],
	]
	for s in shots:
		s[1].call()
		for i in range(40):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("ui_%s.png" % s[0]))
		print("UI SHOT ", s[0])
	get_tree().quit()
