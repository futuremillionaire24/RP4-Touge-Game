class_name PaintScreen
extends MenuScreen
## Paint shop: European factory colours and seven automotive finishes (gloss, metallic, pearl,
## matte, satin, chrome, candy), previewed live on the stage car. A saves; B discards.

const PALETTE := [
	["Carrara White", Color(0.94, 0.94, 0.92)], ["Obsidian Black", Color(0.03, 0.03, 0.035)],
	["Amethyst Schwarz", Color(0.18, 0.06, 0.3)], ["Estoril Blue", Color(0.1, 0.3, 0.75)],
	["Arancio Borealis", Color(0.95, 0.42, 0.05)], ["Rosso Corsa", Color(0.75, 0.04, 0.06)],
	["Racing Yellow", Color(0.98, 0.82, 0.1)], ["British Racing Green", Color(0.55, 0.62, 0.55)],
	["Titanium Silver", Color(0.72, 0.74, 0.77)], ["Giallo Modena", Color(0.95, 0.72, 0.1)],
	["Racing Green", Color(0.03, 0.26, 0.12)], ["Neon Pink", Color(1.0, 0.18, 0.53)],
	["Chalk White", Color(0.93, 0.93, 0.92)], ["Titanium Grey", Color(0.3, 0.31, 0.33)],
	["Nogaro Blue", Color(0.08, 0.2, 0.55)], ["Lime Green", Color(0.55, 0.85, 0.15)],
]
const FINISH_ORDER := ["gloss", "metallic", "pearl", "matte", "satin", "chrome", "candy"]

var index := 0
var _h := 0.0
var _s := 0.0
var _v := 0.0
var _finish := "gloss"
var _pal := -1 # -1 = custom colour
var _swatch: ColorRect
var _rows := {}
var _orig := {}

func _init(garage_index := 0) -> void:
	super._init()
	index = garage_index

func _entry() -> Dictionary:
	return Profile.data.garage[index]

func build() -> void:
	var e := _entry()
	_orig = {"paint": e.paint.duplicate(), "finish": e.finish}
	var c := _color()
	_h = c.h
	_s = c.s
	_v = c.v
	_finish = e.finish
	var col := make_column(540)
	col.add_child(UIKit.header("Paint & Finish", "", CarData.get_car(e.key).name))
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(520, 26)
	col.add_child(_swatch)
	_rows.palette = _row(col, "Palette", func(d):
		_pal = wrapi(_pal + d, 0, PALETTE.size()) if _pal >= 0 else (0 if d > 0 else PALETTE.size() - 1)
		var pc: Color = PALETTE[_pal][1]
		_h = pc.h
		_s = pc.s
		_v = pc.v
		_apply())
	_rows.hue = _row(col, "Hue", func(d):
		_pal = -1
		_h = fposmod(_h + d * 0.01, 1.0)
		_apply())
	_rows.sat = _row(col, "Saturation", func(d):
		_pal = -1
		_s = clampf(_s + d * 0.02, 0.0, 1.0)
		_apply())
	_rows.val = _row(col, "Brightness", func(d):
		_pal = -1
		_v = clampf(_v + d * 0.02, 0.0, 1.0)
		_apply())
	_rows.finish = _row(col, "Finish", func(d):
		_finish = FINISH_ORDER[wrapi(FINISH_ORDER.find(_finish) + d, 0, FINISH_ORDER.size())]
		_apply())
	var factory := UIRow.new("FACTORY COLOUR")
	factory.on_accept = func():
		var car := CarData.get_car(e.key)
		var pc: Color = car.paint
		_h = pc.h
		_s = pc.s
		_v = pc.v
		_finish = car.get("finish", "gloss")
		_apply()
	col.add_child(factory)
	var save := UIRow.new("APPLY PAINT", "FREE")
	save.on_accept = _save
	col.add_child(save)
	set_hints([["â—€â–¶", "Adjust"], ["A", "Apply"], ["RS", "Look around"], ["B", "Discard"]])
	stage.show_entry(e, true)
	_apply()

func _row(col: Control, title: String, adjust: Callable) -> UIRow:
	var r := UIRow.new(title)
	r.on_adjust = adjust
	col.add_child(r)
	return r

func _color() -> Color:
	var p: Array = _entry().paint
	return Color(p[0], p[1], p[2])

func _apply() -> void:
	var c := Color.from_hsv(_h, _s, _v)
	_swatch.color = c
	_rows.palette.set_value(PALETTE[_pal][0] if _pal >= 0 else "Custom")
	_rows.hue.set_value("%dÂ°" % roundi(_h * 360.0)).set_fraction(_h)
	_rows.hue.bar_color = Color.from_hsv(_h, 1.0, 1.0)
	_rows.sat.set_value("%d%%" % roundi(_s * 100.0)).set_fraction(_s)
	_rows.val.set_value("%d%%" % roundi(_v * 100.0)).set_fraction(_v)
	_rows.finish.set_value(_finish.capitalize())
	# The stage car may still be building on the first frame; retry until it's there.
	if stage.view == null:
		await get_tree().create_timer(0.1).timeout
		if is_inside_tree() and stage.view != null:
			stage.set_paint(c, _finish)
		return
	stage.set_paint(c, _finish)

func _save() -> void:
	var c := Color.from_hsv(_h, _s, _v)
	var e := _entry()
	e.paint = [c.r, c.g, c.b]
	e.finish = _finish
	Profile.save()
	festival.toast("PAINT APPLIED")
	_orig = {}
	festival.pop()

func back() -> void:
	# Discard: restore the stage to the saved paint.
	if not _orig.is_empty():
		var p: Array = _orig.paint
		stage.set_paint(Color(p[0], p[1], p[2]), _orig.finish)
	super.back()

