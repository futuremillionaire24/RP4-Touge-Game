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
var _prev_speed := 0.0
var _prev_lat_vel := 0.0
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

		var thr: float = float(telemetry.get("throttle", 0.0))
		var brk: float = float(telemetry.get("brake", 0.0))
		var spd: float = float(telemetry.get("speed", 0.0))
		var str_in: float = float(telemetry.get("steer", 0.0))
		var lat_vel: float = float(telemetry.get("lateral_vel", 0.0))

		# ---- Longitudinal deceleration G-force for progressive dive/squat ----
		var decel_g := clampf((_prev_speed - spd) / maxf(delta, 0.001) / 9.81, -3.0, 3.0)
		_prev_speed = spd

		# Progressive dive: threshold braking produces dramatic nose dive (GT7 style)
		var dive_curve := brk * brk * 0.08  # Squared for progressive feel
		var decel_dive := clampf(decel_g * 0.025, 0.0, 0.06)
		# Acceleration squat: power-on rear squat
		var squat := thr * clampf(spd / 12.0, 0.0, 1.0) * 0.04
		var pitch_weight := dive_curve + decel_dive - squat

		# ---- Real suspension & lateral load roll (Forza 4 sim-driven) ----
		# Remove fake steer-driven roll; let body attitude come directly from physical wheel travel
		var lat_g := clampf((_prev_lat_vel - lat_vel) / maxf(delta, 0.001) / 9.81, -2.5, 2.5)
		_prev_lat_vel = lat_vel
		var g_roll := clampf(-lat_g * 0.035, -0.06, 0.06)

		# ---- Heave: road surface following + bump absorption ----
		var target_heave := susp_heave * 0.012

		# ---- Combine physical suspension geometry with weight transfer ----
		var target_roll := clampf(susp_roll * 0.9 + g_roll, -0.15, 0.15)
		var target_pitch := clampf(susp_pitch * 0.85 + pitch_weight * 0.4, -0.10, 0.10)

		# ---- Critically damped spring interpolation (natural frequency ~4 Hz) ----
		var omega := 25.0  # Natural angular frequency
		var damping := 0.85  # Slightly underdamped for subtle overshoot
		var dt := delta

		# Roll spring
		var roll_err := target_roll - _chassis_roll
		var roll_accel := omega * omega * roll_err - 2.0 * damping * omega * _roll_velocity
		_roll_velocity += roll_accel * dt
		_chassis_roll += _roll_velocity * dt

		# Pitch spring
		var pitch_err := target_pitch - _chassis_pitch
		var pitch_accel := omega * omega * pitch_err - 2.0 * damping * omega * _pitch_velocity
		_pitch_velocity += pitch_accel * dt
		_chassis_pitch += _pitch_velocity * dt

		# Heave spring (softer, ~3 Hz)
		var heave_omega := 18.0
		var heave_err := target_heave - _body_heave
		var heave_accel := heave_omega * heave_omega * heave_err - 2.0 * 0.92 * heave_omega * _heave_velocity
		_heave_velocity += heave_accel * dt
		_body_heave += _heave_velocity * dt

		visual.rotation.z = _chassis_roll
		visual.rotation.x = _chassis_pitch
		visual.position.y = _body_heave

	var is_braking := float(telemetry.get("brake", 0.0)) > 0.05
	var is_reversing := int(telemetry.get("gear", 0)) < 0
	CarBuilder.set_light_state(visual, is_braking, lights_on, is_reversing)
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
