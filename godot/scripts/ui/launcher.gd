extends Control
## Development launcher (replaced by the Festival title flow in M5): pick a car, AI count and
## weather for the test circuit, or open the input test / hardware benchmark. D-pad + A.

const NEON := Color(1.0, 0.18, 0.53)
const CYAN := Color(0.15, 0.91, 1.0)

var _car_idx := 3
var _ai := 5
var _wet := 0
var _items := []
var _car_btn: Button
var _ai_btn: Button
var _wet_btn: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := Label.new()
	title.text = "EURO GT FESTIVAL"
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", NEON)
	title.position = Vector2(80, 60)
	add_child(title)
	var sub := Label.new()
	sub.text = "Retroid Pocket 4 Pro build  ·  development launcher"
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	sub.position = Vector2(84, 136)
	add_child(sub)
	var box := VBoxContainer.new()
	box.position = Vector2(84, 200)
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_car_btn = _button(box, "", _cycle_car)
	_ai_btn = _button(box, "", _cycle_ai)
	_wet_btn = _button(box, "", _cycle_wet)
	_button(box, "▶  FREE ROAM — JAPAN", _freeroam)
	_button(box, "▶  DRIVE TEST CIRCUIT", _drive)
	_button(box, "INPUT TEST", func(): get_tree().change_scene_to_file("res://scenes/input_test.tscn"))
	_button(box, "HARDWARE BENCHMARK", func(): get_tree().change_scene_to_file("res://scenes/benchmark.tscn"))
	_button(box, "QUIT", func(): get_tree().quit())
	_refresh()
	_items[3].grab_focus()

func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(520, 48)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.05)
	normal.content_margin_left = 18
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(NEON, 0.25)
	focus.border_color = NEON
	focus.set_border_width_all(2)
	focus.content_margin_left = 18
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", focus)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", focus)
	b.pressed.connect(cb)
	parent.add_child(b)
	_items.append(b)
	return b

func _refresh() -> void:
	var keys := CarData.keys()
	var car := CarData.get_car(keys[_car_idx])
	_car_btn.text = "CAR   ◀  %s  ▶" % car.name
	_ai_btn.text = "RIVALS   ◀  %d  ▶" % _ai
	_wet_btn.text = "WEATHER   ◀  %s  ▶" % ["Dry", "Damp", "Wet", "Downpour"][_wet]

func _cycle_car() -> void:
	_car_idx = (_car_idx + 1) % CarData.keys().size()
	_refresh()

func _cycle_ai() -> void:
	_ai = (_ai + 1) % 12
	_refresh()

func _cycle_wet() -> void:
	_wet = (_wet + 1) % 4
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	var f := get_viewport().gui_get_focus_owner()
	var dir := 0
	if event.is_action_pressed("ui_left"):
		dir = -1
	elif event.is_action_pressed("ui_right"):
		dir = 1
	if dir == 0 or f == null:
		return
	if f == _car_btn:
		_car_idx = (_car_idx + dir + CarData.keys().size()) % CarData.keys().size()
	elif f == _ai_btn:
		_ai = clampi(_ai + dir, 0, 11)
	elif f == _wet_btn:
		_wet = clampi(_wet + dir, 0, 3)
	_refresh()
	get_viewport().set_input_as_handled()

func _freeroam() -> void:
	var weather: int = [0, 2, 3, 4][_wet]
	get_tree().root.set_meta("launch", {"car": CarData.keys()[_car_idx], "weather": weather})
	get_tree().change_scene_to_file("res://scenes/freeroam.tscn")

func _drive() -> void:
	var wet: float = [0.0, 0.35, 0.7, 1.0][_wet]
	get_tree().root.set_meta("launch", {"car": CarData.keys()[_car_idx], "ai": _ai, "wet": wet})
	get_tree().change_scene_to_file("res://scenes/test_drive.tscn")
