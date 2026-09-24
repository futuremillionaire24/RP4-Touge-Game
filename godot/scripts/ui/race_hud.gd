class_name RaceHUD
extends Control
## Race overlay: countdown lights, position, lap, timer, split delta, standings tower, flash
## messages and the results panel.

const NEON := Color(1.0, 0.18, 0.53)
const CYAN := Color(0.15, 0.91, 1.0)
const WHITE := Color(0.95, 0.96, 1.0)

var race: RaceManager
var countdown_value := -1.0
var split_delta := 0.0
var split_timer := 0.0
var _flash_text := ""
var _flash_col := Color.WHITE
var _flash_t := 0.0
var _result := {}
var _font: Font

static func fmt_time(t: float) -> String:
	if t < 0.0:
		return "--:--.---"
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%06.3f" % [m, s]

static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

func begin(r: RaceManager) -> void:
	race = r
	_result = {}
	visible = true

func end() -> void:
	race = null
	visible = false

func flash(text: String, col: Color) -> void:
	_flash_text = text
	_flash_col = col
	_flash_t = 2.5

func show_results(result: Dictionary) -> void:
	_result = result

func _process(delta: float) -> void:
	_flash_t = maxf(0.0, _flash_t - delta)
	split_timer = maxf(0.0, split_timer - delta)
	queue_redraw()

func _draw() -> void:
	if race == null:
		return
	var vp := get_viewport_rect().size
	var s: float = Settings.get_value("gameplay", "hud_scale", 1.0)
	if not _result.is_empty():
		_draw_results(vp, s)
		return
	# Countdown lights.
	if countdown_value > 0.0:
		var n := int(ceil(countdown_value))
		var cx := vp.x * 0.5
		for i in range(3):
			var on := i < 4 - n
			var col := Color(1, 0.15, 0.2) if on else Color(0.2, 0.05, 0.08)
			draw_circle(Vector2(cx + (i - 1) * 70 * s, vp.y * 0.25), 26 * s, col)
		if n <= 3:
			_center_text(str(n), vp.y * 0.42, int(72 * s), WHITE)
		return
	if countdown_value > -1.5 and race.state == RaceManager.State.RACING and race.race_time < 1.2:
		_center_text("GO!", vp.y * 0.42, int(80 * s), Color(0.3, 1.0, 0.5))
	# Position + lap + time (top-left block).
	var pos := race.position_of(race.player.car_id)
	var total := race.cars.size()
	draw_string(_font, Vector2(24, 64) * s, ordinal(pos), HORIZONTAL_ALIGNMENT_LEFT, -1, int(52 * s), NEON)
	draw_string(_font, Vector2(24 + 110 * s, 64 * s), "/ %d" % total, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * s), WHITE)
	var y := 100.0 * s
	if race.route.closed:
		var t := race.sim.get_telemetry(race.player.car_id)
		var lap := clampi(int(t.lap) + 1, 1, race.laps)
		draw_string(_font, Vector2(26 * s, y), "LAP %d / %d" % [lap, race.laps], HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * s), WHITE)
		y += 28 * s
	else:
		var prog := clampf(race.progress_of(race.player.car_id) / maxf(race.finish_distance - race.start_distance, 1.0), 0.0, 1.0)
		draw_rect(Rect2(Vector2(26 * s, y - 14 * s), Vector2(180 * s, 8 * s)), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(Vector2(26 * s, y - 14 * s), Vector2(180 * s * prog, 8 * s)), CYAN)
		y += 16 * s
	draw_string(_font, Vector2(26 * s, y), fmt_time(race.race_time), HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * s), WHITE)
	if race.best_lap < INF:
		draw_string(_font, Vector2(26 * s, y + 24 * s), "BEST " + fmt_time(race.best_lap), HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), Color(1, 1, 1, 0.6))
	if split_timer > 0.0:
		var col := Color(0.3, 1.0, 0.5) if split_delta <= 0.0 else Color(1.0, 0.3, 0.3)
		_center_text("%+.3f" % split_delta, vp.y * 0.2, int(30 * s), col)
	# Standings tower (right).
	var order := race.standings()
	var ty := 70.0 * s
	for i in range(mini(order.size(), 8)):
		var id: int = order[i]
		var is_player := id == race.player.car_id
		var name: String = "YOU" if is_player else CarData.get_car(_key_of(id)).name
		var col := NEON if is_player else Color(1, 1, 1, 0.75)
		draw_rect(Rect2(Vector2(vp.x - 230 * s, ty - 18 * s), Vector2(206 * s, 24 * s)), Color(0, 0, 0, 0.35))
		draw_string(_font, Vector2(vp.x - 222 * s, ty), "%d  %s" % [i + 1, name], HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), col)
		ty += 26 * s
	if _flash_t > 0.0:
		_center_text(_flash_text, vp.y * 0.33, int(34 * s), Color(_flash_col, clampf(_flash_t, 0.0, 1.0)))

func _key_of(id: int) -> String:
	for c in race.cars:
		if c.car_id == id:
			return c.key
	return ""

func _center_text(text: String, y: float, size: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, Vector2((get_viewport_rect().size.x - w) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_results(vp: Vector2, s: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.01, 0.05, 0.82))
	var ev := EventData.get_event(_result.event)
	_center_text(ev.get("name", "").to_upper(), 90 * s, int(34 * s), CYAN)
	_center_text(ordinal(_result.position), 170 * s, int(80 * s), NEON)
	var y := 230.0 * s
	var x0 := vp.x * 0.5 - 300 * s
	for i in range(_result.rows.size()):
		var r: Dictionary = _result.rows[i]
		var col := NEON if r.player else Color(1, 1, 1, 0.8)
		draw_string(_font, Vector2(x0, y), "%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * s), col)
		draw_string(_font, Vector2(x0 + 50 * s, y), ("YOU — " if r.player else "") + r.car, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * s), col)
		draw_string(_font, Vector2(x0 + 380 * s, y), fmt_time(r.time) if r.time > 0.0 else "DNF", HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * s), col)
		y += 30 * s
	y += 20 * s
	_center_text("+ ¥%s     + %d XP" % [_group(_result.credits), _result.xp], y, int(28 * s), Color(1.0, 0.85, 0.3))
	_center_text("Press A to continue", vp.y - 50 * s, int(20 * s), Color(1, 1, 1, 0.6))

static func _group(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
