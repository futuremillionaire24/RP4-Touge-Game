class_name CarStage
extends Node3D
## Festival car stage behind the menus: a night car-meet pad (glossy asphalt, neon rim lights,
## grid lines), the selected car settled on its real suspension by a private NTSim, and an
## orbit camera (auto-rotate, right stick to look around). Car swaps are debounced so fast list
## scrolling doesn't rebuild meshes every frame.

const FLOOR_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 line_color : source_color = vec3(1.0, 0.18, 0.53);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float r = length(wpos.xz);
	vec2 g = abs(fract(wpos.xz / 2.0 + 0.5) - 0.5) * 2.0;
	float line = 1.0 - smoothstep(0.0, 0.035, min(g.x, g.y));
	float ring = 1.0 - smoothstep(0.0, 0.05, abs(r - 4.2));
	float fade = smoothstep(18.0, 4.0, r);
	ALBEDO = vec3(0.025, 0.022, 0.03);
	ROUGHNESS = 0.18;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = line_color * (line * 0.22 + ring * 1.6) * fade;
}
"""

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
	_env = Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.015, 0.01, 0.04)
	sky_mat.sky_horizon_color = Color(0.12, 0.04, 0.16)
	sky_mat.ground_horizon_color = Color(0.08, 0.03, 0.1)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.6
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.1
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_hdr_threshold = 1.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	# Key light (sodium-white overhead), neon rims, cool fill.
	var key := SpotLight3D.new()
	key.position = Vector3(0.0, 7.0, 1.0)
	key.rotation_degrees = Vector3(-85, 0, 0)
	key.spot_range = 14.0
	key.spot_angle = 42.0
	key.light_energy = 9.0
	key.light_color = Color(1.0, 0.93, 0.85)
	key.shadow_enabled = true
	add_child(key)
	for s in [[Vector3(-5.5, 1.6, -3.0), UIKit.NEON], [Vector3(5.5, 1.4, 3.5), UIKit.CYAN]]:
		var o := OmniLight3D.new()
		o.position = s[0]
		o.light_color = s[1]
		o.light_energy = 5.0
		o.omni_range = 12.0
		add_child(o)
		# Visible neon tube behind each light.
		var tube := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.04
		cm.height = 3.2
		tube.mesh = cm
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.albedo_color = s[1]
		tm.emission_enabled = true
		tm.emission = s[1]
		tm.emission_energy_multiplier = 4.0
		tube.material_override = tm
		# Overhead canopy tubes running front-to-back above each side of the car.
		var p: Vector3 = s[0]
		tube.position = Vector3(signf(p.x) * 2.6, 3.6, 0.0)
		tube.rotation_degrees = Vector3(90, 0, 0)
		add_child(tube)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 150, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.7, 1.0)
	add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	var sh := Shader.new()
	sh.code = FLOOR_SHADER
	var fm := ShaderMaterial.new()
	fm.shader = sh
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
