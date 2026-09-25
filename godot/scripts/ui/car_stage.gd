class_name CarStage
extends Node3D
## Festival car stage behind the menus: an open-air plaza on the Riviera at golden hour (the
## photographic day-cycle sky with scattered cloud, low sun, real stone paving that fades into the
## horizon haze), the selected car settled on its real suspension by a private NTSim, and an orbit
## camera (auto-rotate, right stick to look around). Car swaps are debounced so fast list scrolling
## doesn't rebuild meshes every frame.

const FLOOR_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2DArray ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_normal : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 uv = vec3(wpos.xz / 2.0, 5.0); // rectangular stone paving
	vec4 a = texture(ground_albedo, uv);
	vec4 n = texture(ground_normal, uv);
	float r = length(wpos.xz);
	// Freshly washed plaza: slightly darker and glossier around the car.
	float wet = smoothstep(9.0, 3.0, r) * 0.5;
	ALBEDO = a.rgb * mix(0.95, 0.7, wet);
	ROUGHNESS = mix(n.b, 0.25, wet);
	SPECULAR = 0.5;
	AO = n.a;
	vec3 N = normalize(vec3((n.r * 2.0 - 1.0) * 0.8, 1.0, -(n.g * 2.0 - 1.0) * 0.8));
	NORMAL = normalize((VIEW_MATRIX * vec4(N, 0.0)).xyz);
}
"""
const STAGE_SKY := "qwantani_late_afternoon_puresky"
const STAGE_CLOUDS := "kloofendal_48d_partly_cloudy_puresky"
const SUN_AZIMUTH := 2.4 # radians from north: the sun low over the car's left shoulder

var camera: Camera3D
var yaw := PI + 0.7 # front three-quarter (cars face -Z)
var pitch := 0.16
var distance := 6.4
var auto_rotate := true
var frame_offset := 1.3 # camera h_offset: pushes the car right of the menu column
var view: CarView
var sim: NTSim
var _pending := {}
var _pending_timer := -1.0
var _shown_sig := ""
var _idle := 0.0
var _env: Environment

func _ready() -> void:
	_build_studio()
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.current = true
	add_child(camera)
	_update_camera(0.0)

func _build_studio() -> void:
	# Keyframe data (sun position in the panorama, horizon colour) from the sky bake.
	var meta := {}
	var f := FileAccess.open("res://assets/env/sky/sky.json", FileAccess.READ)
	if f:
		for s in JSON.parse_string(f.get_as_text()).skies:
			meta[s.id] = s
	var key_sky: Dictionary = meta.get(STAGE_SKY, {"sun_u": 0.6, "sun_el": 19.0, "energy": 0.95, "horizon": [0.8, 0.75, 0.7]})
	var clouds: Dictionary = meta.get(STAGE_CLOUDS, {"sun_u": 0.6})
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky_hdri.gdshader")
	var tex: Texture2D = load("res://assets/env/sky/%s.jpg" % STAGE_SKY) if ResourceLoader.exists("res://assets/env/sky/%s.jpg" % STAGE_SKY) else null
	sky_mat.set_shader_parameter("sky_a", tex)
	sky_mat.set_shader_parameter("sky_b", tex)
	sky_mat.set_shader_parameter("energy", Vector2(1.0, 1.0))
	var az_u := SUN_AZIMUTH / TAU
	var rot := Vector4(float(key_sky.sun_u) - 0.5 - az_u, float(key_sky.sun_u) - 0.5 - az_u, float(clouds.sun_u) - 0.5 - az_u, 0.0)
	if ResourceLoader.exists("res://assets/env/sky/%s.jpg" % STAGE_CLOUDS):
		sky_mat.set_shader_parameter("sky_p", load("res://assets/env/sky/%s.jpg" % STAGE_CLOUDS))
		sky_mat.set_shader_parameter("weather", Vector2(0.5, 0.0))
	sky_mat.set_shader_parameter("rot", rot)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 7.5
	_env.glow_enabled = true
	_env.glow_intensity = 0.3
	_env.glow_hdr_threshold = 1.2
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.06
	# Haze: the plaza edge dissolves into the horizon colour of the panorama.
	var h: Array = key_sky.horizon
	_env.fog_enabled = true
	_env.fog_light_color = Color(h[0], h[1], h[2])
	_env.fog_density = 0.012
	_env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	# Low golden-hour sun where the panorama's sun is, with soft contact shadows.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var el := deg_to_rad(float(key_sky.sun_el))
	var dir := Vector3(sin(SUN_AZIMUTH) * cos(el), sin(el), -cos(SUN_AZIMUTH) * cos(el))
	sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP)
	sun.light_color = Color(1.0, 0.86, 0.68)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 20.0
	sun.shadow_blur = 1.5
	add_child(sun)
	# Cool sky fill from the opposite side keeps the shadowed flank readable.
	var fill := DirectionalLight3D.new()
	fill.look_at_from_position(Vector3.ZERO, Vector3(dir.x, -0.6, dir.z), Vector3.UP)
	fill.light_color = Color(0.75, 0.84, 1.0)
	fill.light_energy = 0.25
	add_child(fill)

	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	floor_mi.mesh = pm
	var sh := Shader.new()
	sh.code = FLOOR_SHADER
	var fm := ShaderMaterial.new()
	fm.shader = sh
	for u in ["ground_albedo", "ground_normal"]:
		var p := "res://assets/env/%s.webp" % u
		if ResourceLoader.exists(p):
			fm.set_shader_parameter(u, load(p))
	floor_mi.material_override = fm
	add_child(floor_mi)

## Show a garage entry (paint, finish, upgrades affect ride height via the sim).
func show_entry(entry: Dictionary, immediate := false) -> void:
	_queue({"entry": entry.duplicate(true)}, immediate)

## Show a stock car (dealer, starter choice).
func show_key(key: String, immediate := false) -> void:
	_queue({"entry": {"key": key, "upgrades": {}, "tune": {}}}, immediate)

func clear() -> void:
	_pending = {}
	_pending_timer = -1.0
	_shown_sig = ""
	_free_car()

func _queue(req: Dictionary, immediate: bool) -> void:
	_pending = req
	_pending_timer = 0.0 if immediate else 0.12

func _process(delta: float) -> void:
	if _pending_timer >= 0.0:
		_pending_timer -= delta
		if _pending_timer < 0.0:
			_build(_pending.entry)
	var look: Vector2 = Pad.look
	if look.length() > 0.15:
		yaw -= look.x * delta * 2.2
		pitch = clampf(pitch + look.y * delta * 1.2, 0.02, 0.6)
		_idle = 0.0
	else:
		_idle += delta
	if auto_rotate and _idle > 2.0 and not bool(Settings.get_value("gameplay", "reduced_motion", false)):
		yaw += delta * 0.18
	_update_camera(delta)

func _update_camera(_delta: float) -> void:
	if camera == null:
		return
	var target := Vector3(0, 0.55, 0)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.position = target + off
	camera.look_at(target, Vector3.UP)
	camera.h_offset = -frame_offset

func _free_car() -> void:
	if view:
		view.queue_free()
		view = null
	if sim:
		sim.queue_free()
		sim = null

func _build(entry: Dictionary) -> void:
	var sig := JSON.stringify(entry)
	if sig == _shown_sig:
		return
	_shown_sig = sig
	_free_car()
	sim = NTSim.new()
	sim.running = false
	add_child(sim)
	var g := 30.0
	sim.set_collision_chunk(1, PackedVector3Array([Vector3(-g, 0, -g), Vector3(-g, 0, g), Vector3(g, 0, g), Vector3(-g, 0, -g), Vector3(g, 0, g), Vector3(g, 0, -g)]), PackedByteArray([0, 0]), PackedByteArray([3, 3]))
	var id := sim.add_car(entry.key, UpgradeData.overrides_for(entry), false, 1)
	var spec := sim.get_car_spec(id)
	sim.reset_car(id, Transform3D(Basis(), Vector3(0, spec.cg_height + 0.02, 0)), 0.0)
	for i in range(180):
		sim.step(1.0 / 120.0)
	view = CarView.new()
	add_child(view)
	if entry.has("paint"):
		view.setup_entry(sim, id, entry, true)
	else:
		view.setup(sim, id, entry.key, true)
	view.set_physics_process(false)
	view.global_transform = sim.get_transform(id)
	if view.audio != null and view.audio.player != null:
		view.audio.player.stop()
		view.audio.set_process(false)
	# Pose wheels once from the settled state.
	view.telemetry = sim.get_telemetry(id)
	view.wheel_data = sim.get_wheel_data(id)

## Live paint preview (no rebuild).
func set_paint(color: Color, finish: String) -> void:
	if view == null or view._paint == null:
		return
	apply_finish(view._paint, color, finish)

static func apply_finish(m: ShaderMaterial, color: Color, finish: String) -> void:
	var f: Dictionary = CarData.FINISHES.get(finish, CarData.FINISHES["gloss"])
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("metallic", f.metallic)
	m.set_shader_parameter("roughness", f.roughness)
	m.set_shader_parameter("flake_amount", f.flake)
	m.set_shader_parameter("pearl", f.pearl)
	m.set_shader_parameter("clearcoat_amount", f.coat)
	m.set_shader_parameter("clearcoat_gloss", f.gloss)
	m.set_shader_parameter("candy", f.candy)
