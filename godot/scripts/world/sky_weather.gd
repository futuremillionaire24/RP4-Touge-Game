class_name SkyWeather
extends Node3D
## Time of day + weather + season. Drives the sun/moon, sky, fog, exposure, the nt_* shader
## globals (night, wetness, rain, snow, season, wind) and the sim's wetness/temperature.

signal weather_changed(state: String)

enum W { CLEAR, OVERCAST, DRIZZLE, RAIN, STORM, CLEARING, FOG }
const W_NAMES := ["Clear", "Overcast", "Drizzle", "Rain", "Storm", "Clearing", "Fog"]

@export var day_length_minutes := 24.0
var time_of_day := 20.5 # hours, 0..24
var time_scale := 1.0 # 0 = frozen
var season := 0.0 # 0 spring, 1 summer, 2 autumn, 3 winter
var weather := W.CLEAR
var weather_lock := false
var wetness := 0.0
var rain := 0.0
var cloud := 0.0
var fog_amount := 0.0
var snow_cover := 0.0

var env_rig: EnvironmentRig
var sim: NTSim
var camera: Camera3D
var night := 0.0

var _target_rain := 0.0
var _target_cloud := 0.0
var _target_fog := 0.0
var _weather_timer := 240.0
var _lightning_timer := 8.0
var _flash := 0.0
var _rain_fx: GPUParticles3D
var _rng := RandomNumberGenerator.new()

func setup(p_env: EnvironmentRig, p_sim: NTSim, p_camera: Camera3D) -> void:
	env_rig = p_env
	sim = p_sim
	camera = p_camera
	_rng.randomize()
	_make_rain()

func set_weather(w: int, instant := false) -> void:
	weather = w
	match w:
		W.CLEAR: _target_rain = 0.0; _target_cloud = 0.1; _target_fog = 0.0
		W.OVERCAST: _target_rain = 0.0; _target_cloud = 0.75; _target_fog = 0.15
		W.DRIZZLE: _target_rain = 0.3; _target_cloud = 0.8; _target_fog = 0.25
		W.RAIN: _target_rain = 0.7; _target_cloud = 0.9; _target_fog = 0.3
		W.STORM: _target_rain = 1.0; _target_cloud = 1.0; _target_fog = 0.4
		W.CLEARING: _target_rain = 0.0; _target_cloud = 0.4; _target_fog = 0.1
		W.FOG: _target_rain = 0.0; _target_cloud = 0.6; _target_fog = 1.0
	if instant:
		rain = _target_rain
		cloud = _target_cloud
		fog_amount = _target_fog
		wetness = clampf(rain * 1.1, 0.0, 1.0)
	weather_changed.emit(W_NAMES[w])

func _next_weather() -> int:
	# Markov-ish transitions that feel like Japanese weather fronts.
	match weather:
		W.CLEAR: return [W.CLEAR, W.OVERCAST, W.FOG][_rng.randi_range(0, 2) if _rng.randf() < 0.5 else 0]
		W.OVERCAST: return [W.DRIZZLE, W.CLEARING, W.RAIN][_rng.randi_range(0, 2)]
		W.DRIZZLE: return [W.RAIN, W.CLEARING][_rng.randi_range(0, 1)]
		W.RAIN: return [W.STORM, W.DRIZZLE, W.CLEARING][_rng.randi_range(0, 2)]
		W.STORM: return W.RAIN
		W.CLEARING: return W.CLEAR
		W.FOG: return W.CLEARING
	return W.CLEAR

func _make_rain() -> void:
	_rain_fx = GPUParticles3D.new()
	_rain_fx.amount = 9000
	_rain_fx.lifetime = 1.1
	_rain_fx.local_coords = false
	_rain_fx.visibility_aabb = AABB(Vector3(-40, -25, -40), Vector3(80, 50, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 1, 28)
	pm.direction = Vector3(0.1, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 28.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain_fx.process_material = pm
	var streak := QuadMesh.new()
	streak.size = Vector2(0.015, 0.55)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	sm.billboard_keep_scale = true
	streak.material = sm
	_rain_fx.draw_pass_1 = streak
	_rain_fx.emitting = false
	add_child(_rain_fx)

const SKY_DIR := "res://assets/env/sky/"
var _sky_keys: Array = [] # day-cycle keyframes from sky.json, sorted by hour
var _sky_weather := {} # weather id -> keyframe
var _sky_tex := {} # id -> Texture2D (only the ones in use stay referenced)

func _sky_meta() -> void:
	if not _sky_keys.is_empty():
		return
	var f := FileAccess.open(SKY_DIR + "sky.json", FileAccess.READ)
	if f == null:
		return
	for s in JSON.parse_string(f.get_as_text()).skies:
		if float(s.hour) < 0.0:
			_sky_weather[s.weather] = s
		else:
			_sky_keys.append(s)
	_sky_keys.sort_custom(func(a, b): return a.hour < b.hour)

## The two day-cycle keyframes around `h` and the blend between them (wraps over midnight).
func _sky_pair(h: float) -> Array:
	var n := _sky_keys.size()
	for i in range(n):
		var a: Dictionary = _sky_keys[i]
		var b: Dictionary = _sky_keys[(i + 1) % n]
		var ha := float(a.hour)
		var hb := float(b.hour) + (24.0 if i == n - 1 else 0.0)
		var hh := h + (24.0 if i == n - 1 and h < ha else 0.0)
		if hh >= ha and hh < hb:
			return [a, b, smoothstep(0.0, 1.0, (hh - ha) / (hb - ha))]
	return [_sky_keys[0], _sky_keys[0], 0.0]

func _sky_texture(id: String) -> Texture2D:
	if not _sky_tex.has(id):
		_sky_tex[id] = load(SKY_DIR + id + ".jpg")
	return _sky_tex[id]

## Sun azimuth (radians from north, clockwise): east at 6:00, south at noon, west at 18:00.
func sun_azimuth() -> float:
	return deg_to_rad(90.0 + (time_of_day - 6.0) / 12.0 * 180.0)

func sun_direction() -> Vector3:
	# Elevation follows the photographed sky keyframes, so the sky's sun glow, the disc and the
	# shadows always agree.
	_sky_meta()
	var el := 0.0
	if _sky_keys.is_empty():
		el = asin(clampf(sin((time_of_day - 6.0) / 12.0 * PI), -1.0, 1.0)) * 0.8
	else:
		var p := _sky_pair(time_of_day)
		el = deg_to_rad(lerpf(float(p[0].sun_el), float(p[1].sun_el), p[2]))
	var az := sun_azimuth()
	# +X east, +Z south, -Z north.
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()

func _process(delta: float) -> void:
	var real_minutes_per_hour := day_length_minutes / 24.0
	time_of_day = fmod(time_of_day + delta * time_scale / (real_minutes_per_hour * 60.0), 24.0)
	if not weather_lock:
		_weather_timer -= delta
		if _weather_timer <= 0.0:
			_weather_timer = _rng.randf_range(180.0, 420.0)
			set_weather(_next_weather())
	# Blend weather quantities.
	rain = move_toward(rain, _target_rain, delta * 0.02)
	cloud = move_toward(cloud, _target_cloud, delta * 0.015)
	fog_amount = move_toward(fog_amount, _target_fog, delta * 0.01)
	var cold := season > 2.6
	if rain > 0.02:
		wetness = minf(1.0, wetness + delta * rain * 0.025)
	else:
		wetness = maxf(0.0, wetness - delta * (0.004 + 0.006 * (1.0 - cloud)))
	if cold and rain > 0.1:
		snow_cover = minf(1.0, snow_cover + delta * rain * 0.01)
	elif not cold:
		snow_cover = maxf(0.0, snow_cover - delta * 0.02)

	_update_lighting(delta)
	var snowing := cold and rain > 0.05
	RenderingServer.global_shader_parameter_set("nt_night", night)
	RenderingServer.global_shader_parameter_set("nt_wetness", 0.0 if snowing else wetness)
	RenderingServer.global_shader_parameter_set("nt_rain", 0.0 if snowing else rain)
	RenderingServer.global_shader_parameter_set("nt_snow", snow_cover)
	RenderingServer.global_shader_parameter_set("nt_season", season)
	RenderingServer.global_shader_parameter_set("nt_wind", Vector3(0.6, 0, 0.3) * (1.0 + rain * 2.0))
	if sim:
		sim.wetness = wetness
		sim.ambient_temp = lerpf(22.0, 2.0, clampf(season - 2.0, 0.0, 1.0)) - night * 4.0
	if camera and _rain_fx:
		_rain_fx.global_position = camera.global_position + Vector3(0, 14, 0) + camera.global_basis.z * -8.0
		_rain_fx.emitting = rain > 0.05
		_rain_fx.amount_ratio = clampf(rain, 0.05, 1.0)
		var sm: StandardMaterial3D = (_rain_fx.draw_pass_1 as QuadMesh).material
		sm.albedo_color = Color(0.95, 0.97, 1.0, 0.8) if snowing else Color(0.75, 0.8, 0.9, 0.35)

func _update_lighting(delta: float) -> void:
	if env_rig == null:
		return
	var sd := sun_direction()
	var elev := sd.y
	night = 1.0 - smoothstep(-0.12, 0.12, elev)
	var sun := env_rig.sun
	var env := env_rig.env
	var sky := env_rig.sky_mat

	# ---- Sun or moon direction with slight night-time movement ----
	var light_dir := sd if elev > -0.05 else Vector3(-sd.x, -sd.y, sd.z).normalized()
	sun.look_at_from_position(Vector3.ZERO, -light_dir, Vector3.UP)

	# ---- Golden hour: rich warm palette (GT7-style dramatic sunset/sunrise) ----
	var golden := smoothstep(0.4, 0.0, absf(elev)) * (1.0 - night)
	var golden_deep := smoothstep(0.18, 0.0, absf(elev)) * (1.0 - night)  # Extra warmth near horizon
	var day_col := Color(1.0, 0.96, 0.90).lerp(Color(1.0, 0.58, 0.28), golden)
	day_col = day_col.lerp(Color(1.0, 0.42, 0.18), golden_deep * 0.4)  # Deep amber at horizon
	var moon_col := Color(0.50, 0.58, 0.82)
	sun.light_color = day_col.lerp(moon_col, night)
	var overcast := cloud
	sun.light_energy = lerpf(lerpf(1.35, 0.28, overcast), 0.065, night)
	sun.shadow_opacity = lerpf(1.0, 0.3, overcast)

	# ---- Photographic sky: day-cycle keyframes + weather cloud layers ----
	var horizon := Color(0.7, 0.76, 0.84)
	_sky_meta()
	if not _sky_keys.is_empty():
		var p := _sky_pair(time_of_day)
		var a: Dictionary = p[0]
		var b: Dictionary = p[1]
		var t: float = p[2]
		# Rotate each panorama so its sun glow sits at the game sun's azimuth.
		var az_u := sun_azimuth() / TAU
		var rot := Vector4(float(a.sun_u) - 0.5 - az_u, float(b.sun_u) - 0.5 - az_u, 0.0, 0.0)
		sky.set_shader_parameter("sky_a", _sky_texture(a.id))
		sky.set_shader_parameter("sky_b", _sky_texture(b.id))
		sky.set_shader_parameter("blend", t)
		sky.set_shader_parameter("energy", Vector2(float(a.energy), float(b.energy)))
		var partly := smoothstep(0.05, 0.4, cloud) * (1.0 - smoothstep(0.7, 0.95, cloud) * 0.5)
		var over := smoothstep(0.45, 0.85, cloud)
		if _sky_weather.has("cloudy"):
			var w: Dictionary = _sky_weather.cloudy
			sky.set_shader_parameter("sky_p", _sky_texture(w.id))
			rot.z = float(w.sun_u) - 0.5 - az_u
		if _sky_weather.has("overcast"):
			var w: Dictionary = _sky_weather.overcast
			sky.set_shader_parameter("sky_o", _sky_texture(w.id))
			rot.w = float(w.sun_u) - 0.5 - az_u
		sky.set_shader_parameter("rot", rot)
		sky.set_shader_parameter("weather", Vector2(partly, over))
		var ha: Array = a.horizon
		var hb: Array = b.horizon
		var e := lerpf(float(a.energy), float(b.energy), t)
		horizon = Color(lerpf(ha[0], hb[0], t), lerpf(ha[1], hb[1], t), lerpf(ha[2], hb[2], t)) * e
		var grey := Color(0.5, 0.52, 0.55) * e
		horizon = horizon.lerp(grey, over * 0.7)
		# Drop texture references that are no longer shown (VRAM on the handheld).
		for id in _sky_tex.keys():
			if id != a.id and id != b.id and not _sky_weather.values().any(func(s): return s.id == id):
				_sky_tex.erase(id)

	# ---- Ambient & exposure ----
	env.ambient_light_energy = lerpf(lerpf(1.0, 1.1, overcast), 0.4, night)
	env.ambient_light_color = horizon.lightened(0.1)
	env.tonemap_exposure = lerpf(1.0, 1.25, night)

	# ---- Glow: clean bloom on light emitters without blowing out car panels ----
	env.glow_intensity = lerpf(0.35, 0.55, night)
	env.glow_hdr_threshold = lerpf(1.2, 1.05, night)
	env.glow_bloom = lerpf(0.02, 0.04, night)

	# ---- Fog: atmospheric depth with weather ----
	env.fog_density = lerpf(0.0004, 0.007, fog_amount) + rain * 0.0015 + night * 0.0002
	env.fog_light_color = horizon.lerp(Color(0.52, 0.55, 0.60), overcast * 0.5)

	# ---- Lightning in storms: double-flash pattern (GT7-style) ----
	if weather == W.STORM:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_timer = _rng.randf_range(4.0, 14.0)
			_flash = 1.0
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.5)
		# Double-flash: first burst + secondary pulse
		var flash_intensity := _flash * (1.0 + 0.3 * sin(_flash * 12.0))
		env.ambient_light_energy += flash_intensity * 5.0
		sky.set_shader_parameter("flash", flash_intensity)
	else:
		sky.set_shader_parameter("flash", 0.0)

