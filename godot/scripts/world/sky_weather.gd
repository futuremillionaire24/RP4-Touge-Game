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

func sun_direction() -> Vector3:
	# Sun rises in the east (+X) at 6:00, sets in the west at 18:00; tilted south.
	var t := (time_of_day - 6.0) / 12.0 * PI
	return Vector3(cos(t), sin(t), 0.35).normalized()

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

	# ---- Sky palette: GT7-grade day → golden hour → night ----
	var top_day := Color(0.20, 0.40, 0.74)
	var hor_day := Color(0.70, 0.78, 0.88)
	# Golden hour: peach horizon, warm indigo top
	var top_golden := Color(0.38, 0.24, 0.48)
	var hor_golden := Color(1.0, 0.50, 0.28)
	# Night: deep purple-black sky with subtle Japanese city glow on horizon
	var top_n := Color(0.010, 0.008, 0.035)
	var hor_n := Color(0.09, 0.05, 0.16)  # Purple-pink city glow

	var top := top_day.lerp(top_golden, golden * 0.7).lerp(top_n, night)
	var hor := hor_day.lerp(hor_golden, golden).lerp(hor_n, night)

	# Overcast greys
	var grey := Color(0.42, 0.44, 0.48).lerp(Color(0.04, 0.04, 0.06), night)
	sky.sky_top_color = top.lerp(grey, overcast * 0.85)
	sky.sky_horizon_color = hor.lerp(grey.lightened(0.08), overcast * 0.8)
	sky.ground_horizon_color = sky.sky_horizon_color.darkened(0.22)
	sky.sun_angle_max = lerpf(28.0, 12.0, night)  # Tighter moon disc at night
	sky.sun_curve = lerpf(0.08, 0.15, night)

	# ---- Ambient & exposure: richer night presence ----
	env.ambient_light_energy = lerpf(lerpf(0.60, 0.65, overcast), 0.32, night)
	env.ambient_light_color = sky.sky_horizon_color.lightened(0.2)
	env.tonemap_exposure = lerpf(0.95, 1.5, night)

	# ---- Glow: dramatic at night for neon signs and headlights ----
	env.glow_intensity = lerpf(0.42, 1.25, night)
	env.glow_hdr_threshold = lerpf(1.3, 0.75, night)
	env.glow_bloom = lerpf(0.025, 0.06, night)

	# ---- Fog: atmospheric depth with weather ----
	env.fog_density = lerpf(0.0004, 0.007, fog_amount) + rain * 0.0015 + night * 0.0002
	env.fog_light_color = sky.sky_horizon_color.lerp(Color(0.52, 0.55, 0.60), overcast * 0.5)

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
		sky.sky_top_color = sky.sky_top_color.lerp(Color(0.85, 0.88, 1.0), flash_intensity * 0.85)

