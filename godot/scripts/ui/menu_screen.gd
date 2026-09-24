class_name MenuScreen
extends Control
## Base for festival menu screens. The Festival host pushes/pops screens; each screen builds its
## widgets in build(), refreshes data in refresh(), and gets pad input: B = back, L1/R1 = tabs,
## X / Y = secondary actions. Focus is remembered across push/pop.

var festival: Festival
var stage: CarStage
var column: VBoxContainer # left menu column
var hint_bar: HBoxContainer
var _last_focus: Control
var _built := false

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Left column container (under the top bar) that most screens fill.
func make_column(width := 560.0, top := 36.0) -> VBoxContainer:
	column = VBoxContainer.new()
	column.position = Vector2(44, top)
	column.size = Vector2(width, 750 - top - 60)
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	return column

func set_hints(pairs: Array) -> void:
	if hint_bar:
		hint_bar.queue_free()
	hint_bar = UIKit.hints(pairs)
	hint_bar.position = Vector2(44, 750 - 44)
	add_child(hint_bar)

## Scrollable list inside the column; returns the VBox to add rows to.
func make_list(parent: Control, height: float) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, height)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	sc.add_child(v)
	return v

func build() -> void:
	pass

func refresh() -> void:
	pass

func enter() -> void:
	if not _built:
		_built = true
		build()
	refresh()
	visible = true
	UIKit.fade_in(self, 18.0)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var cur := get_viewport().gui_get_focus_owner()
	if cur and is_ancestor_of(cur):
		return
	if _last_focus and is_instance_valid(_last_focus) and _last_focus.is_visible_in_tree():
		_last_focus.grab_focus()
	else:
		focus_default()

func leave() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f and is_ancestor_of(f):
		_last_focus = f

func focus_default() -> void:
	var first := _first_focusable(self)
	if first:
		first.grab_focus()

func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			if (c as Control).focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled):
				return c
			var inner := _first_focusable(c)
			if inner:
				return inner
	return null

func back() -> void:
	if festival != null:
		festival.pop()
	else:
		leave()
		queue_free()

func tab(_dir: int) -> void:
	pass

func action_x() -> void:
	pass

func action_y() -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if festival != null and (festival.top() != self or festival.modal_open()):
		return
	if event.is_action_pressed("ui_cancel"):
		back()
	elif _is_button(event, JOY_BUTTON_LEFT_SHOULDER, KEY_Q):
		tab(-1)
	elif _is_button(event, JOY_BUTTON_RIGHT_SHOULDER, KEY_E):
		tab(1)
	elif _is_button(event, JOY_BUTTON_X, KEY_X):
		action_x()
	elif _is_button(event, JOY_BUTTON_Y, KEY_Y):
		action_y()
	else:
		return
	get_viewport().set_input_as_handled()

static func _is_button(event: InputEvent, joy: JoyButton, key: Key) -> bool:
	if event is InputEventJoypadButton:
		return event.pressed and (event as InputEventJoypadButton).button_index == joy
	if event is InputEventKey:
		return event.pressed and not event.echo and (event as InputEventKey).physical_keycode == key
	return false

## Tab strip widget: returns an HBox with labels; call highlight_tabs(strip, index).
func make_tabs(parent: Control, names: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.add_child(UIKit.glyph("L1"))
	for n in names:
		var l := UIKit.label(n.to_upper(), 17, UIKit.DIM)
		l.custom_minimum_size = Vector2(0, 30)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var p := PanelContainer.new()
		p.set_meta("tab", true)
		p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		p.add_child(l)
		h.add_child(p)
	h.add_child(UIKit.glyph("R1"))
	parent.add_child(h)
	return h

func highlight_tabs(strip: HBoxContainer, index: int) -> void:
	var i := 0
	for c in strip.get_children():
		if c is PanelContainer and c.has_meta("tab"):
			var l: Label = c.get_child(0)
			var on := i == index
			l.add_theme_color_override("font_color", Color.WHITE if on else UIKit.DIM)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(UIKit.NEON, 0.35) if on else Color(0, 0, 0, 0)
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			sb.set_corner_radius_all(3)
			c.add_theme_stylebox_override("panel", sb)
			i += 1
