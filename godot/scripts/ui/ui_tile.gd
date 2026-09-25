class_name UITile
extends Button
## Forza Horizon-style menu tile: full-bleed image (or a tinted gradient when there is no art),
## category tag top-left, badge top-right, bold title + subtitle bottom-left, info bottom-right.
## Focus: thick white frame and a slight zoom. A triggers `on_accept`; `on_focus` lets a screen
## update its detail panel / the car stage.

var on_accept: Callable
var on_focus: Callable
var _img: TextureRect
var _shade: TextureRect
var _frame: Panel
var _title: Label
var _sub: Label
var _info: Label
var _tag_box: HBoxContainer
var _badge_box: HBoxContainer
var _lock: Label
var _tint := Color(0.16, 0.18, 0.24)
var locked := false

func _init(title := "", subtitle := "", image: Texture2D = null) -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	# Background: art, or a two-tone gradient in the tile's tint.
	_img = TextureRect.new()
	_img.set_anchors_preset(Control.PRESET_FULL_RECT)
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_img)
	_shade = TextureRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.1), Color(0, 0, 0, 0.82)])
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	_shade.texture = gt
	add_child(_shade)
	var text := VBoxContainer.new()
	text.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	text.offset_left = 14
	text.offset_right = -14
	text.offset_bottom = -10
	text.grow_vertical = Control.GROW_DIRECTION_BEGIN
	text.add_theme_constant_override("separation", -4)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text)
	_title = UIKit.label(title.to_upper(), 28, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, "heavy")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_title)
	_sub = UIKit.label(subtitle.to_upper(), 17, Color(0.86, 0.87, 0.9), HORIZONTAL_ALIGNMENT_LEFT, "ui")
	_sub.visible = subtitle != ""
	text.add_child(_sub)
	_info = UIKit.label("", 19, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, "title")
	_info.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_info.offset_left = -220
	_info.offset_right = -14
	_info.offset_top = -34
	_info.offset_bottom = -10
	add_child(_info)
	_tag_box = HBoxContainer.new()
	_tag_box.position = Vector2(10, 10)
	_tag_box.add_theme_constant_override("separation", 6)
	_tag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tag_box)
	_badge_box = HBoxContainer.new()
	_badge_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge_box.offset_left = -200
	_badge_box.offset_right = -10
	_badge_box.offset_top = 10
	_badge_box.alignment = BoxContainer.ALIGNMENT_END
	_badge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge_box)
	# Lock notice sits top-right (under any badge) so it never covers the title.
	_lock = UIKit.label("LOCKED", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, "heavy")
	_lock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lock.offset_left = -300
	_lock.offset_right = -12
	_lock.offset_top = 10
	_lock.add_theme_constant_override("outline_size", 6)
	_lock.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_lock.visible = false
	add_child(_lock)
	_frame = Panel.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.draw_center = false
	fsb.border_color = Color.WHITE
	fsb.set_border_width_all(4)
	_frame.add_theme_stylebox_override("panel", fsb)
	_frame.visible = false
	add_child(_frame)
	set_image(image)
	pressed.connect(func():
		if on_accept.is_valid() and not locked:
			on_accept.call())
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	resized.connect(func():
		pivot_offset = size * 0.5
		_title.add_theme_font_size_override("font_size", 34 if size.y > 250 else (28 if size.y > 130 else 23)))

func set_image(tex: Texture2D) -> UITile:
	_img.texture = tex
	if tex == null:
		var gt := GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, _tint.lightened(0.18))
		g.set_color(1, _tint.darkened(0.45))
		gt.gradient = g
		gt.fill_from = Vector2(0.0, 0.0)
		gt.fill_to = Vector2(1.0, 1.0)
		_img.texture = gt
		_img.stretch_mode = TextureRect.STRETCH_SCALE
	else:
		_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	return self

## Base colour for tiles without art.
func set_tint(c: Color) -> UITile:
	_tint = c
	if _img.texture is GradientTexture2D:
		set_image(null)
	return self

func set_title(t: String) -> UITile:
	_title.text = t.to_upper()
	return self

func set_subtitle(s: String) -> UITile:
	_sub.text = s.to_upper()
	_sub.visible = s != ""
	return self

func set_info(s: String, color := Color.WHITE) -> UITile:
	_info.text = s
	_info.add_theme_color_override("font_color", color)
	return self

func add_tag(text: String, color := UIKit.ACCENT) -> UITile:
	_tag_box.add_child(UIKit.tag(text, color))
	return self

func clear_tags() -> UITile:
	for c in _tag_box.get_children():
		c.queue_free()
	return self

func set_badge(c: Control) -> UITile:
	for x in _badge_box.get_children():
		x.queue_free()
	if c:
		_badge_box.add_child(c)
	return self

func set_locked(v: bool, why := "LOCKED") -> UITile:
	locked = v
	_lock.text = "LOCKED · " + why.to_upper()
	_lock.visible = v
	_img.modulate = Color(0.45, 0.45, 0.5) if v else Color.WHITE
	return self

func _on_focus(on: bool) -> void:
	_frame.visible = on
	z_index = 1 if on else 0
	var target := Vector2.ONE * (1.035 if on else 1.0)
	if bool(Settings.get_value("gameplay", "reduced_motion", false)):
		scale = target
	else:
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(self, "scale", target, 0.12)
	if on:
		Haptics.impact(0.08, 8)
		if on_focus.is_valid():
			on_focus.call()
