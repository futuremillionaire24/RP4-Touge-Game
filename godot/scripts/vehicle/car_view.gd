class_name CarView
extends Node3D
## Visual + feedback side of one simulated car: pose, wheels (spin/steer/suspension), brake and
## head lights, dent deformation, collision haptics. Reads everything from NTSim each physics
## tick; physics interpolation smooths it to the display rate.

signal collided(impulse: float, position: Vector3, other: int)

var sim: NTSim
var car_id := -1
var key := ""
var audio_key := "" # donor car key after an engine swap
var is_player := false
var telemetry := {}
var wheel_data := PackedFloat32Array()
var visual: Node3D
var audio: CarAudio
var _wheels := []
var _paint: ShaderMaterial
var _brake_lights := []
var _headlights := []
var _taillights := []
var _dent_timer := 0.0
var lights_on := false

func setup(p_sim: NTSim, p_id: int, p_key: String, player: bool, paint: Material = null) -> void:
	sim = p_sim
	car_id = p_id
	key = p_key
	is_player = player
	name = "Car_%d_%s" % [car_id, key]
	var spec := sim.get_car_spec(car_id)
	wheel_data = sim.get_wheel_data(car_id)
	visual = CarBuilder.build(key, spec, wheel_data, paint, player)
	add_child(visual)
	_wheels = visual.get_meta("wheels")
	_paint = visual.get_meta("paint")
	_brake_lights = visual.get_meta("brake_lights", []) if visual.has_meta("brake_lights") else []
	for m in _brake_lights:
		# Unique material per car so braking only lights this car.
		if m != null and m is MeshInstance3D and m.material_override != null:
			m.material_override = m.material_override.duplicate()
	if is_player:
		_make_headlights(spec)
		_make_taillights(spec)
	else:
		_make_rival_headlight(spec)
	audio = CarAudio.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(self)
	global_transform = sim.get_transform(car_id)
	reset_physics_interpolation()
	_redline = float(spec.get("redline_rpm", 7000.0))
	_setup_effects()

# ---- Brake glow and exhaust backfire ----------------------------------------------------------
var _redline := 7000.0
var _disc_mats: Array[StandardMaterial3D] = [] # front, rear
var _disc_heat := [0.0, 0.0]
var _flames: Array[MeshInstance3D] = []
var _flame_timer := 0.0
var _pops_left := 0
var _pop_gap := 0.0
var _prev_throttle := 0.0

func _setup_effects() -> void:
	# Per-car disc materials (the shared one would light every car's rotors at once).
	for axle in range(2):
		var m := (CarMaterials.shared("disc") as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.emission_enabled = true
		m.emission = Color.BLACK
		_disc_mats.append(m)
	for i in range(_wheels.size()):
		var disc := (_wheels[i] as Node).find_child("BrakeDisc", true, false) as MeshInstance3D
		if disc:
			disc.material_override = _disc_mats[0 if i < 2 else 1]
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_color = Color(1.0, 0.5, 0.15, 0.9)
	fm.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(0.28, 0.28)
	var tips: Array = visual.get_meta("exhausts_local", []) if visual.has_meta("exhausts_local") else []
	if tips.is_empty() and visual.has_meta("exhaust_local"):
		tips = [visual.get_meta("exhaust_local")]
	for p in tips:
		var f := MeshInstance3D.new()
		f.mesh = q
		f.material_override = fm
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.position = (p as Vector3) + Vector3(0, 0, 0.18) # just behind the tip (forward is -Z)
		f.visible = false
		visual.add_child(f)
		_flames.append(f)

func _update_effects(delta: float) -> void:
	var spd: float = float(telemetry.get("speed", 0.0))
	var brk: float = float(telemetry.get("brake", 0.0))
	# Rotors: braking energy ~ brake x speed heats them (a hard stop from 200 km/h reaches ~0.75);
	# they cool faster in the airflow at speed.
	var tau := 8.0 / (1.0 + spd / 30.0)
	for axle in range(2):
		var share := 1.3 if axle == 0 else 0.7
		_disc_heat[axle] = clampf(_disc_heat[axle] + brk * spd * 0.005 * share * delta, 0.0, 1.0) * exp(-delta / tau)
		if axle < _disc_mats.size():
			var t: float = _disc_heat[axle]
			var glow := smoothstep(0.35, 1.0, t)
			_disc_mats[axle].emission = Color(0.55, 0.06, 0.0).lerp(Color(1.0, 0.42, 0.08), glow) * glow
			_disc_mats[axle].emission_energy_multiplier = 3.0
	# Backfire: overrun pops after lifting off from high revs, and crackle on the limiter.
	if _flames.is_empty():
		return
	var thr: float = float(telemetry.get("throttle", 0.0))
	var rpm: float = float(telemetry.get("rpm", 0.0))
	if _prev_throttle > 0.6 and thr < 0.15 and rpm > _redline * 0.6:
		_pops_left = randi_range(2, 4)
		_pop_gap = randf_range(0.02, 0.08)
	_prev_throttle = thr
	if bool(telemetry.get("limiter", false)) and _pops_left == 0 and randf() < 0.25:
		_pops_left = 1
		_pop_gap = 0.0
	_flame_timer -= delta
	_pop_gap -= delta
	if _pops_left > 0 and _pop_gap <= 0.0:
		_pops_left -= 1
		_pop_gap = randf_range(0.07, 0.16)
		_flame_timer = randf_range(0.04, 0.09)
		for f in _flames:
			f.scale = Vector3.ONE * randf_range(0.6, 1.3)
	for f in _flames:
		f.visible = _flame_timer > 0.0

## Garage build: paint, finish and engine-swap audio from a Profile garage entry.
func setup_entry(p_sim: NTSim, p_id: int, entry: Dictionary, player: bool) -> void:
	var k: String = entry.get("key", CarData.DEFAULT_KEY)
	audio_key = UpgradeData.swap_donor_key(k, int(entry.get("upgrades", {}).get("swap", 0)))
	setup(p_sim, p_id, k, player, Profile.paint_for(entry))

func _make_headlights(spec: Dictionary) -> void:
	var he: Vector3 = spec.half_extents
	var anchors: Array = visual.get_meta("headlights_local", []) if visual and visual.has_meta("headlights_local") else []
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var pos: Vector3
		if anchors.size() > i:
			pos = anchors[i] + Vector3(0, 0, -0.15)
		else:
			pos = Vector3(side * he.x * 0.68, he.y * 0.28 + 0.12, -he.z - 0.15)
		var l := SpotLight3D.new()
		l.name = "HeadBeam_%d" % i
		l.light_color = Color(0.96, 0.98, 1.0)
		l.light_energy = 0.0
		l.spot_range = 80.0
		l.spot_angle = 32.0
		l.spot_attenuation = 1.0
		l.spot_angle_attenuation = 1.4
		l.shadow_enabled = false
		l.position = pos
		l.rotation = Vector3(deg_to_rad(-2.8), side * deg_to_rad(-1.8), 0)
		add_child(l)
		_headlights.append(l)

func _make_taillights(spec: Dictionary) -> void:
	var he: Vector3 = spec.half_extents
	var anchors: Array = visual.get_meta("taillights_local", []) if visual and visual.has_meta("taillights_local") else []
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var pos: Vector3
		if anchors.size() > i:
			pos = anchors[i] + Vector3(0, 0, 0.15)
		else:
			pos = Vector3(side * he.x * 0.65, he.y * 0.32 + 0.15, he.z + 0.15)
		var l := SpotLight3D.new()
		l.name = "TailBeam_%d" % i
		l.light_color = Color(1.0, 0.06, 0.03)
		l.light_energy = 0.0
		l.spot_range = 10.0
		l.spot_angle = 68.0
		l.spot_attenuation = 1.2
		l.spot_angle_attenuation = 1.2
		l.shadow_enabled = false
		l.position = pos
		l.rotation = Vector3(deg_to_rad(-12.0), PI + side * deg_to_rad(4.0), 0)
		add_child(l)
		_taillights.append(l)

func _make_rival_headlight(spec: Dictionary) -> void:
	var he: Vector3 = spec.half_extents
	var l := SpotLight3D.new()
	l.name = "RivalBeam"
	l.light_color = Color(0.95, 0.97, 1.0)
	l.light_energy = 0.0
	l.spot_range = 50.0
	l.spot_angle = 38.0
	l.spot_attenuation = 1.1
	l.shadow_enabled = false
	l.position = Vector3(0.0, he.y * 0.28 + 0.12, -he.z - 0.15)
	l.rotation = Vector3(deg_to_rad(-3.0), 0, 0)
	add_child(l)
	_headlights.append(l)

func set_lights(on: bool) -> void:
	lights_on = on
	var h_energy := 3.8 if on else 0.0
	for l in _headlights:
		l.light_energy = h_energy
	_update_taillights(false)

func _update_taillights(braking: bool) -> void:
	var target_e := 0.0
	if braking:
		target_e = 3.2
	elif lights_on:
		target_e = 0.55
	for l in _taillights:
		l.light_energy = target_e

var _chassis_roll := 0.0
var _chassis_pitch := 0.0
var _roll_velocity := 0.0
var _pitch_velocity := 0.0
var _prev_pos := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _have_prev := false
var _acc_smooth := Vector3.ZERO
var _body_heave := 0.0
var _heave_velocity := 0.0

func _physics_process(delta: float) -> void:
	if sim == null or car_id < 0:
		return
	global_transform = sim.get_transform(car_id)
	telemetry = sim.get_telemetry(car_id)
	wheel_data = sim.get_wheel_data(car_id)
	var stride := NTSim.WHEEL_STRIDE
	var wheel_y: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in range(4):
		var o := i * stride
		var w: Node3D = _wheels[i]
		var wy: float = wheel_data[o + 1]
		wheel_y[i] = wy
		w.position = Vector3(wheel_data[o], wy, wheel_data[o + 2])
		w.rotation.y = -wheel_data[o + 3]
		var spin: Node3D = w.get_child(0)
		spin.rotation.x = -wheel_data[o + 4]

	# ---- GT7/FH5-quality Dynamic Chassis Roll, Pitch, Heave & Squat ----
	if visual != null and _wheels.size() == 4:
		var track_w := absf(_wheels[0].position.x - _wheels[1].position.x)
		if track_w < 0.4: track_w = 1.45
		var wheelbase := absf(_wheels[0].position.z - _wheels[2].position.z)
		if wheelbase < 0.4: wheelbase = 2.4

		# ---- Suspension geometry roll & pitch from wheel heights ----
		var susp_roll := (wheel_y[0] + wheel_y[2] - wheel_y[1] - wheel_y[3]) * 0.5 / track_w
		var susp_pitch := (wheel_y[2] + wheel_y[3] - wheel_y[0] - wheel_y[1]) * 0.5 / wheelbase
		var susp_heave := (wheel_y[0] + wheel_y[1] + wheel_y[2] + wheel_y[3]) * 0.25

		# ---- Load transfer from the car's real acceleration (body frame, low-passed) ----
		# Measured from the simulated transform, so it covers braking, power, cornering, kerbs and
		# crashes alike (no input-driven dive/squat: those ignored grip and pitched the wrong way).
		var dt := maxf(delta, 1e-4)
		var pos := global_position
		var vel := (pos - _prev_pos) / dt if _have_prev else Vector3.ZERO
		var acc := (vel - _prev_vel) / dt if _have_prev else Vector3.ZERO
		_prev_pos = pos
		_prev_vel = vel
		_have_prev = true
		var local_acc := global_transform.basis.inverse() * acc
		var k := 1.0 - exp(-dt / 0.12)
		_acc_smooth = _acc_smooth.lerp(local_acc.limit_length(40.0), k)
		var lat_g := _acc_smooth.x / 9.81 # + towards the right
		var long_g := -_acc_smooth.z / 9.81 # + accelerating (forward is -Z)

		# ---- Heave: road surface following + bump absorption ----
		var target_heave := susp_heave * 0.012

		# ---- Combine physical suspension geometry with weight transfer ----
		# Right turn (lat_g > 0): the outside (left) dips = +roll about Z. Braking (long_g < 0):
		# the nose dips = -pitch about X; power squats the tail.
		var target_roll := clampf(susp_roll * 0.9 + clampf(lat_g * 0.02, -0.04, 0.04), -0.15, 0.15)
		var target_pitch := clampf(susp_pitch * 0.85 + clampf(long_g * 0.012, -0.03, 0.02), -0.10, 0.10)

		# ---- Body springs (~4 Hz roll/pitch, ~3 Hz heave), fixed 1/120 s substeps so a slow
		# frame can't make the explicit integration blow up ----
		var omega := 25.0
		var damping := 0.85
		var heave_omega := 18.0
		var steps := clampi(ceili(dt / (1.0 / 120.0)), 1, 12)
		var h := minf(dt, 0.1) / steps
		for _i in range(steps):
			_roll_velocity += (omega * omega * (target_roll - _chassis_roll) - 2.0 * damping * omega * _roll_velocity) * h
			_chassis_roll += _roll_velocity * h
			_pitch_velocity += (omega * omega * (target_pitch - _chassis_pitch) - 2.0 * damping * omega * _pitch_velocity) * h
			_chassis_pitch += _pitch_velocity * h
			_heave_velocity += (heave_omega * heave_omega * (target_heave - _body_heave) - 2.0 * 0.92 * heave_omega * _heave_velocity) * h
			_body_heave += _heave_velocity * h

		visual.rotation.z = _chassis_roll
		visual.rotation.x = _chassis_pitch
		visual.position.y = _body_heave

	var is_braking := float(telemetry.get("brake", 0.0)) > 0.05
	var is_reversing := int(telemetry.get("gear", 0)) < 0
	CarBuilder.set_light_state(visual, is_braking, lights_on, is_reversing)
	_update_effects(delta)
	_update_taillights(is_braking)
	_handle_events()
	_dent_timer -= delta
	if _dent_timer <= 0.0:
		_dent_timer = 0.25
		_update_dents()

var _recent_impacts: Array[float] = []

## Impulses since the last call (skill system uses them to break chains on crashes).
func pop_recent_impacts() -> Array[float]:
	var out := _recent_impacts
	_recent_impacts = []
	return out

func _handle_events() -> void:
	for e in sim.pop_events(car_id):
		var impulse: float = e.impulse
		if _recent_impacts.size() < 16:
			_recent_impacts.append(impulse)
		collided.emit(impulse, e.position, e.other)
		if is_player:
			Haptics.impact(clampf(impulse / 9000.0, 0.15, 1.0), int(clampf(impulse / 60.0, 40.0, 220.0)))

func _update_dents() -> void:
	if _paint == null:
		return
	var d := sim.get_dents(car_id)
	var arr := PackedVector4Array()
	arr.resize(8)
	for i in range(8):
		arr[i] = Vector4(d[i * 4], d[i * 4 + 1], d[i * 4 + 2], d[i * 4 + 3])
	_paint.set_shader_parameter("dents", arr)

func wheel_value(index: int, field: int) -> float:
	return wheel_data[index * NTSim.WHEEL_STRIDE + field]
