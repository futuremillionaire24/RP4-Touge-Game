class_name UIKit
extends RefCounted
## Euro GT Festival UI kit (Forza Horizon 4 layout, German/European type): theme, palette, fonts,
## text helpers and small widgets shared by every menu. Type is Barlow / Barlow Condensed (SIL OFL,
## a DIN-lineage grotesque); focus is a bold white frame, focused list rows invert to white.
## Tuned for the RP4's 4.7" 1334x750 panel: 20 px minimum body text, 48 px row height.

const BG := Color(0.05, 0.05, 0.07)
const PANEL := Color(0.06, 0.065, 0.08, 0.88)
const PANEL_LIGHT := Color(1, 1, 1, 0.08)
const ACCENT := Color(0.93, 0.06, 0.44) # festival magenta (tab underline, tags, progress)
const NEON := ACCENT # legacy name used by older screens
const CYAN := Color(0.93, 0.94, 0.96) # values
const AMBER := Color(1.0, 0.74, 0.18) # wheelspins, highlights
const GREEN := Color(0.3, 0.86, 0.5) # credits gained, success
const RED := Color(0.94, 0.2, 0.2)
const TEXT := Color(0.96, 0.96, 0.97)
const DIM := Color(0.7, 0.71, 0.75)
const INK := Color(0.06, 0.06, 0.08) # text on white (focused rows)

const F_BODY := "res://assets/fonts/Barlow-Medium.ttf"
const F_BODY_BOLD := "res://assets/fonts/Barlow-SemiBold.ttf"
const F_UI := "res://assets/fonts/BarlowCondensed-SemiBold.ttf"
const F_TITLE := "res://assets/fonts/BarlowCondensed-Bold.ttf"
const F_HEAVY := "res://assets/fonts/BarlowCondensed-ExtraBold.ttf"
const F_HERO := "res://assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf"

static var _theme: Theme
static var _fonts := {}

## Font by style: "body", "body_bold", "ui" (default), "title", "heavy", "hero".
static func font(style := "ui") -> Font:
	if _fonts.has(style):
		return _fonts[style]
	var path: String = {"body": F_BODY, "body_bold": F_BODY_BOLD, "ui": F_UI, "title": F_TITLE, "heavy": F_HEAVY, "hero": F_HERO}.get(style, F_UI)
	var f: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	_fonts[style] = f
	return f

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var scale := float(Settings.get_value("gameplay", "text_scale", 1.0))
	t.default_font = font("ui")
	t.default_font_size = int(21 * scale)
	# Buttons / rows: translucent dark slabs; focus inverts to a white slab with ink text (FH4).
	var normal := _box(Color(0.04, 0.045, 0.06, 0.72), Color(0, 0, 0, 0), 0)
	var focus := _box(Color(0.97, 0.97, 0.98, 0.98), Color(1, 1, 1, 1), 0)
	var pressed := _box(Color(0.85, 0.85, 0.88, 0.98), ACCENT, 0)
	var disabled := _box(Color(0.04, 0.045, 0.06, 0.4), Color(0, 0, 0, 0), 0)
	for sb in [normal, focus, pressed, disabled]:
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", focus)
	t.set_stylebox("focus", "Button", focus) # drawn over "normal" for pad focus: the white slab
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	t.set_color("font_color", "Label", TEXT)
	var panel := _box(PANEL, Color(1, 1, 1, 0.06), 1)
	panel.set_content_margin_all(16)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var bar_bg := _box(Color(1, 1, 1, 0.14), Color(0, 0, 0, 0), 0)
	var bar_fill := _box(ACCENT, Color(0, 0, 0, 0), 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 10)
	var grabber := _box(Color(1, 1, 1, 0.3), Color(0, 0, 0, 0), 0)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	t.set_stylebox("scroll", "VScrollBar", _box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0))
	_theme = t
	return t

## Square-cornered flat box (FH4 panels have no rounding).
static func _box(bg: Color, border: Color, width: int, radius := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = radius > 0
	return sb

## Label. style: see font(); uppercase UI text uses "ui"/"title", prose uses "body".
static func label(text: String, size := 20, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, style := "ui") -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_override("font", font(style))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Screen header: big condensed caps title, optional subtitle, magenta rule.
static func header(title: String, _kanji: String = "", subtitle := "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(label(title.to_upper(), 44, TEXT, HORIZONTAL_ALIGNMENT_LEFT, "heavy"))
	if subtitle != "":
		v.add_child(label(subtitle.to_upper(), 18, DIM, HORIZONTAL_ALIGNMENT_LEFT, "ui"))
	var line := ColorRect.new()
	line.color = ACCENT
	line.custom_minimum_size = Vector2(96, 4)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(line)
	return v

## Bottom hint bar: pairs of [glyph, text].
static func hints(pairs: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	for p in pairs:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 7)
		item.add_child(glyph(p[0]))
		item.add_child(label(String(p[1]).to_upper(), 18, TEXT, HORIZONTAL_ALIGNMENT_LEFT, "ui"))
		h.add_child(item)
	return h

const GLYPH_COLORS := {"A": Color(0.35, 0.85, 0.4), "B": Color(0.95, 0.3, 0.3), "X": Color(0.3, 0.6, 1.0),
	"Y": Color(1.0, 0.8, 0.2), "L1": Color(0.9, 0.9, 0.92), "R1": Color(0.9, 0.9, 0.92),
	"L2": Color(0.9, 0.9, 0.92), "R2": Color(0.9, 0.9, 0.92), "◀▶": Color(0.9, 0.9, 0.92),
	"START": Color(0.9, 0.9, 0.92), "RS": Color(0.9, 0.9, 0.92), "LB": Color(0.9, 0.9, 0.92), "RB": Color(0.9, 0.9, 0.92)}

static func glyph(name: String) -> PanelContainer:
	var p := PanelContainer.new()
	var round := name.length() == 1
	var sb := _box(Color(GLYPH_COLORS.get(name, Color.GRAY), 0.95), Color(0, 0, 0, 0), 0, 12 if round else 4)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", sb)
	var l := label(name, 16, INK, HORIZONTAL_ALIGNMENT_CENTER, "title")
	l.custom_minimum_size = Vector2(12, 0)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## FH4 class plate: class letter on its colour, PI on black.
static func class_badge(pi: int, size := 20) -> PanelContainer:
	var c := CarData.pi_class(pi)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.04, 0.95), CarData.CLASS_COLORS[c], 2))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var letter := PanelContainer.new()
	var lsb := _box(CarData.CLASS_COLORS[c], Color(0, 0, 0, 0), 0)
	lsb.content_margin_left = 7
	lsb.content_margin_right = 7
	letter.add_theme_stylebox_override("panel", lsb)
	letter.add_child(label(CarData.CLASS_NAMES[c], size, INK, HORIZONTAL_ALIGNMENT_CENTER, "heavy"))
	h.add_child(letter)
	var num := label(str(pi), size, TEXT, HORIZONTAL_ALIGNMENT_CENTER, "heavy")
	num.custom_minimum_size = Vector2(size * 2.1, 0)
	h.add_child(num)
	p.add_child(h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## Small magenta tag (tile categories, "NEW", "OWNED").
static func tag(text: String, color := ACCENT, size := 15) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(color, Color(0, 0, 0, 0), 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(text.to_upper(), size, Color.WHITE if color.get_luminance() < 0.6 else INK, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## Tile art rendered by tools/tile_art.gd: res://assets/ui/<kind>/<name>.webp (null if missing).
static func art(kind: String, name: String) -> Texture2D:
	var p := "res://assets/ui/%s/%s.webp" % [kind, name]
	return load(p) if ResourceLoader.exists(p) else null

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
