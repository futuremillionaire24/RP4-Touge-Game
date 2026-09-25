class_name CreditsScreen
extends MenuScreen
## Credits and attributions, built from the credit records the asset tools write (CC-BY cars and
## props from Sketchfab, CC0 Poly Haven textures and skies, OpenStreetMap / terrain data, fonts).
## Rolls slowly on its own; up/down scrolls, B returns.

var _scroll: ScrollContainer
var _body: VBoxContainer
var _pos := 0.0
var _hold := 2.0

func build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var head := UIKit.header("Credits", "", "Euro GT Festival · made with Godot Engine")
	head.position = Vector2(44, 20)
	add_child(head)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(44, 120)
	_scroll.size = Vector2(1246, 570)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(1246, 0)
	_body.add_theme_constant_override("separation", 2)
	_scroll.add_child(_body)
	_fill()
	set_hints([["▲▼", "Scroll"], ["B", "Back"]])

func _section(title: String) -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 18)
	_body.add_child(sp)
	_body.add_child(UIKit.label(title.to_upper(), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, "heavy"))
	var line := ColorRect.new()
	line.color = UIKit.ACCENT
	line.custom_minimum_size = Vector2(80, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.add_child(line)

## One credit: the work on the first line, author / licence / source wrapped beneath it.
func _line(left: String, right := "") -> void:
	_body.add_child(UIKit.label(left, 20, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, "body_bold"))
	if right != "":
		_note(right)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	_body.add_child(sp)

func _note(text: String) -> void:
	var r := UIKit.label(text, 17, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, "body")
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(1220, 0)
	_body.add_child(r)

static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _credit_line(c: Dictionary, what: String) -> void:
	_line("%s — \"%s\"" % [what, c.get("title", "")], "by %s · %s · %s" % [c.get("author", "?"), c.get("license", ""), c.get("source", "")])

func _fill() -> void:
	_section("Cars")
	_note("3D models licensed under Creative Commons Attribution, adapted for the game (scaled, re-rigged, optimised). Real car names and brands belong to their owners; this is an unofficial fan project.")
	for dir in ["res://assets/cars"]:
		for k in DirAccess.get_directories_at(dir):
			var j := _json("%s/%s/%s.json" % [dir, k, k])
			if j.has("credit"):
				var name: String = String(CarData.get_car(k).get("name", k)) if CarData.keys().has(k) else k.replace("_", " ").capitalize() + " (traffic)"
				_credit_line(j.credit, name)
	_section("World props")
	for k in DirAccess.get_directories_at("res://assets/props"):
		var j := _json("res://assets/props/%s/%s.json" % [k, k])
		if j.has("credit"):
			_credit_line(j.credit, k.replace("_", " ").capitalize())
	_section("Textures & skies")
	_note("Poly Haven (polyhaven.com) — CC0 public domain.")
	var env := _json("res://assets/env/env_textures.json")
	for set_name in env.keys():
		for l in env[set_name].get("layers", []):
			_line(String(l.get("name", l.get("id", ""))), "by %s · CC0" % ", ".join(PackedStringArray(l.get("authors", []))))
	var sky := _json("res://assets/env/sky/sky.json")
	for s in sky.get("skies", []):
		_line(String(s.id).replace("_", " ").capitalize(), "by %s · CC0 · %s" % [", ".join(PackedStringArray(s.get("authors", []))), s.get("source", "")])
	_section("Map")
	_line(MapData.credit())
	_line("Monaco, the Corniches, La Turbie and Roquebrune-Cap-Martin", "roads, buildings, land use and trees from OpenStreetMap (ODbL)")
	_section("Type")
	_line("Barlow & Barlow Condensed", "by Jeremy Tribby · SIL Open Font License 1.1")
	_section("Engine")
	_line("Godot Engine", "godotengine.org · MIT License · Jolt Physics (MIT)")

func _process(delta: float) -> void:
	if _scroll == null:
		return
	var dir := Input.get_axis("ui_up", "ui_down")
	if absf(dir) > 0.1:
		_pos += dir * 520.0 * delta
		_hold = 3.0
	else:
		_hold -= delta
		if _hold <= 0.0:
			_pos += 34.0 * delta # slow roll
	var max_scroll := maxf(0.0, _body.size.y - _scroll.size.y)
	_pos = clampf(_pos, 0.0, max_scroll)
	_scroll.scroll_vertical = int(_pos)

func focus_default() -> void:
	pass
