extends MenuScreen
## In-Game Controller Configuration & Live Hardware Tester
## Designed specifically for Retroid Pocket 4 Pro & external gamepads.
## Provides real-time button/axis visualizer, quick presets (ABXY swap, bumper driving),
## and interactive single-click remapping for every driving action.

var _list: VBoxContainer
var _status_lbl: Label
var _preset_row: UIRow
var _remapping_action := ""
var _remap_modal: Control
var _remap_lbl: Label

# Live tester UI elements
var _tester_box: PanelContainer
var _btn_labels: Dictionary = {}
var _stick_l_dot: ColorRect
var _stick_r_dot: ColorRect
var _stick_l_txt: Label
var _stick_r_txt: Label
var _trigger_l_bar: ProgressBar
var _trigger_r_bar: ProgressBar
var _rows_by_action: Dictionary = {}

func build() -> void:
	var col := make_column(580, 70.0)
	col.add_child(UIKit.header("Controller Setup", "", "RP4 Pro & Gamepad Remapper"))

	_status_lbl = UIKit.label("", 16, UIKit.CYAN)
	col.add_child(_status_lbl)

	# Quick Presets Selector
	_preset_row = UIRow.new("Controller Preset")
	_preset_row.set_value("RP4 Default", UIKit.NEON)
	_preset_row.on_adjust = _cycle_preset
	_preset_row.on_accept = _cycle_preset.bind(1)
	col.add_child(_preset_row)

	# Remap list
	_list = make_list(col, 460)

	_build_live_tester()
	_build_remap_modal()

	set_hints([["A", "Remap / Adjust"], ["◀▶", "Preset"], ["X", "Reset Defaults"], ["B", "Back"]])

func _build_live_tester() -> void:
	# Right-side live gamepad hardware monitor
	_tester_box = PanelContainer.new()
	_tester_box.position = Vector2(650, 80)
	_tester_box.size = Vector2(640, 580)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.07, 0.92)
	sb.border_color = Color(0.15, 0.91, 1.0, 0.4)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_top = 16
	sb.content_margin_right = 16
	sb.content_margin_bottom = 16
	_tester_box.add_theme_stylebox_override("panel", sb)
	add_child(_tester_box)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_tester_box.add_child(vb)

	var title := UIKit.label("LIVE HARDWARE MONITOR", 18, UIKit.NEON)
	vb.add_child(title)

	var desc := UIKit.label("Press any button or move sticks/triggers to verify hardware detection.", 13, UIKit.DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(desc)

	# Triggers row
	var trig_hdr := UIKit.label("HALL ANALOG TRIGGERS (L2 / R2)", 14, UIKit.CYAN)
	vb.add_child(trig_hdr)

	var trig_grid := GridContainer.new()
	trig_grid.columns = 2
	trig_grid.add_theme_constant_override("h_separation", 20)
	vb.add_child(trig_grid)

	var l2_box := VBoxContainer.new()
	l2_box.add_child(UIKit.label("Left Trigger (LT / L2)", 13, UIKit.TEXT))
	_trigger_l_bar = ProgressBar.new()
	_trigger_l_bar.custom_minimum_size = Vector2(280, 16)
	_trigger_l_bar.show_percentage = true
	l2_box.add_child(_trigger_l_bar)
	trig_grid.add_child(l2_box)

	var r2_box := VBoxContainer.new()
	r2_box.add_child(UIKit.label("Right Trigger (RT / R2)", 13, UIKit.TEXT))
	_trigger_r_bar = ProgressBar.new()
	_trigger_r_bar.custom_minimum_size = Vector2(280, 16)
	_trigger_r_bar.show_percentage = true
	r2_box.add_child(_trigger_r_bar)
	trig_grid.add_child(r2_box)

	# Sticks row
	var stick_hdr := UIKit.label("HALL ANALOG THUMBSTICKS (L / R)", 14, UIKit.CYAN)
	vb.add_child(stick_hdr)

	var sticks_h := HBoxContainer.new()
	sticks_h.add_theme_constant_override("separation", 40)
	vb.add_child(sticks_h)

	# Left stick visual box
	var l_stick_box := VBoxContainer.new()
	l_stick_box.add_child(UIKit.label("Left Stick (Steer)", 13, UIKit.TEXT))
	var l_bg := ColorRect.new()
	l_bg.custom_minimum_size = Vector2(100, 100)
	l_bg.color = Color(0.08, 0.08, 0.12)
	_stick_l_dot = ColorRect.new()
	_stick_l_dot.size = Vector2(12, 12)
	_stick_l_dot.color = UIKit.NEON
	_stick_l_dot.position = Vector2(44, 44)
	l_bg.add_child(_stick_l_dot)
	l_stick_box.add_child(l_bg)
	_stick_l_txt = UIKit.label("X: 0.00  Y: 0.00", 12, UIKit.DIM)
	l_stick_box.add_child(_stick_l_txt)
	sticks_h.add_child(l_stick_box)

	# Right stick visual box
	var r_stick_box := VBoxContainer.new()
	r_stick_box.add_child(UIKit.label("Right Stick (Camera)", 13, UIKit.TEXT))
	var r_bg := ColorRect.new()
	r_bg.custom_minimum_size = Vector2(100, 100)
	r_bg.color = Color(0.08, 0.08, 0.12)
	_stick_r_dot = ColorRect.new()
	_stick_r_dot.size = Vector2(12, 12)
	_stick_r_dot.color = UIKit.CYAN
	_stick_r_dot.position = Vector2(44, 44)
	r_bg.add_child(_stick_r_dot)
	r_stick_box.add_child(r_bg)
	_stick_r_txt = UIKit.label("X: 0.00  Y: 0.00", 12, UIKit.DIM)
	r_stick_box.add_child(_stick_r_txt)
	sticks_h.add_child(r_stick_box)

	# Buttons matrix
	var btn_hdr := UIKit.label("HARDWARE BUTTON STATES", 14, UIKit.CYAN)
	vb.add_child(btn_hdr)

	var btn_flow := HFlowContainer.new()
	btn_flow.add_theme_constant_override("h_separation", 8)
	btn_flow.add_theme_constant_override("v_separation", 6)
	vb.add_child(btn_flow)

	var btns := [
		[JOY_BUTTON_A, "A"], [JOY_BUTTON_B, "B"], [JOY_BUTTON_X, "X"], [JOY_BUTTON_Y, "Y"],
		[JOY_BUTTON_LEFT_SHOULDER, "L1"], [JOY_BUTTON_RIGHT_SHOULDER, "R1"],
		[JOY_BUTTON_LEFT_STICK, "L3"], [JOY_BUTTON_RIGHT_STICK, "R3"],
		[JOY_BUTTON_DPAD_UP, "D-Up"], [JOY_BUTTON_DPAD_DOWN, "D-Down"],
		[JOY_BUTTON_DPAD_LEFT, "D-Left"], [JOY_BUTTON_DPAD_RIGHT, "D-Right"],
		[JOY_BUTTON_BACK, "Select"], [JOY_BUTTON_START, "Start"]
	]

	for b_def in btns:
		var p := PanelContainer.new()
		var p_sb := StyleBoxFlat.new()
		p_sb.bg_color = Color(0.12, 0.12, 0.16)
		p_sb.set_corner_radius_all(4)
		p_sb.content_margin_left = 8
		p_sb.content_margin_right = 8
		p_sb.content_margin_top = 4
		p_sb.content_margin_bottom = 4
		p.add_theme_stylebox_override("panel", p_sb)
		var lbl := Label.new()
		lbl.text = b_def[1]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		p.add_child(lbl)
		btn_flow.add_child(p)
		_btn_labels[b_def[0]] = {"label": lbl, "panel": p, "base_sb": p_sb}

func _build_remap_modal() -> void:
	_remap_modal = Control.new()
	_remap_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_remap_modal.visible = false
	_remap_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_remap_modal)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.0, 0.03, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_remap_modal.add_child(dim)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(500, 200)
	box.position = Vector2(417, 275)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.09)
	sb.border_color = UIKit.NEON
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 24
	sb.content_margin_top = 24
	sb.content_margin_right = 24
	sb.content_margin_bottom = 24
	box.add_theme_stylebox_override("panel", sb)
	_remap_modal.add_child(box)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)

	var hdr := UIKit.label("REMAP INPUT ACTION", 20, UIKit.NEON, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(hdr)

	_remap_lbl = UIKit.label("", 16, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_remap_lbl)

	var cancel_hint := UIKit.label("Press [B Button] or [Escape] to cancel", 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(cancel_hint)

func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows_by_action.clear()

	var state := Pad.raw_state()
	if Pad.has_pad:
		_status_lbl.text = "CONNECTED: %s (Device %d)" % [state.name, state.device]
		_status_lbl.add_theme_color_override("font_color", UIKit.GREEN)
	else:
		_status_lbl.text = "NO GAMEPAD DETECTED — KEYBOARD FALLBACK ACTIVE"
		_status_lbl.add_theme_color_override("font_color", UIKit.AMBER)

	var first: UIRow = null
	for act in Pad.ACTIONS:
		var name_str: String = Pad.ACTION_LABELS.get(act, act.capitalize())
		var row := UIRow.new(name_str)
		row.set_value(Pad.binding_string(act), UIKit.CYAN)
		row.on_accept = _start_remap.bind(act)
		_list.add_child(row)
		_rows_by_action[act] = row
		if first == null:
			first = row

	if first and is_inside_tree():
		first.call_deferred("grab_focus")

func _cycle_preset(dir: int) -> void:
	var keys := Pad.PRESETS.keys()
	var current_idx := 0
	# Pick next preset
	var next_idx: int = wrapi(current_idx + dir, 0, keys.size())
	var key: String = keys[next_idx]
	Pad.apply_preset(key)
	Settings.save_settings()
	_preset_row.set_value(Pad.PRESETS[key].name, UIKit.NEON)
	if festival != null:
		festival.toast("APPLIED PRESET: %s" % Pad.PRESETS[key].name.to_upper())
	refresh()

func _start_remap(action: String) -> void:
	_remapping_action = action
	_remap_lbl.text = "Press any button or pull trigger/stick for:\n%s" % Pad.ACTION_LABELS.get(action, action)
	_remap_modal.visible = true

func _input(event: InputEvent) -> void:
	if _remapping_action != "":
		# Cancel remap on B or Escape
		if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
			get_viewport().set_input_as_handled()
			_finish_remap(null)
			return
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_finish_remap(null)
			return

		# Joypad button press
		if event is InputEventJoypadButton and event.pressed:
			get_viewport().set_input_as_handled()
			_finish_remap({"button": event.button_index})
			return

		# Joypad trigger / stick motion
		if event is InputEventJoypadMotion and absf(event.axis_value) > 0.65:
			get_viewport().set_input_as_handled()
			var sgn := signf(event.axis_value)
			_finish_remap({"axis": event.axis, "sign": sgn})
			return
		return

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		leave()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X:
		action_x()

func _finish_remap(spec: Variant) -> void:
	var act := _remapping_action
	_remapping_action = ""
	_remap_modal.visible = false
	if spec != null and typeof(spec) == TYPE_DICTIONARY:
		Pad.rebind(act, spec)
		Settings.save_settings()
		if festival != null:
			festival.toast("REMAPPED %s → %s" % [Pad.ACTION_LABELS.get(act, act).to_upper(), Pad.binding_string(act)])
	refresh()

func action_x() -> void:
	Pad.reset_to_defaults()
	Settings.save_settings()
	if festival != null:
		festival.toast("RESET ALL CONTROLS TO DEFAULTS")
	refresh()

func leave() -> void:
	if festival != null:
		super.leave()
	else:
		get_tree().paused = false
		queue_free()

func _process(_delta: float) -> void:
	if not visible:
		return
	# Update live tester
	var state := Pad.raw_state()
	if state.axes.size() >= 6:
		var lx: float = state.axes[JOY_AXIS_LEFT_X]
		var ly: float = state.axes[JOY_AXIS_LEFT_Y]
		var rx: float = state.axes[JOY_AXIS_RIGHT_X]
		var ry: float = state.axes[JOY_AXIS_RIGHT_Y]
		var lt: float = clampf(state.axes[JOY_AXIS_TRIGGER_LEFT], 0.0, 1.0)
		var rt: float = clampf(state.axes[JOY_AXIS_TRIGGER_RIGHT], 0.0, 1.0)

		_trigger_l_bar.value = lt * 100.0
		_trigger_r_bar.value = rt * 100.0

		_stick_l_dot.position = Vector2(44 + lx * 38.0, 44 + ly * 38.0)
		_stick_r_dot.position = Vector2(44 + rx * 38.0, 44 + ry * 38.0)

		_stick_l_txt.text = "X: %+.2f  Y: %+.2f" % [lx, ly]
		_stick_r_txt.text = "X: %+.2f  Y: %+.2f" % [rx, ry]

	# Update button indicators
	for b_idx in _btn_labels:
		var is_dn: bool = Input.is_joy_button_pressed(Pad.device, b_idx) if Pad.device >= 0 else false
		var entry: Dictionary = _btn_labels[b_idx]
		var p: PanelContainer = entry.panel
		var lbl: Label = entry.label
		var sb: StyleBoxFlat = entry.base_sb
		if is_dn:
			sb.bg_color = UIKit.NEON
			lbl.add_theme_color_override("font_color", Color.WHITE)
		else:
			sb.bg_color = Color(0.12, 0.12, 0.16)
			lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
