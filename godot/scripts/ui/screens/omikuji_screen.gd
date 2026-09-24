class_name OmikujiScreen
extends MenuScreen
## Super Prize Spins: festival level rewards inspired by Forza Horizon.
## Spin the reel to win rare European sports cars, cash jackpots, and festival XP.

var _draws: Label
var _stage2d: Control
var _slip: PanelContainer
var _badge_label: Label
var _fortune_name: Label
var _reward: Label
var _state := "idle" # idle, spinning, reveal
var _t := 0.0
var _result := {}
var _rng := RandomNumberGenerator.new()
var _spin_angle := 0.0

func build() -> void:
	_rng.randomize()
	var col := make_column(520)
	col.add_child(UIKit.header("Super Wheelspin", "", "Festival Rewards  ·  earn free wheelspins on every level up"))
	_draws = UIKit.label("", 24, UIKit.AMBER)
	col.add_child(_draws)
	var draw := UIRow.new("SPIN THE WHEEL")
	draw.on_accept = _draw_fortune
	col.add_child(draw)
	var odds := UIKit.label(_odds_text(), 16, UIKit.DIM)
	odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	odds.custom_minimum_size = Vector2(500, 0)
	col.add_child(odds)
	_stage2d = Control.new()
	_stage2d.position = Vector2(760, 110)
	_stage2d.size = Vector2(460, 520)
	_stage2d.draw.connect(_draw_spinner)
	_stage2d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage2d)
	_slip = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.15, 0.96)
	sb.border_color = UIKit.NEON
	sb.set_border_width_all(2)
	sb.set_content_margin_all(24)
	sb.set_corner_radius_all(6)
	_slip.add_theme_stylebox_override("panel", sb)
	_slip.position = Vector2(810, 150)
	_slip.custom_minimum_size = Vector2(360, 420)
	_slip.visible = false
	add_child(_slip)
	var sv := VBoxContainer.new()
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	sv.add_theme_constant_override("separation", 12)
	_slip.add_child(sv)
	_badge_label = UIKit.label("", 28, UIKit.NEON, HORIZONTAL_ALIGNMENT_CENTER)
	sv.add_child(_badge_label)
	_fortune_name = UIKit.label("", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	sv.add_child(_fortune_name)
	_reward = UIKit.label("", 24, UIKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward.custom_minimum_size = Vector2(310, 0)
	sv.add_child(_reward)
	set_hints([["A", "Spin"], ["B", "Back"]])
	stage.clear()

func refresh() -> void:
	var n := int(Profile.data.omikuji)
	_draws.text = "%d spin%s available" % [n, "" if n == 1 else "s"] if n > 0 else "No spins left — earn XP in events to level up"

func _odds_text() -> String:
	var total := 0
	for f in Profile.FORTUNES:
		total += int(f.weight)
	var parts := []
	for f in Profile.FORTUNES:
		parts.append("%s %d%%" % [f.get("badge", f.name), roundi(100.0 * f.weight / total)])
	return "  ·  ".join(parts)

func _draw_fortune() -> void:
	if _state == "spinning":
		return
	if int(Profile.data.omikuji) <= 0:
		festival.toast("NO SPINS LEFT — EARN XP TO LEVEL UP")
		return
	_slip.visible = false
	stage.clear()
	_state = "spinning"
	_t = 0.0
	_result = Profile.draw_omikuji(_rng)

func _process(delta: float) -> void:
	if _state == "spinning":
		_t += delta
		var spd := maxf(0.0, 18.0 * (1.6 - _t))
		_spin_angle += spd * delta
		if int(_t * 14.0) != int((_t - delta) * 14.0):
			Haptics.impact(0.35, 20)
		if _t > 1.6:
			_reveal()
	_stage2d.queue_redraw()

func _reveal() -> void:
	_state = "reveal"
	var f: Dictionary = _result.fortune
	var badge: String = f.get("badge", "PRIZE")
	_badge_label.text = badge
	_fortune_name.text = f.name
	match _result.kind:
		"car":
			var car := CarData.get_car(_result.car)
			_reward.text = "NEW CAR WON!\n%s\n%s" % [car.name, CarData.class_label(int(CarData.STOCK_PI[_result.car]))]
			stage.show_entry(Profile.data.garage[int(_result.index)], true)
		"credits":
			_reward.text = "+%s" % UIKit.money(int(_result.amount))
		"xp":
			_reward.text = "+%d FESTIVAL XP" % int(_result.amount)
	_slip.visible = true
	UIKit.fade_in(_slip, 0.0)
	Haptics.impact(0.8 if badge == "LEGENDARY" else 0.4, 120)
	refresh()

func _draw_spinner() -> void:
	if _state == "reveal":
		return
	var c := Vector2(230, 260)
	var r := 150.0
	var segs := 8
	var colors := [
		Color(0.91, 0.64, 0.09), # Amber Gold
		Color(0.18, 0.42, 0.31), # British Racing Green
		Color(0.86, 0.16, 0.16), # Racing Red
		Color(0.20, 0.35, 0.75), # Cobalt Blue
		Color(0.70, 0.25, 0.85), # Royal Purple
		Color(0.85, 0.50, 0.15), # Orange
		Color(0.15, 0.60, 0.65), # Cyan Teal
		Color(0.35, 0.35, 0.40), # Gunmetal
	]
	# Outer rim
	_stage2d.draw_circle(c, r + 14.0, Color(0.15, 0.15, 0.20))
	_stage2d.draw_arc(c, r + 14.0, 0.0, TAU, 64, UIKit.NEON, 3.0)
	# Wheel segments
	for i in range(segs):
		var a1 := _spin_angle + i * (TAU / segs)
		var a2 := _spin_angle + (i + 1) * (TAU / segs)
		var pts := PackedVector2Array([c])
		var steps := 8
		for s in range(steps + 1):
			var a := lerpf(a1, a2, float(s) / steps)
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		_stage2d.draw_colored_polygon(pts, colors[i % colors.size()])
		_stage2d.draw_line(c, c + Vector2(cos(a1), sin(a1)) * r, Color(0.08, 0.08, 0.12), 2.0)
	# Center hub
	_stage2d.draw_circle(c, 42.0, Color(0.10, 0.10, 0.15))
	_stage2d.draw_arc(c, 42.0, 0.0, TAU, 32, UIKit.NEON, 2.0)
	_stage2d.draw_string(ThemeDB.fallback_font, c + Vector2(-22, 6), "GT", HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color.WHITE)
	# Pointer at top
	var ptr := PackedVector2Array([
		Vector2(c.x, c.y - r - 20.0),
		Vector2(c.x - 14.0, c.y - r - 2.0),
		Vector2(c.x + 14.0, c.y - r - 2.0),
	])
	_stage2d.draw_colored_polygon(ptr, UIKit.NEON)
