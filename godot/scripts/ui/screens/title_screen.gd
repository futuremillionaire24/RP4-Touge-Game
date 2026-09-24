class_name TitleScreen
extends MenuScreen
## Title: flickering neon logo over the car stage; "PRESS A" then Continue / New Festival /
## Dev tools / Quit. New players go to the starter-car choice.

var _logo: Label
var _press: Label
var _menu: VBoxContainer
var _t := 0.0
var _flicker := 0.0

func build() -> void:
	festival.set_top_bar_visible(false)
	stage.frame_offset = 0.0
	var e := Profile.current_car()
	if e.is_empty():
		stage.show_key("sylph_s2", true)
	else:
		stage.show_entry(e, true)
	_logo = UIKit.label("峠", 150, UIKit.NEON)
	_logo.position = Vector2(84, 70)
	add_child(_logo)
	var name_l := UIKit.label("NEON TOUGE", 68, Color.WHITE)
	name_l.position = Vector2(270, 108)
	add_child(name_l)
	var sub := UIKit.label("JAPAN STREET FESTIVAL  ·  RETROID POCKET 4 PRO", 20, UIKit.CYAN)
	sub.position = Vector2(276, 196)
	add_child(sub)
	_press = UIKit.label("PRESS  A  TO  START", 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
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
	_press.modulate.a = 0.55 + 0.45 * sin(_t * 3.0)
	# Neon tube flicker: rare quick dropouts.
	_flicker -= delta
	if _flicker <= 0.0:
		_flicker = randf_range(0.04, 0.09) if randf() < 0.25 else randf_range(1.5, 5.0)
		_logo.modulate = Color(1, 1, 1, 0.35) if _flicker < 0.1 else Color.WHITE
	elif _flicker > 0.1:
		_logo.modulate = Color.WHITE

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
