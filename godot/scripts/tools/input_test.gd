extends Control
## M0 input test: live view of every joypad axis and button (raw), the shaped driving values
## and the mapped actions. A / X trigger rumble tests; Start + Select exits.

var _font: Font
var _log := []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	Pad.device_changed.connect(func(has): _log.append("device %s" % ("connected" if has else "disconnected")))

func _process(_delta: float) -> void:
	if Pad.pressed("handbrake"):
		Haptics.impact(0.4, 120)
		_log.append("rumble 0.4 / 120 ms")
	if Pad.pressed("shift_down"):
		Haptics.impact(1.0, 300)
		_log.append("rumble 1.0 / 300 ms")
	if Pad.held("pause") and Pad.held("map"):
		get_tree().quit()
	if _log.size() > 8:
		_log = _log.slice(_log.size() - 8)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.03, 0.02, 0.06))
	var raw := Pad.raw_state()
	var y := 34.0
	draw_string(_font, Vector2(24, y), "INPUT TEST — %s (device %d)" % [raw.name, raw.device], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.2, 0.55))
	y += 34
	var names := ["LX", "LY", "RX", "RY", "L2", "R2"]
	for i in range(raw.axes.size()):
		var v: float = raw.axes[i]
		var label: String = names[i] if i < names.size() else "A%d" % i
		var x0 := 24.0
		draw_string(_font, Vector2(x0, y + 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		var bar := Rect2(Vector2(x0 + 40, y), Vector2(300, 14))
		draw_rect(bar, Color(1, 1, 1, 0.15))
		var mid := bar.position.x + bar.size.x * 0.5
		var w := v * bar.size.x * 0.5
		draw_rect(Rect2(Vector2(minf(mid, mid + w), y), Vector2(absf(w), 14)), Color(0.15, 0.9, 1))
		draw_string(_font, Vector2(x0 + 350, y + 12), "%+.3f" % v, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		y += 22
	y += 10
	var bx := 24.0
	for b in range(raw.buttons.size()):
		var on: bool = raw.buttons[b]
		draw_rect(Rect2(Vector2(bx, y), Vector2(34, 26)), Color(1, 0.2, 0.55) if on else Color(1, 1, 1, 0.12))
		draw_string(_font, Vector2(bx + 6, y + 18), str(b), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		bx += 40
		if bx > 620:
			bx = 24
			y += 32
	y += 50
	draw_string(_font, Vector2(24, y), "steer %+.3f   throttle %.3f   brake %.3f   handbrake %.0f   look (%.2f, %.2f)" % [Pad.steer, Pad.throttle, Pad.brake, Pad.handbrake(), Pad.look.x, Pad.look.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	y += 26
	var held := []
	for a in Pad.ACTIONS:
		if Pad.held(a):
			held.append(a)
	draw_string(_font, Vector2(24, y), "actions: " + ", ".join(held), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 1, 0.7))
	var lx := 700.0
	var ly := 80.0
	draw_string(_font, Vector2(lx, ly - 24), "A: rumble light   X: rumble strong   Start+Select: exit", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
	for line in _log:
		draw_string(_font, Vector2(lx, ly), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
		ly += 20
