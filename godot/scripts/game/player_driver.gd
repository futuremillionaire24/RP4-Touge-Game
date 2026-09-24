class_name PlayerDriver
extends Node
## Feeds pad input to the player's car in NTSim, handles gear shifts, reverse, rewind,
## camera cycling and continuous haptics (curbs, ABS, limiter, slip).

signal rewind_started
signal rewind_finished(seconds: float)

var sim: NTSim
var car: CarView
var camera: ChaseCamera
var enabled := true
var rewinding := false
var _rewound := 0.0
var _brake_hold := 0.0
var _clutch_kick_timer := 0.0

func _physics_process(delta: float) -> void:
	if sim == null or car == null or car.car_id < 0:
		return
	var id := car.car_id
	# Rewind: hold to scrub back at 2x, release to resume.
	if Settings.get_value("assists", "rewind", true) and Pad.held("rewind") and enabled:
		if not rewinding:
			rewinding = true
			_rewound = 0.0
			sim.running = false
			rewind_started.emit()
		if sim.rewind_available() > delta * 2.0:
			_rewound += sim.rewind(delta * 2.0)
		Haptics.clear()
		return
	elif rewinding:
		rewinding = false
		sim.running = true
		if camera:
			camera.snap()
		rewind_finished.emit(_rewound)

	if not enabled:
		sim.set_input(id, 0.0, 0.0, 1.0, 0.0, 0.0)
		return
	var gearbox: int = Settings.get_value("assists", "gearbox", 0)
	var clutch := Pad.clutch() if gearbox == 2 else 0.0
	# Clutch-kick: quick tap or hold dips the clutch to flare engine RPM across all gearbox modes.
	if Pad.pressed("clutch"):
		_clutch_kick_timer = 0.16
	if _clutch_kick_timer > 0.0:
		_clutch_kick_timer -= delta
		clutch = 1.0
	elif gearbox != 2 and Pad.held("clutch"):
		clutch = 1.0

	# ---- Progressive steering curve: speed-dependent exponent (GT7/FH5 feel) ----
	var raw_steer := Pad.steer
	# Subtle deadzone for analog stick precision
	var deadzone := 0.04
	raw_steer = signf(raw_steer) * maxf(0.0, absf(raw_steer) - deadzone) / (1.0 - deadzone) if absf(raw_steer) > deadzone else 0.0
	# Speed-dependent progressive curve: linear at low speed, exponential at high speed
	var speed_k: float = clampf(float(car.telemetry.get("speed", 0.0)) / 25.0, 0.0, 1.0)
	var exponent := lerpf(1.2, 1.8, speed_k)  # More progressive at speed for stability
	var steer := signf(raw_steer) * pow(absf(raw_steer), exponent)
	sim.set_input(id, steer, Pad.throttle, Pad.brake, Pad.handbrake(), clutch)
	if Pad.pressed("shift_up"):
		sim.shift(id, 1)
	if Pad.pressed("shift_down"):
		sim.shift(id, -1)
	# Auto gearbox: hold brake at a standstill for 0.35 s to engage reverse.
	var speed: float = car.telemetry.get("speed", 0.0)
	_brake_hold = _brake_hold + delta if (Pad.brake > 0.6 and Pad.throttle < 0.05 and speed < 0.8) else 0.0
	sim.set_reverse_request(id, _brake_hold > 0.35)
	if Pad.pressed("camera") and camera:
		camera.cycle_mode()
	if Pad.pressed("lights"):
		car.set_lights(not car.lights_on)
	_haptics()

func _haptics() -> void:
	var t := car.telemetry
	if t.is_empty():
		return
	var curb := 0.0
	var slip := 0.0
	var loose := 0.0
	for i in range(4):
		var surf := int(car.wheel_value(i, 10))
		var contact := car.wheel_value(i, 6) > 0.5
		if not contact:
			continue
		if surf == TrackBuilder.Surf.CURB:
			curb = maxf(curb, 0.55)
		elif surf in [TrackBuilder.Surf.GRAVEL, TrackBuilder.Surf.DIRT, TrackBuilder.Surf.GRASS]:
			loose = maxf(loose, 0.25)
		slip = maxf(slip, clampf((car.wheel_value(i, 7) - 3.0) / 12.0, 0.0, 1.0))
	var speed_k := clampf(float(t.speed) / 20.0, 0.0, 1.0)
	Haptics.set_continuous("curb", curb * speed_k)
	Haptics.set_continuous("loose", loose * speed_k)
	var threshold_brake := 0.45 if t.abs else (0.3 if (Pad.brake > 0.65 and slip > 0.25) else 0.0)
	Haptics.set_continuous("abs", threshold_brake)
	Haptics.set_continuous("limiter", 0.2 if t.limiter else 0.0)
	Haptics.set_continuous("slip", slip * 0.15)
