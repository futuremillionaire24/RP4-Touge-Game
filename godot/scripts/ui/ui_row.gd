class_name UIRow
extends Button
## Menu row: title on the left, value on the right. Left/right adjusts when `on_adjust` is set
## (◀ ▶ shown while focused), A triggers `on_accept`. Optional bar shows a 0..1 fraction and an
## optional ghost marker (e.g. stock value in the tuning screen).

var on_adjust: Callable # func(dir: int)
var on_accept: Callable
var on_focus: Callable
var _title: Label
var _value: Label
var _sub: Label
var _bar: Control
var fraction := -1.0
var marker := -1.0
var bar_color := UIKit.CYAN

func _init(title := "", value := "") -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0, 48)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18
	h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	_title = UIKit.label(title, 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.clip_text = true
	h.add_child(_title)
	_sub = UIKit.label("", 17, UIKit.DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_sub)
	_value = UIKit.label(value, 20, UIKit.CYAN, HORIZONTAL_ALIGNMENT_RIGHT)
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.custom_minimum_size = Vector2(150, 0)
	h.add_child(_value)
	_raw_value = value
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_top = -5
	_bar.offset_bottom = -2
	_bar.offset_left = 18
	_bar.offset_right = -14
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	pressed.connect(func():
		if on_accept.is_valid():
			on_accept.call())
	focus_entered.connect(func():
		_refresh_value()
		if on_focus.is_valid():
			on_focus.call())
	focus_exited.connect(_refresh_value)

var _raw_value := ""

func set_title(t: String) -> UIRow:
	_title.text = t
	return self

func set_value(v: String, color := UIKit.CYAN) -> UIRow:
	_raw_value = v
	_value.add_theme_color_override("font_color", color)
	_refresh_value()
	return self

func set_sub(s: String, color := UIKit.DIM) -> UIRow:
	_sub.text = s
	_sub.add_theme_color_override("font_color", color)
	return self

func set_fraction(f: float, ghost := -1.0) -> UIRow:
	fraction = f
	marker = ghost
	_bar.queue_redraw()
	return self

func _refresh_value() -> void:
	if on_adjust.is_valid() and has_focus():
		_value.text = "◀  %s  ▶" % _raw_value
	else:
		_value.text = _raw_value

func _draw_bar() -> void:
	if fraction < 0.0:
		return
	var w := _bar.size.x
	_bar.draw_rect(Rect2(0, 0, w, 3), Color(1, 1, 1, 0.1))
	_bar.draw_rect(Rect2(0, 0, w * clampf(fraction, 0.0, 1.0), 3), bar_color)
	if marker >= 0.0:
		_bar.draw_rect(Rect2(w * clampf(marker, 0.0, 1.0) - 1, -3, 2, 9), Color(1, 1, 1, 0.7))

var _hold_dir := 0
var _hold_time := 0.0
var _repeat_interval := 0.0

func _gui_input(event: InputEvent) -> void:
	if not on_adjust.is_valid():
		return
	var dir := 0
	if event.is_action_pressed("ui_left", false):
		dir = -1
	elif event.is_action_pressed("ui_right", false):
		dir = 1
	if dir != 0:
		_hold_dir = dir
		_hold_time = 0.0
		_repeat_interval = 0.30
		on_adjust.call(dir)
		_refresh_value()
		Haptics.impact(0.12, 12)
		accept_event()
	elif event.is_action_released("ui_left") or event.is_action_released("ui_right"):
		_hold_dir = 0
		_hold_time = 0.0

func _process(delta: float) -> void:
	if not has_focus() or not on_adjust.is_valid() or _hold_dir == 0:
		_hold_dir = 0
		return
	var left_dn: bool = Input.is_action_pressed("ui_left")
	var right_dn: bool = Input.is_action_pressed("ui_right")
	if not left_dn and not right_dn:
		_hold_dir = 0
		return
	_hold_time += delta
	if _hold_time >= _repeat_interval:
		_hold_time -= _repeat_interval
		_repeat_interval = maxf(0.05, _repeat_interval * 0.85)
		on_adjust.call(_hold_dir)
		_refresh_value()
		Haptics.impact(0.08, 10)

