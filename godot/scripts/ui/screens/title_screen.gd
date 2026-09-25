class_name TitleScreen
extends MenuScreen
## Title: flickering neon logo over the car stage; "PRESS A" then Continue / New Festival /
## Dev tools / Quit. New players go to the starter-car choice.

var _press: Label
var _menu: VBoxContainer
var _t := 0.0

func build() -> void:
	festival.set_top_bar_visible(false)
	stage.frame_offset = 0.0
	var e := Profile.current_car()
	if e.is_empty():
		stage.show_key("ferrari_f40", true)
	else:
		stage.show_entry(e, true)
	var name_box := VBoxContainer.new()
	name_box.position = Vector2(84, 80)
	name_box.add_theme_constant_override("separation", 2)
	add_child(name_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(UIKit.label("EURO GT", 88, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, "hero"))
	row.add_child(UIKit.label("FESTIVAL", 88, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, "hero"))
	name_box.add_child(row)
	var sub := UIKit.label("MONACO  ·  CÔTE D'AZUR  ·  EUROPEAN GRAND TOURING", 22, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT, "title")
	name_box.add_child(sub)
	var accent_line := ColorRect.new()
	accent_line.color = UIKit.NEON
	accent_line.custom_minimum_size = Vector2(360, 6)
	accent_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_box.add_child(accent_line)

	_press = UIKit.label("PRESS  A  TO  START", 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "heavy")
	_press.position = Vector2(0, 610)
	_press.size = Vector2(1334, 40)
	add_child(_press)
	_menu = VBoxContainer.new()
	_menu.position = Vector2(84, 420)
	_menu.custom_minimum_size = Vector2(440, 0)
	_menu.visible = false
	add_child(_menu)
	var has_save: bool = bool(Profile.data.onboarded) and not Profile.data.garage.is_empty()
	if has_save:
		var cont := UIRow.new("CONTINUE", "LV %d" % int(Profile.data.level))
		cont.on_accept = func(): festival.reset_to(HubScreen.new())
		_menu.add_child(cont)
	var nf := UIRow.new("NEW FESTIVAL")
	nf.on_accept = _new_festival.bind(has_save)
	_menu.add_child(nf)
	var dev := UIRow.new("DEVELOPER TOOLS", "bench · input")
	dev.on_accept = func(): get_tree().change_scene_to_file("res://scenes/launcher.tscn")
	_menu.add_child(dev)
	var quit := UIRow.new("QUIT")
	quit.on_accept = func():
		Profile.save()
		get_tree().quit()
	_menu.add_child(quit)
	var ver := UIKit.label("v%s" % ProjectSettings.get_setting("application/config/version", "1.0"), 16, UIKit.DIM)
	ver.position = Vector2(1240, 716)
	add_child(ver)

func focus_default() -> void:
	if _menu.visible:
		_menu.get_child(0).grab_focus()

func _process(delta: float) -> void:
	_t += delta
	_press.modulate.a = 0.6 + 0.4 * sin(_t * 3.0)

func _unhandled_input(event: InputEvent) -> void:
	var start_pressed: bool = (
		event.is_action_pressed("ui_accept")
		or (event is InputEventJoypadButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if not _menu.visible and start_pressed:
		_menu.visible = true
		_press.visible = false
		UIKit.fade_in(_menu)
		_menu.get_child(0).grab_focus()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and _menu.visible:
		_menu.visible = false
		_press.visible = true
		get_viewport().set_input_as_handled()

func _new_festival(has_save: bool) -> void:
	if not has_save:
		festival.reset_to(StarterScreen.new())
		return
	festival.choose("Start a new festival?", "Your garage, credits and progress will be erased. Settings are kept.", [
		["CANCEL", Callable()],
		["ERASE AND START OVER", func():
			Profile.reset()
			festival.reset_to(StarterScreen.new())],
	])

func leave() -> void:
	super.leave()
	festival.set_top_bar_visible(true)
	stage.frame_offset = 1.3
