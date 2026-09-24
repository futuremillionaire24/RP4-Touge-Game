extends Node
## Rumble: the RP4 Pro's motor is the handheld vibrator (Input.vibrate_handheld, needs the
## install-time VIBRATE permission); desktop pads use joypad vibration. Continuous effects
## (curbs, ABS, limiter) are mixed into short pulses so they never queue up.

var _continuous := {} # name -> strength 0..1
var _pulse_timer := 0.0
var _cooldown := 0.0

func strength() -> float:
	return Settings.get_value("controls", "vibration", 0.8)

## One-shot impact: `amount` 0..1, duration in ms.
func impact(amount: float, duration_ms: int = 80) -> void:
	var s := clampf(amount, 0.0, 1.0) * strength()
	if s < 0.03 or _cooldown > 0.0:
		return
	_cooldown = 0.03
	_emit(s, duration_ms)

## Sets a continuous effect level (0 disables). Mixed and re-triggered every 50 ms.
func set_continuous(name: String, amount: float) -> void:
	if amount <= 0.01:
		_continuous.erase(name)
	else:
		_continuous[name] = clampf(amount, 0.0, 1.0)

func clear() -> void:
	_continuous.clear()
	if Pad.device >= 0:
		Input.stop_joy_vibration(Pad.device)

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_pulse_timer -= delta
	if _pulse_timer > 0.0 or _continuous.is_empty():
		return
	_pulse_timer = 0.05
	var total := 0.0
	for v in _continuous.values():
		total = maxf(total, v)
	total *= strength()
	if total > 0.03:
		_emit(total, 60)

func _emit(s: float, ms: int) -> void:
	if OS.has_feature("android"):
		Input.vibrate_handheld(ms, s)
	elif Pad.device >= 0:
		Input.start_joy_vibration(Pad.device, s * 0.6, s, ms / 1000.0)
