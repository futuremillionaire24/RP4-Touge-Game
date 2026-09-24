extends Node3D
## M1 test drive: a racing circuit built by the native road mesher, the player's car and an
## optional AI field. Command-line flags (after `--`): car=<key> ai=<count> wet=<0..1>
## weather/camera tests: shot=<path> (saves a screenshot after `shot_delay` seconds).

const CIRCUIT := [
	Vector3(0, 0, 0), Vector3(250, 0, 0), Vector3(380, 0, -40), Vector3(420, 0, -150), Vector3(360, 0, -230),
	Vector3(250, 0, -220), Vector3(200, 0, -160), Vector3(140, 0, -200), Vector3(60, 0, -300), Vector3(-80, 0, -300),
	Vector3(-160, 0, -220), Vector3(-140, 0, -120), Vector3(-200, 0, -60), Vector3(-120, 0, 10),
]
const ROAD_Y := 0.14
const HALF_WIDTH := 6.5

var sim: NTSim
var cars: Array[CarView] = []
var player: CarView
var camera: ChaseCamera
var hud: DriveHUD
var driver: PlayerDriver
var args := {}
var _shot_timer := -1.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var launch: Dictionary = get_tree().root.get_meta("launch", {})
	for k in launch.keys():
		args[k] = str(launch[k])
	var env := EnvironmentRig.new()
	add_child(env)
	sim = NTSim.new()
	sim.name = "Sim"
	add_child(sim)
	var wet := float(args.get("wet", "0"))
	sim.wetness = wet
	RenderingServer.global_shader_parameter_set("nt_wetness", wet)
	RenderingServer.global_shader_parameter_set("nt_rain", wet)
	_build_track()
	_spawn_cars()
	camera = ChaseCamera.new()
	camera.sim = sim
	camera.target = player
	add_child(camera)
	driver = PlayerDriver.new()
	driver.sim = sim
	driver.car = player
	driver.camera = camera
	add_child(driver)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = DriveHUD.new()
	layer.add_child(hud)
	hud.bind(player, sim.get_car_spec(player.car_id))
	driver.rewind_started.connect(func(): hud.rewinding = true)
	driver.rewind_finished.connect(func(_s): hud.rewinding = false)
	player.collided.connect(func(imp, _p, _o): camera.add_shake(clampf(imp / 12000.0, 0.0, 1.0)))
	hud.toast("NEON TOUGE  —  TEST CIRCUIT", 3.0)
	if args.has("shot"):
		_shot_timer = float(args.get("shot_delay", "4"))
	if args.has("autodrive"):
		sim.set_ai(player.car_id, true)
		sim.set_ai_difficulty(player.car_id, 5)
		driver.enabled = false

func _build_track() -> void:
	var ctrl := PackedVector3Array()
	for p in CIRCUIT:
		ctrl.append(p + Vector3(0, ROAD_Y, 0))
	var rs := NTRoad.resample(ctrl, true, 3.0)
	var samples := TrackBuilder.circuit_samples(rs.points, rs.tangents, HALF_WIDTH)
	var root := Node3D.new()
	root.name = "Track"
	add_child(root)
	TrackBuilder.build_road(root, sim, 1, samples, {"closed": true, "lanes": 2, "marking": 0, "uv_length": 12.0})
	TrackBuilder.build_ground(root, sim, Vector3(110, 0, -140), 900.0, 150.0, 0.0, TrackBuilder.Surf.GRASS, 1000)
	var widths := PackedFloat32Array()
	widths.resize(rs.points.size())
	widths.fill(HALF_WIDTH)
	sim.set_racing_line(rs.points, PackedVector3Array(), widths, widths, true)
	_scatter_markers(root, rs.points, rs.tangents)

## Distance boards and cones give the eye speed references until the full world lands.
func _scatter_markers(root: Node3D, pts: PackedVector3Array, tans: PackedVector3Array) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.16
	cone.height = 0.45
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.35, 0.05)
	mat.roughness = 0.6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	var count := pts.size() / 10
	mm.instance_count = count * 2
	var idx := 0
	for i in range(0, pts.size(), 10):
		if idx >= count * 2 - 1:
			break
		var right := tans[i].cross(Vector3.UP).normalized()
		for side: float in [-1.0, 1.0]:
			var p: Vector3 = pts[i] + right * side * (HALF_WIDTH + 2.5) + Vector3(0, 0.1, 0)
			mm.set_instance_transform(idx, Transform3D(Basis(), p))
			idx += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	root.add_child(mmi)

func _spawn_cars() -> void:
	var key: String = args.get("car", CarData.DEFAULT_KEY)
	var ai_count := int(args.get("ai", "0"))
	var line := sim.get_racing_line_points()
	var n := line.size()
	var grid := []
	for slot in range(ai_count + 1):
		var idx := (n - 1 - slot * 3 + n) % n
		var nxt := (idx + 1) % n
		var dir := (line[nxt] - line[idx]).normalized()
		var right := dir.cross(Vector3.UP).normalized()
		var pos := line[idx] + right * (2.6 if slot % 2 == 1 else -2.6)
		grid.append(Transform3D(Basis.looking_at(dir, Vector3.UP), pos + Vector3(0, 0.7, 0)))
	var keys := NTSim.car_keys()
	for slot in range(ai_count + 1):
		var is_player := slot == 0
		var car_key: String = key if is_player else keys[(slot * 5) % keys.size()]
		var id := sim.add_car(car_key, {}, not is_player, 1000 + slot)
		sim.reset_car(id, grid[slot], 0.0)
		if is_player:
			sim.set_assists(id, Settings.assists_dict())
		else:
			sim.set_ai_difficulty(id, int(Settings.get_value("assists", "difficulty", 3)))
		var view := CarView.new()
		add_child(view)
		view.setup(sim, id, car_key, is_player)
		cars.append(view)
		if is_player:
			player = view

func _process(delta: float) -> void:
	if player and not player.telemetry.is_empty():
		var t := player.telemetry
		hud.race_text = "LAP %d   %s" % [maxi(1, int(t.lap) + 1), "WRONG WAY" if t.wrong_way else ""]
	if Pad.pressed("pause"):
		Haptics.clear()
		get_tree().change_scene_to_file("res://scenes/launcher.tscn")
	if _shot_timer > 0.0:
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			_save_shot(args.shot)

func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("screenshot saved: ", path)
	if args.has("quit_after_shot"):
		get_tree().quit()
