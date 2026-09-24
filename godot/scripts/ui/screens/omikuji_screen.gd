class_name OmikujiScreen
extends MenuScreen
## Omikuji (shrine fortune) draws, earned on every festival level-up. Shake the hexagonal
## box, a numbered stick drops, and the paper slip unfolds with your fortune: from 大吉 (a free
## car) through credit and XP blessings down to 凶 (a small consolation — tie it to the tree).

var _draws: Label
var _stage2d: Control
var _slip: PanelContainer
var _fortune_kanji: Label
var _fortune_name: Label
var _reward: Label
var _state := "idle" # idle, shaking, reveal
var _t := 0.0
var _result := {}
var _rng := RandomNumberGenerator.new()
var _stick_no := 0

func build() -> void:
	_rng.randomize()
	var col := make_column(520)
	col.add_child(UIKit.header("Omikuji", "御神籤", "Shrine fortunes · one draw per festival level"))
	_draws = UIKit.label("", 24, UIKit.AMBER)
	col.add_child(_draws)
	var draw := UIRow.new("DRAW A FORTUNE")
	draw.on_accept = _draw_fortune
	col.add_child(draw)
	var odds := UIKit.label(_odds_text(), 16, UIKit.DIM)
	odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	odds.custom_minimum_size = Vector2(500, 0)
	col.add_child(odds)
	_stage2d = Control.new()
	_stage2d.position = Vector2(760, 110)
	_stage2d.size = Vector2(460, 520)
	_stage2d.draw.connect(_draw_box)
	_stage2d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage2d)
	_slip = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.95, 0.9)
	sb.border_color = Color(0.75, 0.1, 0.12)
	sb.set_border_width_all(3)
	sb.set_content_margin_all(18)
	_slip.add_theme_stylebox_override("panel", sb)
	_slip.position = Vector2(820, 150)
	_slip.custom_minimum_size = Vector2(340, 420)
	_slip.visible = false
	add_child(_slip)
	var sv := VBoxContainer.new()
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	_slip.add_child(sv)
	_fortune_kanji = UIKit.label("", 110, Color(0.75, 0.08, 0.1), HORIZONTAL_ALIGNMENT_CENTER)
	sv.add_child(_fortune_kanji)
	_fortune_name = UIKit.label("", 24, Color(0.15, 0.1, 0.1), HORIZONTAL_ALIGNMENT_CENTER)
	sv.add_child(_fortune_name)
	_reward = UIKit.label("", 22, Color(0.1, 0.1, 0.12), HORIZONTAL_ALIGNMENT_CENTER)
	_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward.custom_minimum_size = Vector2(300, 0)
	sv.add_child(_reward)
	set_hints([["A", "Draw"], ["B", "Back"]])
	stage.clear()

func refresh() -> void:
	var n := int(Profile.data.omikuji)
	_draws.text = "%d draw%s available" % [n, "" if n == 1 else "s"] if n > 0 else "No draws — level up at the festival to earn more"

func _odds_text() -> String:
	var total := 0
	for f in Profile.FORTUNES:
		total += int(f.weight)
	var parts := []
	for f in Profile.FORTUNES:
		parts.append("%s %s %d%%" % [f.kanji, f.name, roundi(100.0 * f.weight / total)])
	return "  ·  ".join(parts)

func _draw_fortune() -> void:
	if _state == "shaking":
		return
	if int(Profile.data.omikuji) <= 0:
		festival.toast("NO DRAWS LEFT — EARN XP TO LEVEL UP")
		return
	_slip.visible = false
	stage.clear()
	_state = "shaking"
	_t = 0.0
	_stick_no = _rng.randi_range(1, 100)
	_result = Profile.draw_omikuji(_rng)

func _process(delta: float) -> void:
	if _state == "shaking":
		_t += delta
		if int(_t * 12.0) != int((_t - delta) * 12.0):
			Haptics.impact(0.35, 25)
		if _t > 1.6:
			_reveal()
	_stage2d.queue_redraw()

func _reveal() -> void:
	_state = "reveal"
	var f: Dictionary = _result.fortune
	_fortune_kanji.text = f.kanji
	_fortune_name.text = "No. %d  ·  %s" % [_stick_no, f.name]
	match _result.kind:
		"car":
			var car := CarData.get_car(_result.car)
			_reward.text = "A car appears!\n%s\n%s" % [car.name, CarData.class_label(int(CarData.STOCK_PI[_result.car]))]
			stage.show_entry(Profile.data.garage[int(_result.index)], true)
		"credits":
			_reward.text = ("%s\n(tie this one to the shrine tree)" if f.kanji == "凶" else "%s") % UIKit.money(int(_result.amount))
		"xp":
			_reward.text = "+%d XP" % int(_result.amount)
	_slip.visible = true
	UIKit.fade_in(_slip, 0.0)
	Haptics.impact(0.8 if f.kanji == "大吉" else 0.4, 120)
	refresh()

func _draw_box() -> void:
	if _state == "reveal":
		return
	# Hexagonal wooden omikuji box, shaken with a decaying wobble.
	var c := Vector2(230, 260)
	var shake := 0.0
	if _state == "shaking":
		shake = sin(_t * 38.0) * 0.18 * clampf(1.6 - _t, 0.0, 1.0) + sin(_t * 23.0) * 0.08
	var xf := Transform2D(shake, c)
	var pts := PackedVector2Array()
	for i in range(6):
		var a := TAU * i / 6.0 + PI / 6.0
		pts.append(xf * Vector2(cos(a) * 70.0, sin(a) * 70.0 * 0.45 - 110.0))
	var body := PackedVector2Array([xf * Vector2(-61, -110), xf * Vector2(61, -110), xf * Vector2(61, 150), xf * Vector2(-61, 150)])
	_stage2d.draw_colored_polygon(body, Color(0.55, 0.27, 0.1))
	_stage2d.draw_colored_polygon(pts, Color(0.68, 0.36, 0.14))
	_stage2d.draw_line(xf * Vector2(-61, -110), xf * Vector2(-61, 150), Color(0.35, 0.16, 0.05), 3.0)
	_stage2d.draw_line(xf * Vector2(61, -110), xf * Vector2(61, 150), Color(0.35, 0.16, 0.05), 3.0)
	_stage2d.draw_rect(Rect2(xf * Vector2(-40, -30), Vector2(80, 120)), Color(0.93, 0.9, 0.82))
	_stage2d.draw_string(ThemeDB.fallback_font, xf * Vector2(-30, 20), "御神籤", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.7, 0.08, 0.1))
	if _state == "shaking" and _t > 1.1:
		# The numbered stick slides out of the hole.
		var out := clampf((_t - 1.1) / 0.4, 0.0, 1.0)
		var top := xf * Vector2(0, -110 - 90.0 * out)
		_stage2d.draw_line(xf * Vector2(0, -110), top, Color(0.95, 0.85, 0.6), 8.0)
		_stage2d.draw_string(ThemeDB.fallback_font, top + Vector2(14, 10), str(_stick_no), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.AMBER)
