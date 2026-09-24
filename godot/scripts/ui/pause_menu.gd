class_name PauseMenu
extends CanvasLayer
## In-world pause (Start): pauses the tree, shows a pad-navigable list of actions. The host
## passes [[label, id], ...] and gets `chosen(id)` ("resume" is always first and on B/Start).

signal chosen(id: String)

var _rows: Array[UIRow] = []

func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

func open(title: String, subtitle: String, options: Array) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.04, 0.06, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var col := VBoxContainer.new()
	col.position = Vector2(84, 120)
	col.custom_minimum_size = Vector2(480, 0)
	root.add_child(col)
	col.add_child(UIKit.header(title, "", subtitle))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 14)
	col.add_child(sp)
	for o in [["RESUME", "resume"]] + options:
		var row := UIRow.new(o[0])
		var id: String = o[1]
		row.on_accept = func(): _pick(id)
		col.add_child(row)
		_rows.append(row)
	var hints := UIKit.hints([["A", "Select"], ["B", "Resume"]])
	hints.position = Vector2(84, 706)
	root.add_child(hints)
	get_tree().paused = true
	Haptics.clear()
	UIKit.fade_in(col)
	_rows[0].grab_focus()

func _pick(id: String) -> void:
	get_tree().paused = false
	chosen.emit(id)
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	var start: bool = event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START
	var esc: bool = event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_ESCAPE
	if event.is_action_pressed("ui_cancel") or start or esc:
		get_viewport().set_input_as_handled()
		_pick("resume")
