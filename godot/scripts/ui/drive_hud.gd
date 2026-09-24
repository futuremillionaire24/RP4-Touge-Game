class_name DriveHUD
extends Control
## Neon driving HUD sized for the 4.7" screen: tach arc + speed + gear bottom-right, assists and
## boost, race info top-left, FPS/thermal readout (toggle), rewind overlay.

var car: CarView
var skills: SkillSystem
var redline := 7500.0
var limiter := 7800.0
var max_boost := 0.0
var race_text := ""
var toast_text := ""
var _toast_t := 0.0
var rewinding := false
var _font: Font
var _rpm_smooth := 0.0

const NEON := Color(1.0, 0.18, 0.53)
const CYAN := Color(0.15, 0.91, 1.0)
const WHITE := Color(0.95, 0.96, 1.0)
const DIM := Color(1, 1, 1, 0.25)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

func bind(view: CarView, spec: Dictionary) -> void:
	car = view
	redline = spec.redline_rpm
	limiter = spec.limiter_rpm
	max_boost = spec.max_boost

func toast(text: String, seconds := 2.5) -> void:
	toast_text = text
	_toast_t = seconds

func _process(delta: float) -> void:
	_toast_t = maxf(0.0, _toast_t - delta)
	queue_redraw()

func _draw() -> void:
	var s: float = Settings.get_value("gameplay", "hud_scale", 1.0)
	var vp := get_viewport_rect().size
	if car and not car.telemetry.is_empty():
		_draw_cluster(vp, s)
	if skills:
		_draw_skills(vp, s)
	# Top-left race info.
	if race_text != "":
		draw_string(_font, Vector2(24, 44) * Vector2.ONE, race_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * s), WHITE)
	if _toast_t > 0.0:
		var a := clampf(_toast_t * 2.0, 0.0, 1.0)
		var size := int(30 * s)
		var w := _font.get_string_size(toast_text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
		draw_string(_font, Vector2((vp.x - w) * 0.5, vp.y * 0.28), toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(NEON, a))
	if rewinding:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.1, 0.2, 0.5, 0.18))
		var t := "<<  REWIND"
		draw_string(_font, Vector2(vp.x * 0.5 - 70, 70), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * s), CYAN)
	if Settings.get_value("graphics", "show_fps", false) or OS.is_debug_build():
		var ft := "%d fps  %.1f ms  1%%: %.1f  x%.2f  L%d" % [roundi(Perf.fps), Perf.avg_ms, Perf.low1_ms, Perf.scale, Perf.level]
		if Perf.thermal >= 0.0:
			ft += "  T %.2f" % Perf.thermal
		draw_string(_font, Vector2(vp.x - 420, 24), ft, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 1, 0.8, 0.8))

## Skill chain ticker (bottom centre): chain points x multiplier, combo timer bar, recent skills.
func _draw_skills(vp: Vector2, s: float) -> void:
	var cx := vp.x * 0.5
	var base_y := vp.y - 118.0 * s
	if skills.chain_points > 0.0:
		var total := int(skills.chain_points)
		var txt := "%s" % RaceHUD._group(total)
		var fs := int(34 * s)
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, Vector2(cx - w * 0.5 - 30 * s, base_y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, WHITE)
		draw_string(_font, Vector2(cx + w * 0.5 - 18 * s, base_y), "x%d" % skills.multiplier, HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * s), NEON)
		var frac := clampf(skills.combo_timer / SkillSystem.COMBO_TIME, 0.0, 1.0)
		draw_rect(Rect2(Vector2(cx - 90 * s, base_y + 8 * s), Vector2(180 * s, 4 * s)), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(Vector2(cx - 90 * s, base_y + 8 * s), Vector2(180 * s * frac, 4 * s)), CYAN)
	var y := base_y - 42.0 * s
	for r in skills.recent:
		var a := clampf(float(r.t), 0.0, 1.0)
		var label := "%s  +%d" % [r.name.to_upper(), int(r.points)] if int(r.points) > 0 else String(r.name).to_upper()
		var fs2 := int(18 * s)
		var w2 := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		draw_string(_font, Vector2(cx - w2 * 0.5, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(CYAN, a))
		y -= 22.0 * s

func _draw_cluster(vp: Vector2, s: float) -> void:
	var t: Dictionary = car.telemetry
	var center := Vector2(vp.x - 150 * s, vp.y - 120 * s)
	var r := 92.0 * s
	var rpm: float = t.rpm
	_rpm_smooth = lerpf(_rpm_smooth, rpm, 0.45)
	var max_rpm := ceilf(limiter / 1000.0) * 1000.0
	var a0 := deg_to_rad(150.0)
	var a1 := deg_to_rad(390.0)

	# ---- GT7-style neon tach arc ----
	# Background arc (subtle)
	draw_arc(center, r, a0, a1, 72, Color(1, 1, 1, 0.12), 5.0 * s, true)
	# Outer glow halo
	draw_arc(center, r + 2 * s, a0, a1, 72, Color(NEON.r, NEON.g, NEON.b, 0.08), 10.0 * s, true)

	# Redline zone with pulsing glow
	var red_a := lerpf(a0, a1, redline / max_rpm)
	var red_pulse := 0.6 + 0.15 * sin(Time.get_ticks_msec() / 150.0)
	var red_col := Color(1, 0.08, 0.15, red_pulse) if _rpm_smooth > redline * 0.9 else Color(1, 0.08, 0.15, 0.55)
	draw_arc(center, r, red_a, a1, 28, red_col, 6.0 * s, true)

	# Fill arc: gradient from cyan → pink → red as RPM climbs
	var fill_frac := clampf(_rpm_smooth / max_rpm, 0.0, 1.0)
	var fill_a := lerpf(a0, a1, fill_frac)
	var fill_col: Color
	if fill_frac < 0.65:
		fill_col = CYAN.lerp(NEON, fill_frac / 0.65)
	else:
		fill_col = NEON.lerp(Color(1, 0.95, 0.2), (fill_frac - 0.65) / 0.35)
	draw_arc(center, r, a0, fill_a, 72, fill_col, 8.0 * s, true)
	# Inner bright core
	draw_arc(center, r - 1 * s, a0, fill_a, 72, Color(fill_col, 0.5), 3.0 * s, true)

	# Tick marks: numbered every 1000, minor ticks every 500
	var k := 0
	while k * 1000.0 <= max_rpm:
		var a := lerpf(a0, a1, (k * 1000.0) / max_rpm)
		var tick_r := r - 14 * s
		var tick_end := r - 6 * s
		var p0 := center + Vector2(cos(a), sin(a)) * tick_r
		var p1 := center + Vector2(cos(a), sin(a)) * tick_end
		# Major tick line
		draw_line(p0, p1, Color(1, 1, 1, 0.35), 1.5 * s, true)
		# Number
		var num_pos := center + Vector2(cos(a), sin(a)) * (tick_r - 10 * s)
		draw_string(_font, num_pos - Vector2(4, -4) * s, str(k), HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), Color(1, 1, 1, 0.55))
		# Minor tick at 500
		if (k + 0.5) * 1000.0 < max_rpm:
			var a_half := lerpf(a0, a1, ((k + 0.5) * 1000.0) / max_rpm)
			var p0h := center + Vector2(cos(a_half), sin(a_half)) * (r - 10 * s)
			var p1h := center + Vector2(cos(a_half), sin(a_half)) * (r - 6 * s)
			draw_line(p0h, p1h, Color(1, 1, 1, 0.2), 1.0 * s, true)
		k += 1

	# ---- Speed display ----
	var metric: bool = Settings.get_value("gameplay", "units_metric", true)
	var spd := absf(float(t.speed_kmh))
	var spd_val := spd if metric else spd * 0.621371
	var spd_str := "%d" % roundi(spd_val)
	var fs := int(48 * s)
	var sw := _font.get_string_size(spd_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, center + Vector2(-sw * 0.5, 14 * s), spd_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, WHITE)
	var unit_str := "km/h" if metric else "mph"
	var us := _font.get_string_size(unit_str, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s)).x
	draw_string(_font, center + Vector2(-us * 0.5, 34 * s), unit_str, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), Color(1, 1, 1, 0.4))

	# ---- Gear indicator: large with neon accent ----
	var g: int = t.gear
	var gs := "R" if g < 0 else ("N" if g == 0 else str(g))
	var gear_col: Color
	if t.get("limiter", false):
		gear_col = Color(1, 0.2, 0.2)
	elif t.get("shifting", false):
		gear_col = Color(1, 1, 1, 0.6)
	else:
		gear_col = CYAN
	draw_string(_font, center + Vector2(r * 0.52, r * 0.92), gs, HORIZONTAL_ALIGNMENT_LEFT, -1, int(42 * s), gear_col)

	# ---- Shift light: dual-color flash at redline ----
	if _rpm_smooth > redline * 0.93 and g > 0:
		var flash_phase := fmod(Time.get_ticks_msec() / 120.0, 2.0)
		var shift_col := Color(1, 0.15, 0.2) if flash_phase < 1.0 else Color(0.2, 0.8, 1.0)
		draw_circle(center + Vector2(0, -r - 18 * s), 7 * s, shift_col)
		# Subtle glow around shift light
		draw_circle(center + Vector2(0, -r - 18 * s), 12 * s, Color(shift_col, 0.15))

	# ---- Boost gauge: gradient fill with neon accents ----
	if max_boost > 0.0:
		var boost_frac := clampf(float(t.boost) / max_boost, 0, 1)
		var bb := Rect2(center + Vector2(-r, r * 0.92), Vector2(r * 1.2, 6 * s))
		draw_rect(bb, Color(1, 1, 1, 0.08))
		var boost_col := CYAN.lerp(NEON, boost_frac)
		draw_rect(Rect2(bb.position, Vector2(bb.size.x * boost_frac, bb.size.y)), boost_col)
		# Bright edge at the fill front
		if boost_frac > 0.02:
			draw_rect(Rect2(bb.position + Vector2(bb.size.x * boost_frac - 2 * s, 0), Vector2(2 * s, bb.size.y)), Color(boost_col, 1.0).lightened(0.4))
		draw_string(_font, bb.position + Vector2(0, -4 * s), "BOOST %.1f" % float(t.boost), HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), Color(1, 1, 1, 0.4))

	# ---- Assist indicators with subtle background pills ----
	var ax := center.x - r - 45 * s
	var ay := center.y + r * 0.3
	for flag in [["ABS", t.abs], ["TCS", t.tcs], ["STM", t.stm]]:
		if flag[1]:
			# Background pill
			draw_rect(Rect2(Vector2(ax - 4 * s, ay - 14 * s), Vector2(38 * s, 18 * s)), Color(1, 0.75, 0.2, 0.12))
			draw_string(_font, Vector2(ax, ay), flag[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s), Color(1, 0.78, 0.22))
		ay += 20 * s

	# ---- Drift angle meter: larger with neon glow ----
	var da := absf(rad_to_deg(float(t.drift_angle)))
	if da > 8.0 and spd > 20.0:
		var drift_str := "%d°" % roundi(da)
		var da_fs := int(28 * s)
		var da_w := _font.get_string_size(drift_str, HORIZONTAL_ALIGNMENT_LEFT, -1, da_fs).x
		var da_pos := Vector2(vp.x * 0.5 - da_w * 0.5, vp.y - 38)
		# Glow behind
		draw_string(_font, da_pos + Vector2(0, 1), drift_str, HORIZONTAL_ALIGNMENT_LEFT, -1, da_fs, Color(NEON, 0.25))
		draw_string(_font, da_pos, drift_str, HORIZONTAL_ALIGNMENT_LEFT, -1, da_fs, NEON)
