class_name ChaseCamera
extends Camera3D
## GT7/FH5-class driving camera: chase near/far (lagged, drift look-ahead, speed FOV),
## hood, bumper and cockpit. Follows chassis roll with subtle horizon tilt, uses exponential
## speed pull-back, variable drift-blend rate, and smooth wall collision avoidance.
## Right stick looks around, L3 looks back.

enum Mode { CHASE_NEAR, CHASE_FAR, HOOD, BUMPER, COCKPIT }

@export var target: CarView
var sim: NTSim
var mode := Mode.CHASE_NEAR
var _pos := Vector3.ZERO
var _look_dir := Vector3.FORWARD
var _yaw_offset := 0.0
var _pitch_offset := 0.0
var _shake := 0.0
var _shake_t := 0.0
var _initialized := false
var _fov := 70.0
var _roll_tilt := 0.0        # Horizon tilt following chassis roll
var _height_spring := 0.0    # Spring-damped height for smooth vertical tracking
var _height_vel := 0.0       # Height spring velocity
var _drift_blend := 0.0      # Smooth drift camera blend factor
var _impact_push := 0.0      # Post-collision push-out
var _brake_dive_cam := 0.0   # Camera dips slightly on hard braking

const MODES := {
	Mode.CHASE_NEAR: {"dist": 5.4, "height": 1.75, "look_h": 0.9, "fov": 68.0, "lag": 7.0},
	Mode.CHASE_FAR:  {"dist": 7.8, "height": 2.4,  "look_h": 1.0, "fov": 64.0, "lag": 6.0},
	Mode.HOOD: {"fov": 74.0},
	Mode.BUMPER: {"fov": 78.0},
	Mode.COCKPIT: {"fov": 72.0},
}

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.08
	far = 3500.0
	current = true

func cycle_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	_initialized = false

func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount * Settings.get_value("gameplay", "camera_shake", 1.0))
	# Collision pushes the camera out briefly (GT7 impact feel)
	_impact_push = maxf(_impact_push, amount * 0.6)

func snap() -> void:
	_initialized = false

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var xf: Transform3D = target.get_global_transform_interpolated()
	var vel := sim.get_velocity(target.car_id) if sim else Vector3.ZERO
	var speed := vel.length()
	var fwd := -xf.basis.z
	var up := Vector3.UP
	var t: Dictionary = target.telemetry if target else {}

	# Free look / look back.
	var look_in := Pad.look
	var target_yaw := -look_in.x * PI * 0.8
	var target_pitch := -look_in.y * 0.45
	if Pad.held("look_back"):
		target_yaw = PI
	_yaw_offset = lerp_angle(_yaw_offset, target_yaw, 1.0 - exp(-10.0 * delta))
	_pitch_offset = lerpf(_pitch_offset, target_pitch, 1.0 - exp(-10.0 * delta))

	var cfg: Dictionary = MODES[mode]
	var speed_kmh := speed * 3.6
	var boost: float = t.get("boost", 0.0)

	# ---- FOV: exponential speed curve + boost kick + braking compression ----
	var spd_frac := clampf(speed_kmh / 260.0, 0.0, 1.0)
	var fov_speed := spd_frac * spd_frac * 16.0  # Exponential for dramatic high-speed widening
	var brk_frac: float = float(t.get("brake", 0.0))
	var fov_brake := -brk_frac * clampf(speed_kmh / 120.0, 0.0, 1.0) * 3.0  # Slight narrow on braking
	var fov_target: float = cfg.fov + fov_speed + boost * 3.0 + fov_brake
	if Settings.get_value("gameplay", "reduced_motion", false):
		fov_target = cfg.fov + spd_frac * 6.0
	_fov = lerpf(_fov, fov_target, 1.0 - exp(-3.5 * delta))
	fov = _fov

	# ---- Collision impact push-out ----
	_impact_push = move_toward(_impact_push, 0.0, delta * 3.0)

	# ---- Camera brake dive ----
	var dive_target := brk_frac * clampf(speed_kmh / 80.0, 0.0, 1.0) * 0.15
	_brake_dive_cam = lerpf(_brake_dive_cam, dive_target, 1.0 - exp(-6.0 * delta))

	var spec_he := Vector3(0.9, 0.65, 2.2)
	if mode == Mode.CHASE_NEAR or mode == Mode.CHASE_FAR:
		# ---- Drift camera: variable blend rate (faster blend in, slower settle out) ----
		var flat_fwd := Vector3(fwd.x, 0, fwd.z).normalized()
		var flat_vel := Vector3(vel.x, 0, vel.z)
		var dir := flat_fwd
		var drift_angle := 0.0
		if flat_vel.length() > 3.0 and flat_vel.normalized().dot(flat_fwd) > -0.2:
			var vdir := flat_vel.normalized()
			drift_angle = flat_fwd.angle_to(vdir)
			# Variable blend: drift faster into the slide, settle out slower
			var target_drift := clampf(flat_vel.length() / 10.0, 0.0, 1.0) * 0.5
			var drift_rate := 8.0 if target_drift > _drift_blend else 3.5
			_drift_blend = lerpf(_drift_blend, target_drift, 1.0 - exp(-drift_rate * delta))
			dir = flat_fwd.slerp(vdir, _drift_blend).normalized()
		else:
			_drift_blend = lerpf(_drift_blend, 0.0, 1.0 - exp(-3.0 * delta))
		dir = dir.rotated(Vector3.UP, _yaw_offset)
		if not _initialized:
			_look_dir = dir
		# Adaptive lag: looser when drifting for dramatic effect
		var effective_lag: float = cfg.lag * lerpf(1.0, 0.7, clampf(drift_angle / 0.5, 0.0, 1.0))
		_look_dir = _look_dir.slerp(dir, 1.0 - exp(-effective_lag * delta)).normalized()

		# ---- Speed pull-back: exponential curve for dramatic high-speed extension ----
		var pull_back := clampf(speed_kmh / 200.0, 0.0, 1.0)
		pull_back = pull_back * pull_back * 1.6  # Exponential curve
		var dist: float = cfg.dist + pull_back + _impact_push * 1.5
		var height: float = cfg.height + _pitch_offset * 2.0 - _brake_dive_cam
		var pivot := xf.origin + up * float(cfg.look_h)
		var desired := pivot - _look_dir * dist + up * (height - float(cfg.look_h))

		# ---- Wall collision: soft spring pushback instead of hard snap ----
		if sim:
			var hit := sim.raycast(pivot, desired, 2)
			if not hit.is_empty():
				var safe_dist := maxf(1.4, float(hit.distance) - 0.4)
				desired = pivot + (desired - pivot).normalized() * safe_dist
			var gh := sim.ground_height(desired + Vector3(0, 2.5, 0), 8.0)
			if not is_nan(gh):
				desired.y = maxf(desired.y, gh + 0.6)
		if not _initialized:
			_pos = desired
			_height_spring = desired.y
			_initialized = true

		# ---- Separate horizontal and vertical tracking rates ----
		var k_h := 1.0 - exp(-20.0 * delta)   # Tighter horizontal follow
		var k_v := 1.0 - exp(-8.0 * delta)     # Softer vertical for smoother terrain following
		_pos.x = lerpf(_pos.x, desired.x, k_h)
		_pos.z = lerpf(_pos.z, desired.z, k_h)
		# Spring-damped vertical for buttery-smooth hill cresting
		var vy_err := desired.y - _height_spring
		var vy_accel := 120.0 * vy_err - 16.0 * _height_vel
		_height_vel += vy_accel * delta
		_height_spring += _height_vel * delta
		_pos.y = _height_spring

		global_position = _pos
		look_at(pivot + _look_dir * 4.5, up)

		# ---- Horizon roll tilt: subtly follow chassis roll (GT7 immersion) ----
		var chassis_roll: float = target._chassis_roll if target else 0.0
		var target_tilt := chassis_roll * 0.35  # 35% of chassis roll for subtle tilt
		_roll_tilt = lerpf(_roll_tilt, target_tilt, 1.0 - exp(-6.0 * delta))
		rotate_object_local(Vector3.FORWARD, _roll_tilt)
	else:
		var local: Vector3
		match mode:
			Mode.HOOD:
				local = Vector3(0, 0.62, -0.6)
			Mode.BUMPER:
				local = Vector3(0, 0.1, -spec_he.z - 0.05)
			_:
				local = Vector3(-0.35, 0.52, 0.15)
		global_transform = xf * Transform3D(Basis.from_euler(Vector3(_pitch_offset * 0.5, _yaw_offset, 0)), local)
		_initialized = true

	# ---- Shake: collisions + speed buzz + rough surface micro-vibration ----
	_shake = move_toward(_shake, 0.0, delta * 2.5)
	_shake_t += delta
	var shake_setting: float = Settings.get_value("gameplay", "camera_shake", 1.0)
	# Multi-frequency buzz for richer feel (GT7-style)
	var buzz_base := clampf((speed_kmh - 120.0) / 180.0, 0.0, 1.0) * 0.003 * shake_setting
	var buzz_high := clampf((speed_kmh - 200.0) / 100.0, 0.0, 1.0) * 0.002 * shake_setting
	var s: float = _shake * 0.09 + buzz_base + buzz_high
	if s > 0.0001:
		h_offset = sin(_shake_t * 37.0) * s + sin(_shake_t * 61.0) * buzz_high * 0.5
		v_offset = cos(_shake_t * 43.0) * s + cos(_shake_t * 53.0) * buzz_high * 0.4
	else:
		h_offset = 0.0
		v_offset = 0.0
