class_name SkillSystem
extends Node
## Forza-style skill chains. Skills add points to the running chain and raise the multiplier;
## the chain banks after 4 s without a new skill, or is lost on a hard crash.
## Banked chains pay XP and credits through Profile.

signal skill(name: String, points: int)
signal chain_banked(points: int)
signal chain_lost(points: int)

const COMBO_TIME := 4.0
const MAX_MULT := 10

var sim: NTSim
var car: CarView
var enabled := true
var chain_points := 0.0
var multiplier := 1
var combo_timer := 0.0
var recent: Array = [] # [{"name", "points", "t"}]
var drift_points := 0.0 # running points of the current drift (for the ticker)
var in_drift := false
var _drift_skill_steps := 0
var _speed_timer := 0.0
var _air := 0.0
var _draft_timer := 0.0
var _burnout := 0.0
var _yaw_accum := 0.0
var _last_yaw := 0.0
var total_banked := 0

func _physics_process(delta: float) -> void:
	if not enabled or sim == null or car == null or car.telemetry.is_empty():
		return
	var t := car.telemetry
	var speed_kmh: float = absf(float(t.speed_kmh))
	# ---- Drift ----
	var angle := rad_to_deg(absf(float(t.drift_angle)))
	if angle > 12.0 and speed_kmh > 30.0 and float(t.airborne) < 0.2:
		in_drift = true
		var p := (angle - 10.0) * speed_kmh * delta * 0.08
		drift_points += p
		chain_points += p
		combo_timer = COMBO_TIME
		# Every 1500 drift points counts as another skill for the multiplier.
		var steps := int(drift_points / 1500.0)
		if steps > _drift_skill_steps:
			_drift_skill_steps = steps
			_bump("Drift", 0)
	elif in_drift:
		in_drift = false
		if drift_points > 200.0:
			_announce("Drift  %d" % int(drift_points), int(drift_points))
		drift_points = 0.0
		_drift_skill_steps = 0
	# ---- Near misses (from the native traffic system) ----
	for nm in sim.pop_near_misses():
		var pts := int(250.0 + (1.6 - float(nm.clearance)) * 300.0 + float(nm.rel_speed) * 6.0)
		_bump("Near Miss", pts)
	# ---- Speed ----
	if speed_kmh > 200.0:
		_speed_timer += delta
		if _speed_timer > 2.0:
			_speed_timer = 0.0
			_bump("Speed", 300 + int((speed_kmh - 200.0) * 4.0))
	else:
		_speed_timer = 0.0
	# ---- Air ----
	var airborne: float = t.airborne
	if airborne > 0.0:
		_air = maxf(_air, airborne)
	elif _air > 0.45:
		_bump("Air", int(_air * 900.0))
		_air = 0.0
	else:
		_air = 0.0
	# ---- Drafting ----
	if float(t.slipstream) > 0.3 and speed_kmh > 80.0:
		_draft_timer += delta
		if _draft_timer > 1.5:
			_draft_timer = 0.0
			_bump("Drafting", 200)
	# ---- Burnout: full throttle, barely moving, rear wheels spinning ----
	var spin := car.wheel_value(2, 8)
	if float(t.throttle) > 0.8 and speed_kmh < 25.0 and spin > 0.6:
		_burnout += delta
		if _burnout > 1.5:
			_burnout = 0.0
			_bump("Burnout", 250)
	else:
		_burnout = 0.0
	# ---- 180 / 360 spins ----
	var yaw := car.global_rotation.y
	var dy := wrapf(yaw - _last_yaw, -PI, PI)
	_last_yaw = yaw
	if speed_kmh > 15.0 and absf(dy) > 0.001:
		_yaw_accum += dy
	else:
		_yaw_accum = move_toward(_yaw_accum, 0.0, delta * 2.0)
	if absf(_yaw_accum) > TAU * 0.95:
		_yaw_accum = 0.0
		_bump("360", 1000)
	# ---- Crash breaks the chain ----
	for e in car.pop_recent_impacts():
		if float(e) > 9000.0 and chain_points > 0.0:
			chain_lost.emit(int(chain_points))
			_reset_chain()
			return
	# ---- Combo timer ----
	if chain_points > 0.0 and not in_drift:
		combo_timer -= delta
		if combo_timer <= 0.0:
			_bank()

func _bump(name: String, points: int) -> void:
	multiplier = mini(multiplier + 1, MAX_MULT)
	chain_points += points
	combo_timer = COMBO_TIME
	_announce(name, points)

func _announce(name: String, points: int) -> void:
	recent.push_front({"name": name, "points": points, "t": 3.0})
	if recent.size() > 4:
		recent.pop_back()
	skill.emit(name, points)

func _bank() -> void:
	var total := int(chain_points * multiplier)
	if total > 0:
		total_banked += total
		chain_banked.emit(total)
		Profile.add_xp(total / 20)
		Profile.add_credits(total / 10)
		Profile.data.stats.drift_score = maxi(int(Profile.data.stats.drift_score), total)
	_reset_chain()

func _reset_chain() -> void:
	chain_points = 0.0
	multiplier = 1
	combo_timer = 0.0
	drift_points = 0.0
	in_drift = false

func _process(delta: float) -> void:
	for r in recent:
		r.t -= delta
	recent = recent.filter(func(r): return r.t > 0.0)
