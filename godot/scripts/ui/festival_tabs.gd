class_name FestivalTabs
extends Control
## FH4-style page tabs across the top: [LB] CAMPAIGN  CARS  MY FESTIVAL  OPTIONS [RB]. The active
## tab is white with a magenta underline that slides between tabs; LB/RB (Q/E) switch, handled by
## the owning MenuScreen via tab(dir).

signal changed(index: int)

var names: PackedStringArray = []
var current := 0
var _labels: Array[Label] = []
var _row: HBoxContainer
var _line: ColorRect

func _init(p_names: PackedStringArray = []) -> void:
	names = p_names
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 48)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 26)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_row.add_child(UIKit.glyph("LB"))
	for n in names:
		var l := UIKit.label(n.to_upper(), 27, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, "heavy")
		_row.add_child(l)
		_labels.append(l)
	_row.add_child(UIKit.glyph("RB"))
	_line = ColorRect.new()
	_line.color = UIKit.ACCENT
	_line.size = Vector2(40, 4)
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_line)
	for g in [_row.get_child(0), _row.get_child(_row.get_child_count() - 1)]:
		(g as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _ready() -> void:
	await get_tree().process_frame
	select(current, false)

func select(i: int, animate := true) -> void:
	if names.is_empty():
		return
	current = wrapi(i, 0, names.size())
	for k in range(_labels.size()):
		_labels[k].add_theme_color_override("font_color", Color.WHITE if k == current else Color(1, 1, 1, 0.45))
	var l := _labels[current]
	var target_pos := Vector2(l.position.x, l.position.y + l.size.y + 1)
	var target_size := Vector2(l.size.x, 4)
	if animate and not bool(Settings.get_value("gameplay", "reduced_motion", false)):
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_line, "position", target_pos, 0.16)
		tw.tween_property(_line, "size", target_size, 0.16)
	else:
		_line.position = target_pos
		_line.size = target_size

func step(dir: int) -> void:
	select(current + dir)
	Haptics.impact(0.1, 10)
	changed.emit(current)
