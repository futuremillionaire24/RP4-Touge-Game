class_name UIKit
extends RefCounted
## Neon JDM UI kit: theme, palette, text helpers and small widgets shared by every menu.
## Tuned for the RP4's 4.7" 1334x750 panel: 20 px minimum body text, 48 px row height.

const BG := Color(0.08, 0.08, 0.11)
const PANEL := Color(0.10, 0.10, 0.15, 0.94)
const PANEL_LIGHT := Color(1, 1, 1, 0.07)
const NEON := Color(0.91, 0.64, 0.09) # Forza Horizon warm amber-gold accent
const CYAN := Color(0.92, 0.93, 0.96) # Clean European silver/white secondary
const AMBER := Color(0.95, 0.68, 0.12)
const GREEN := Color(0.18, 0.55, 0.32) # British racing green
const RED := Color(0.86, 0.16, 0.16) # Ferrari/Brembo racing red
const TEXT := Color(0.95, 0.95, 0.97)
const DIM := Color(0.72, 0.72, 0.76)

static var _theme: Theme

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 20
	var scale := float(Settings.get_value("gameplay", "text_scale", 1.0))
	t.default_font_size = int(20 * scale)
	# Buttons: Forza Horizon 4 flat design with amber-gold focus indicator
	var normal := _box(PANEL_LIGHT, Color(0, 0, 0, 0), 0)
	var focus := _box(Color(0.15, 0.14, 0.12, 0.95), NEON, 2)
	var pressed := _box(Color(0.25, 0.20, 0.08, 0.95), NEON, 2)
	var disabled := _box(Color(1, 1, 1, 0.025), Color(0, 0, 0, 0), 0)
	for sb in [normal, focus, pressed, disabled]:
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", focus)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	t.set_color("font_color", "Label", TEXT)
	var panel := _box(PANEL, Color(1, 1, 1, 0.08), 1)
	panel.set_content_margin_all(16)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var bar_bg := _box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0)
	var bar_fill := _box(NEON, Color(0, 0, 0, 0), 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 10)
	var grabber := _box(Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 0)
	grabber.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	t.set_stylebox("scroll", "VScrollBar", _box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0))
	_theme = t
	return t

static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(3)
	sb.anti_aliasing = true
	return sb

static func label(text: String, size := 20, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func header(title: String, _kanji: String = "", subtitle := "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(label(title.to_upper(), 34, TEXT))
	v.add_child(row)
	if subtitle != "":
		v.add_child(label(subtitle, 17, DIM))
	var line := ColorRect.new()
	line.color = NEON
	line.custom_minimum_size = Vector2(140, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(line)
	return v

## Bottom hint bar: pairs of [glyph, text]. Glyph colors follow the RP4 face buttons.
static func hints(pairs: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	for p in pairs:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		item.add_child(glyph(p[0]))
		item.add_child(label(p[1], 18, DIM))
		h.add_child(item)
	return h

const GLYPH_COLORS := {"A": Color(0.35, 0.85, 0.4), "B": Color(0.95, 0.3, 0.3), "X": Color(0.3, 0.6, 1.0),
	"Y": Color(1.0, 0.8, 0.2), "L1": Color(0.7, 0.7, 0.75), "R1": Color(0.7, 0.7, 0.75),
	"L2": Color(0.7, 0.7, 0.75), "R2": Color(0.7, 0.7, 0.75), "◀▶": Color(0.7, 0.7, 0.75),
	"START": Color(0.7, 0.7, 0.75), "RS": Color(0.7, 0.7, 0.75)}

static func glyph(name: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(Color(GLYPH_COLORS.get(name, Color.GRAY), 0.9), Color(0, 0, 0, 0), 0)
	sb.set_corner_radius_all(12 if name.length() == 1 else 6)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", sb)
	var l := label(name, 16, Color(0.05, 0.03, 0.08), HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(12, 0)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func class_badge(pi: int, size := 20) -> PanelContainer:
	var c := CarData.pi_class(pi)
	var p := PanelContainer.new()
	var sb := _box(Color(0.05, 0.05, 0.08, 0.92), CarData.CLASS_COLORS[c], 2)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(label(CarData.CLASS_NAMES[c], size, CarData.CLASS_COLORS[c]))
	h.add_child(label(str(pi), size, TEXT))
	p.add_child(h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + "CR " + s + out

static func time_str(t: float) -> String:
	if t < 0.0:
		return "--:--.---"
	return "%d:%02d.%03d" % [int(t) / 60, int(t) % 60, int(fmod(t, 1.0) * 1000.0)]

static func speed_str(ms: float) -> String:
	if bool(Settings.get_value("gameplay", "units_metric", true)):
		return "%d km/h" % roundi(ms * 3.6)
	return "%d mph" % roundi(ms * 2.23694)

static func fade_in(node: CanvasItem, slide := 24.0) -> void:
	if bool(Settings.get_value("gameplay", "reduced_motion", false)):
		slide = 0.0
	node.modulate.a = 0.0
	var c := node as Control
	var target := Vector2.ZERO
	if c:
		if c.has_meta("home_pos"):
			target = c.get_meta("home_pos")
		else:
			target = c.position
			c.set_meta("home_pos", target)
		c.position = target + Vector2(slide, 0)
	var tw := node.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, 0.18)
	if c:
		tw.tween_property(c, "position", target, 0.2)

static func scroll_into_view(scroll: ScrollContainer, c: Control) -> void:
	if scroll == null or c == null:
		return
	scroll.ensure_control_visible(c)
