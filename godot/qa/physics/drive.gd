extends Node3D
## QA physics harness: drives a car through the REAL input path (keyboard events -> Pad autoload
## -> PlayerDriver -> NTSim) on a flat pad, for each gearbox mode. Prints QA_ lines.
## Run: godot --headless --path . res://qa/physics/drive.tscn -- profile=qa_physics car=sylph_s2

var sim: NTSim
var view: CarView
var driver: PlayerDriver
var id := -1
var car_key := "sylph_s2"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("car="):
			car_key = a.substr(4)
	print("QA physics ticks/s=", Engine.physics_ticks_per_second)
	sim = NTSim.new()
	add_child(sim)
	var faces := PackedVector3Array()
	var surf := PackedByteArray()
	var flags := PackedByteArray()
	var t := 128.0
	for ix in range(-12, 12):
		for iz in range(-12, 12):
			var x := ix * t
			var z := iz * t
			faces.append_array([Vector3(x, 0, z), Vector3(x, 0, z + t), Vector3(x + t, 0, z + t), Vector3(x, 0, z), Vector3(x + t, 0, z + t), Vector3(x + t, 0, z)])
			surf.append_array([0, 0])
			flags.append_array([3, 3])
	sim.set_collision_chunk(1, faces, surf, flags)
	_run.call_deferred()

func _spawn(gearbox: int, overrides := {}) -> void:
	if view:
		view.queue_free()
		driver.queue_free()
		await get_tree().process_frame
	sim.clear_cars()
	Settings.set_value("assists", "gearbox", gearbox, false)
	id = sim.add_car(car_key, overrides, false, 1)
	var spec := sim.get_car_spec(id)
	sim.reset_car(id, Transform3D(Basis(), Vector3(0, spec.cg_height + 0.05, 1200)), 0.0)
	sim.set_assists(id, Settings.assists_dict())
	view = CarView.new()
	add_child(view)
	view.setup(sim, id, car_key, true)
	driver = PlayerDriver.new()
	driver.sim = sim
	driver.car = view
	add_child(driver)
	sim.running = true
	await _ticks(120)

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _ticks(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

func _tel() -> Dictionary:
	return sim.get_telemetry(id)

func _log(tag: String) -> void:
	var t := _tel()
	print("QA %-28s kmh=%7.1f gear=%2d rpm=%5.0f thr=%.2f brk=%.2f clutch=%.2f steer=%+.2f" % [tag, t.speed_kmh, t.gear, t.rpm, t.throttle, t.brake, t.clutch, t.steer])

func _run() -> void:
	var hz := Engine.physics_ticks_per_second
	# Pad shaping table (default settings).
	var c := Settings.section("controls")
	var line := "QA shape steer:"
	for v in [0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 0.9, 0.97, 1.0]:
		line += " %.2f->%.3f" % [v, Pad.shape(v, c.steer_deadzone, c.steer_linearity, c.steer_saturation)]
	print(line)
	line = "QA shape brake:"
	for v in [0.05, 0.3, 0.5, 0.6, 0.66, 0.7, 0.9]:
		line += " %.2f->%.3f" % [v, Pad.shape(v, c.brake_deadzone, c.brake_curve, 0.98)]
	print(line)
	for gb in [0, 1, 2]:
		await _spawn(gb)
		_log("gb%d rest" % gb)
		_key(KEY_W, true)
		for s in range(6):
			await _ticks(hz)
			_log("gb%d W held %ds" % [gb, s + 1])
			if gb > 0:
				# Upshift with E once per second (manual modes).
				_key(KEY_E, true)
				await _ticks(2)
				_key(KEY_E, false)
		_key(KEY_W, false)
		# Brake to a stop and keep holding S for reverse.
		_key(KEY_S, true)
		for s in range(8):
			await _ticks(hz)
			_log("gb%d S held %ds" % [gb, s + 1])
		_key(KEY_S, false)
		if gb > 0:
			# Manual: Q repeatedly into reverse from standstill, then W.
			for i in range(8):
				_key(KEY_Q, true)
				await _ticks(2)
				_key(KEY_Q, false)
				await _ticks(10)
			_log("gb%d after 8x Q" % gb)
			_key(KEY_W, true)
			await _ticks(hz * 2)
			_log("gb%d W 2s after Q" % gb)
			_key(KEY_W, false)
		# Keyboard steering ramp.
		_key(KEY_D, true)
		for i in range(4):
			await _ticks(hz / 10)
			_log("gb%d D held %.1fs" % [gb, (i + 1) * 0.1])
		_key(KEY_D, false)
		await _ticks(hz / 2)
	# Clutch-kick: in auto, hold Shift (clutch) + W at standstill 1.5 s, then release clutch.
	await _spawn(0)
	_key(KEY_SHIFT, true)
	_key(KEY_W, true)
	await _ticks(int(hz * 1.5))
	_log("clutch+W 1.5s")
	_key(KEY_SHIFT, false)
	await _ticks(hz)
	_log("clutch released 1s")
	_key(KEY_W, false)
	# Reversing in a straight line: does the skill system score it as a drift?
	await _spawn(0)
	var skills := SkillSystem.new()
	skills.sim = sim
	skills.car = view
	add_child(skills)
	var names := []
	skills.skill.connect(func(n, p): names.append("%s:%d" % [n, p]))
	_key(KEY_S, true)
	for s in range(10):
		await _ticks(hz)
		var t := _tel()
		print("QA reverse %2ds kmh=%6.1f drift_angle=%6.1f deg in_drift=%s drift_points=%.0f chain=%.0f x%d" % [s + 1, t.speed_kmh, rad_to_deg(t.drift_angle), skills.in_drift, skills.drift_points, skills.chain_points, skills.multiplier])
	_key(KEY_S, false)
	print("QA reverse skills fired: ", names)
	skills.queue_free()
	Settings.set_value("assists", "gearbox", 0, false)
	print("QA done")
	get_tree().quit()
