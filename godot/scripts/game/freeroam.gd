extends Node3D
## Open-world free roam: builds the world on a worker thread behind a loading screen, streams
## chunks around the player, spawns at the Daikoku PA festival hub.
## Args (after --): car=<key> time=<hours> weather=<0-6> season=<0-3> spawn=<poi id>
##   shot=<path> shot_delay=<s> quit_after_shot autodrive

var world: NTWorld
var sim: NTSim
var streamer: WorldStreamer
var env: EnvironmentRig
var sky: SkyWeather
var lights: LightPool
var camera: ChaseCamera
var hud: DriveHUD
var driver: PlayerDriver
var player: CarView
var args := {}
var _loading: Control
var _load_label: Label
var _build_task := -1
var _state := "building"
var _district := -1
var _shot_timer := -1.0
var _spawn_xform: Transform3D
var markers: EventMarkers
var race: RaceManager
var race_hud: RaceHUD
var _prompt_event := {}
var _saved_conditions := {}
var _follow_player := true
var traffic_view: TrafficView
var skills: SkillSystem
var activities: Activities
var minimap: Minimap
var police: Node
var layer: CanvasLayer
var _entry := {} # Profile garage entry being driven (empty for dev runs)
var _odo_m := 0.0
var _play_s := 0.0
var _car_probe: ReflectionProbe
var _probe_tick := 0
var _cas_rect: ColorRect
var gps_ribbon: GPSRibbon

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var launch: Dictionary = get_tree().root.get_meta("launch", {})
	for k in launch.keys():
		args[k] = str(launch[k])
	_make_loading_screen()
	env = EnvironmentRig.new()
	add_child(env)
	sim = NTSim.new()
	sim.name = "Sim"
	sim.running = false
	add_child(sim)
	world = NTWorld.new()
	_build_task = WorkerThreadPool.add_task(func(): world.build(int(args.get("seed", "1"))), true, "world build")

func _make_loading_screen() -> void:
	var load_layer := CanvasLayer.new()
	load_layer.layer = 10
	add_child(load_layer)
	_loading = ColorRect.new()
	(_loading as ColorRect).color = Color(0.02, 0.01, 0.04)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	load_layer.add_child(_loading)
	var title := Label.new()
	title.text = "峠  NEON TOUGE"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1, 0.18, 0.53))
	title.position = Vector2(80, 520)
	_loading.add_child(title)
	_load_label = Label.new()
	_load_label.add_theme_font_size_override("font_size", 20)
	_load_label.add_theme_color_override("font_color", Color(0.15, 0.91, 1.0))
	_load_label.position = Vector2(84, 590)
	_loading.add_child(_load_label)

func _process(delta: float) -> void:
	match _state:
		"building":
			_load_label.text = "Generating Japan… terrain, roads, city"
			if WorkerThreadPool.is_task_completed(_build_task):
				WorkerThreadPool.wait_for_task_completion(_build_task)
				_begin_streaming()
		"streaming":
			_load_label.text = "Streaming world… %d chunks" % streamer.loaded_count()
		"playing":
			_play_update(delta)

func _find_spawn() -> Transform3D:
	var want: String = args.get("spawn", "spawn_festival")
	for p in world.pois():
		if p.id == want:
			var pos: Vector3 = p.position
			var road := world.nearest_road(pos, 200.0)
			if not road.is_empty():
				# Step 30 m into the road so we never spawn at a dead end or a junction mouth.
				var rs := world.road_samples(road.road)
				var n: int = rs.centers.size()
				var i: int = clampi(road.sample, 12, maxi(12, n - 12))
				if road.sample > n / 2:
					i = clampi(road.sample - 10, 12, n - 12)
				else:
					i = clampi(road.sample + 10, 12, n - 12)
				var at: Vector3 = rs.centers[i]
				var dir: Vector3 = rs.tangents[i]
				return Transform3D(Basis.looking_at(dir, Vector3.UP), at + Vector3(0, 1.0, 0))
			return Transform3D(Basis(Vector3.UP, p.yaw), pos + Vector3(0, 1.0, 0))
	return Transform3D(Basis(), Vector3(0, world.height_at(0, 0) + 2.0, 0))

func _begin_streaming() -> void:
	_state = "streaming"
	streamer = WorldStreamer.new()
	streamer.name = "World"
	add_child(streamer)
	streamer.setup(world, sim)
	_spawn_xform = _find_spawn()
	streamer.prime(_spawn_xform.origin)
	streamer.initial_load_done.connect(_on_initial_load, CONNECT_ONE_SHOT)

func _on_initial_load() -> void:
	# The festival passes a garage index (upgrades, tune, paint); dev/test runs pass car=<key>.
	var key: String = args.get("car", "sylph_s2")
	_entry = {}
	if args.has("garage_index") and int(args.garage_index) < Profile.data.garage.size():
		_entry = Profile.data.garage[int(args.garage_index)]
		key = _entry.key
	var id := sim.add_car(key, Profile.overrides_for(_entry) if not _entry.is_empty() else {}, false, 1)
	sim.reset_car(id, _spawn_xform, 0.0)
	sim.set_assists(id, Settings.assists_dict())
	player = CarView.new()
	add_child(player)
	if _entry.is_empty():
		player.setup(sim, id, key, true)
	else:
		player.setup_entry(sim, id, _entry, true)
	# Dynamic time-sliced ReflectionProbe on player car (Forza / GT dynamic vehicle reflection).
	_car_probe = ReflectionProbe.new()
	_car_probe.name = "PlayerCarProbe"
	_car_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_car_probe.size = Vector3(250.0, 90.0, 250.0)
	_car_probe.origin_offset = Vector3(0.0, 1.2, 0.0)
	_car_probe.box_projection = true
	_car_probe.interior = false
	_car_probe.enable_shadows = false
	_car_probe.cull_mask = 0xFFFFFFFD # Exclude car layer 2 to avoid self-reflection
	player.add_child(_car_probe)

	camera = ChaseCamera.new()
	camera.sim = sim
	camera.target = player
	add_child(camera)
	driver = PlayerDriver.new()
	driver.sim = sim
	driver.car = player
	driver.camera = camera
	add_child(driver)
	lights = LightPool.new()
	add_child(lights)
	lights.streamer = streamer
	lights.camera = camera
	sky = SkyWeather.new()
	add_child(sky)
	sky.setup(env, sim, camera)
	sky.time_of_day = float(args.get("time", "20.5"))
	sky.season = float(args.get("season", "0"))
	sky.set_weather(int(args.get("weather", "0")), true)

	# Retro Arcade & CAS post-processing layer (CanvasLayer 1): Initial D speedlines, anamorphic flares, CAS filter.
	var pp_layer := CanvasLayer.new()
	pp_layer.layer = 1
	add_child(pp_layer)
	_cas_rect = ColorRect.new()
	_cas_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cas_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cas_mat := ShaderMaterial.new()
	cas_mat.shader = preload("res://shaders/retro_arcade_fx.gdshader")
	cas_mat.set_shader_parameter("sharpness", 0.65)
	var arcade_opt: int = int(Settings.get_value("graphics", "retro_arcade", 1))
	cas_mat.set_shader_parameter("arcade_mode", arcade_opt)
	_cas_rect.material = cas_mat
	pp_layer.add_child(_cas_rect)

	# HUD CanvasLayer (layer 2): decoupled from 3D scaling, perfectly razor-sharp at native 1334x750.
	layer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	hud = DriveHUD.new()
	layer.add_child(hud)
	hud.bind(player, sim.get_car_spec(id))
	Profile.level_up.connect(func(lv): hud.toast("FESTIVAL LEVEL %d  ·  OMIKUJI DRAW EARNED" % lv, 3.5))
	driver.rewind_started.connect(func(): hud.rewinding = true)
	driver.rewind_finished.connect(func(_s): hud.rewinding = false)
	player.collided.connect(func(imp, _p, _o):
		camera.add_shake(clampf(imp / 12000.0, 0.0, 1.0))
		if imp > 25000.0 and police:
			police.add_heat(0.2)
	)
	race_hud = RaceHUD.new()
	race_hud.visible = false
	layer.add_child(race_hud)
	markers = EventMarkers.new()
	add_child(markers)
	markers.build(world)
	gps_ribbon = GPSRibbon.new()
	gps_ribbon.name = "GPSRibbon"
	add_child(gps_ribbon)
	# Ambient traffic (drives on the left), skill chains, PR stunts, collectibles, minimap.
	sim.set_world(world)
	sim.set_traffic_density(float(Settings.get_value("graphics", "traffic_density", 1.0)))
	sim.set_traffic_enabled(true)
	traffic_view = TrafficView.new()
	traffic_view.sim = sim
	add_child(traffic_view)
	skills = SkillSystem.new()
	skills.sim = sim
	skills.car = player
	add_child(skills)
	hud.skills = skills
	skills.chain_banked.connect(func(p): hud.toast("SKILL CHAIN  +%s" % RaceHUD._group(p), 2.0))
	skills.chain_lost.connect(func(_p): hud.toast("CHAIN LOST", 1.5))
	activities = Activities.new()
	activities.sim = sim
	activities.player = player
	activities.skills = skills
	add_child(activities)
	activities.build(world)
	activities.result.connect(_on_activity_result)
	police = PoliceManagerClass.new()
	add_child(police)
	police.setup(sim, world, player, hud, self)
	minimap = Minimap.new()
	layer.add_child(minimap)
	minimap.setup(world, player)
	minimap.markers = markers
	minimap.activities = activities
	if args.has("autodrive"):
		var road := world.nearest_road(_spawn_xform.origin, 300.0)
		_setup_autodrive(id, road)
	sim.running = true
	_loading.get_parent().queue_free()
	_state = "playing"
	if args.has("event"):
		start_event(EventData.get_event(args.event))
	if args.has("shot"):
		_shot_timer = float(args.get("shot_delay", "6"))

## Test helper: the car follows the named road with the AI (used for automated screenshots).
func _setup_autodrive(id: int, road: Dictionary) -> void:
	var name: String = args.get("route", road.get("road", ""))
	var rs := world.road_samples(name)
	if rs.is_empty():
		return
	sim.set_racing_line(rs.centers, rs.ups, rs.width_left, rs.width_right, rs.closed)
	sim.set_ai(id, true)
	sim.set_ai_difficulty(id, 4)
	sim.reset_car(id, _spawn_xform, 0.0)
	driver.enabled = false

func _play_update(delta: float) -> void:
	# Dynamic time-sliced reflection probe update (10 Hz on 60 FPS target).
	_probe_tick += 1
	if _probe_tick % 6 == 0 and _car_probe:
		_car_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	var pos := player.global_position
	if _follow_player:
		streamer.focus = pos
		streamer.focus_velocity = sim.get_velocity(player.car_id)
	lights.night = sky.night
	var d := world.district_at(pos.x, pos.z)
	if d != _district:
		_district = d
		hud.toast(world.district_name(d).to_upper(), 2.5)
	var t := player.telemetry
	if _cas_rect != null and _cas_rect.material != null:
		var scale_factor: float = get_viewport().scaling_3d_scale
		var mat := _cas_rect.material as ShaderMaterial
		mat.set_shader_parameter("scale_factor", scale_factor)
		var spd: float = absf(float(t.get("speed_kmh", 0.0)))
		var spd_ratio := clampf((spd - 70.0) / 120.0, 0.0, 1.0)
		mat.set_shader_parameter("speed_intensity", spd_ratio)
		var steer_input: float = absf(Pad.steer)
		mat.set_shader_parameter("drift_intensity", steer_input * spd_ratio)
	var hh := int(sky.time_of_day)
	var mm := int((sky.time_of_day - hh) * 60.0)
	hud.race_text = "" if race != null else "%02d:%02d  %s  %s" % [hh, mm, SkyWeather.W_NAMES[sky.weather], world.district_name(d)]
	# Auto headlights.
	if player.lights_on != (sky.night > 0.35 or sky.fog_amount > 0.5):
		player.set_lights(sky.night > 0.35 or sky.fog_amount > 0.5)
	# Fell into the sea / off the world: recover onto the nearest road.
	if pos.y < -3.0 or Pad.pressed("reset_car"):
		_recover()
	# Event beacons: park inside one and press A to race.
	if race == null:
		_prompt_event = markers.event_at(pos, float(t.get("speed", 0.0)))
		if not _prompt_event.is_empty():
			hud.toast("A — %s  (%s)" % [_prompt_event.name, EventData.TYPE_NAMES[_prompt_event.type]], 0.3)
			if gps_ribbon and not gps_ribbon.visible:
				var ev_route := Route.from_roads(world, _prompt_event.roads, _prompt_event.closed)
				gps_ribbon.set_route(ev_route)
			if Pad.pressed("handbrake"):
				start_event(_prompt_event)
		elif gps_ribbon and gps_ribbon.visible and race == null:
			gps_ribbon.clear()
	# Odometer and play time for the career stats.
	_odo_m += float(t.get("speed", 0.0)) * delta
	_play_s += delta
	if Pad.pressed("map") and race == null:
		_open_world_map()
	elif Pad.pressed("pause"):
		_open_pause()
	if _shot_timer > 0.0:
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			_save_shot(args.shot)

func start_event(ev: Dictionary) -> void:
	if ev.is_empty() or race != null:
		return
	if not _entry.is_empty():
		var pi := int(_entry.get("pi", 0))
		if CarData.pi_class(pi) > int(ev.get("class_max", 6)):
			hud.toast("%s — CLASS %s OR LOWER ONLY (YOUR CAR: %s)" % [ev.name.to_upper(), CarData.CLASS_NAMES[int(ev.class_max)], CarData.class_label(pi)], 3.0)
			return
		if int(ev.get("level", 0)) > int(Profile.data.level):
			hud.toast("%s — REACH FESTIVAL LEVEL %d" % [ev.name.to_upper(), int(ev.level)], 3.0)
			return
	_saved_conditions = {"time": sky.time_of_day, "weather": sky.weather, "scale": sky.time_scale}
	sky.time_of_day = float(ev.get("time", sky.time_of_day))
	sky.set_weather(int(ev.get("weather", sky.weather)), true)
	sky.weather_lock = true
	sky.time_scale = 0.0
	markers.set_markers_visible(false)
	sim.set_traffic_enabled(false)
	skills.enabled = false
	if activities:
		activities.enabled = false
	if police:
		police.enabled = (ev.get("type", 0) == 4) # Outrun events have active police pursuits!
		if ev.get("type", 0) == 4:
			police.add_heat(1.0)
	race = RaceManager.new()
	race.world = world
	race.sim = sim
	race.player = player
	race.camera = camera
	race.driver = driver
	race.host = self
	race.hud = race_hud
	add_child(race)
	race.race_finished.connect(func(result): Profile.record_result(result))
	race.tree_exited.connect(_on_race_over)
	# Stream the start area (with collision) before the grid appears there.
	var route := Route.from_roads(world, ev.roads, ev.closed)
	var start_pos := route.centers[route.start_index(int(ev.rivals) + 1)]
	sim.set_frozen(player.car_id, true)
	_follow_player = false
	streamer.focus = start_pos
	streamer.focus_velocity = Vector3.ZERO
	hud.toast(ev.name.to_upper(), 3.0)
	var waited := 0.0
	while not streamer.has_collision_at(start_pos) and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	sim.set_frozen(player.car_id, false)
	_follow_player = true
	race.start(ev)
	minimap.route_line = race.route.polyline(4)
	if gps_ribbon:
		gps_ribbon.set_route(race.route)
	if args.has("autodrive"):
		# Automated tests: the AI drives the player's car too.
		sim.set_ai(player.car_id, true)
		sim.set_ai_difficulty(player.car_id, 5)

func _on_race_over() -> void:
	race = null
	sky.time_of_day = _saved_conditions.get("time", sky.time_of_day)
	sky.set_weather(int(_saved_conditions.get("weather", 0)), true)
	sky.time_scale = _saved_conditions.get("scale", 1.0)
	sky.weather_lock = false
	markers.set_markers_visible(true)
	sim.set_traffic_enabled(true)
	skills.enabled = true
	if activities:
		activities.enabled = true
	if police:
		police.enabled = true
	minimap.route_line = PackedVector2Array()
	if gps_ribbon:
		gps_ribbon.clear()

func _on_activity_result(kind: String, _id: String, value: float, stars: int) -> void:
	if kind == "Barn Find":
		hud.toast("BARN FIND DISCOVERED: %s" % _id.to_upper(), 5.0)
		return
	if kind == "Omamori":
		hud.toast("OMAMORI  %d / 30" % int(value), 3.0)
		return
	var unit := "km/h" if kind.begins_with("Speed") else ("pts" if kind == "Drift Zone" else "m")
	var star_str := "★".repeat(stars) + "☆".repeat(3 - stars)
	hud.toast("%s  %d %s  %s" % [kind.to_upper(), int(value), unit, star_str], 3.5)

func _open_pause() -> void:
	if hud: hud.visible = false
	if race_hud: race_hud.visible = false
	if minimap: minimap.visible = false
	var pm := PauseMenu.new()
	add_child(pm)
	var opts := []
	var sub := world.district_name(_district)
	if race != null:
		sub = race.event.get("name", "Event")
		opts.append(["RESTART EVENT", "restart"])
		opts.append(["QUIT EVENT", "quit_event"])
	else:
		opts.append(["WORLD MAP · GPS", "world_map"])
		opts.append(["RECOVER CAR", "recover"])
	opts.append(["CONTROLLER SETUP", "controller"])
	opts.append(["FESTIVAL · GARAGE", "festival"])
	opts.append(["TITLE SCREEN", "title"])
	pm.chosen.connect(_on_pause_choice)
	pm.tree_exited.connect(func():
		if not get_tree().paused:
			if hud: hud.visible = true
			if race_hud: race_hud.visible = (race != null)
			if minimap: minimap.visible = true
	)
	pm.open("Paused", sub, opts)

const ControllerScreenClass = preload("res://scripts/ui/screens/controller_screen.gd")
const WorldMapClass = preload("res://scripts/ui/world_map.gd")
const PoliceManagerClass = preload("res://scripts/game/police_manager.gd")

func _on_pause_choice(id: String) -> void:
	match id:
		"controller":
			if hud: hud.visible = false
			if race_hud: race_hud.visible = false
			if minimap: minimap.visible = false
			get_tree().paused = true
			var cl := CanvasLayer.new()
			cl.layer = 25
			add_child(cl)
			var dim := ColorRect.new()
			dim.color = Color(0.01, 0.01, 0.02, 0.95)
			dim.set_anchors_preset(Control.PRESET_FULL_RECT)
			cl.add_child(dim)
			var ctrl = ControllerScreenClass.new()
			cl.add_child(ctrl)
			ctrl.enter()
			ctrl.tree_exited.connect(func():
				cl.queue_free()
				_open_pause()
			)
		"world_map":
			_open_world_map()
		"recover":
			_recover()
		"restart":
			var ev: Dictionary = race.event
			race.abort()
			await get_tree().process_frame
			start_event(ev)
		"quit_event":
			race.abort()
		"festival", "title":
			_commit_stats()
			Haptics.clear()
			get_tree().root.set_meta("festival_screen", "hub" if id == "festival" else "title")
			get_tree().change_scene_to_file("res://scenes/festival.tscn")

func _open_world_map() -> void:
	if not world or not player:
		return
	if hud: hud.visible = false
	if race_hud: race_hud.visible = false
	if minimap: minimap.visible = false
	get_tree().paused = true
	var wm = WorldMapClass.new()
	add_child(wm)
	wm.setup(world, player, markers, activities, self)
	wm.waypoint_set.connect(func(pos: Vector3, poly: PackedVector2Array, centers_3d: PackedVector3Array, ups_3d: PackedVector3Array):
		if minimap:
			minimap.route_line = poly
		if gps_ribbon:
			if pos != Vector3.INF and centers_3d.size() > 1:
				gps_ribbon.set_samples(centers_3d, ups_3d)
			else:
				gps_ribbon.clear()
		if pos != Vector3.INF:
			hud.toast("GPS WAYPOINT SET", 2.0)
		else:
			hud.toast("GPS ROUTE CLEARED", 1.5)
	)
	wm.fast_travel_requested.connect(func(pos: Vector3, dir: Vector3):
		get_tree().paused = false
		sim.reset_car(player.car_id, Transform3D(Basis.looking_at(dir, Vector3.UP), pos), 0.0)
		if camera:
			camera.snap()
		hud.toast("FAST TRAVEL COMPLETE", 2.0)
		if hud: hud.visible = true
		if race_hud: race_hud.visible = (race != null)
		if minimap: minimap.visible = true
	)
	wm.closed.connect(func():
		get_tree().paused = false
		if hud: hud.visible = true
		if race_hud: race_hud.visible = (race != null)
		if minimap: minimap.visible = true
	)

## Odometer / play time into the garage entry and career stats.
func _commit_stats() -> void:
	var km := _odo_m / 1000.0
	if not _entry.is_empty():
		_entry["km"] = float(_entry.get("km", 0.0)) + km
	Profile.data.stats.distance_km = float(Profile.data.stats.distance_km) + km
	Profile.data.stats.play_seconds = float(Profile.data.stats.play_seconds) + _play_s
	_odo_m = 0.0
	_play_s = 0.0
	Profile.save()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _state == "playing":
			_commit_stats()
			if not get_tree().paused:
				_open_pause.call_deferred()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android back button opens the pause menu.
		if _state == "playing" and not get_tree().paused:
			_open_pause.call_deferred() # can't add children during the notification

func _recover() -> void:
	var road := world.nearest_road(player.global_position, 400.0)
	if road.is_empty():
		return
	var dir: Vector3 = road.tangent
	sim.reset_car(player.car_id, Transform3D(Basis.looking_at(dir, Vector3.UP), road.position + Vector3(0, 1.2, 0)), 0.0)
	camera.snap()

func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("screenshot saved: ", path, "  chunks ", streamer.loaded_count(), "  fps ", Perf.fps, "  traffic ", sim.traffic_active_count())
	if OS.is_debug_build():
		var nearest := INF
		var nearest_pos := Vector3.ZERO
		for m in range(6):
			var b := sim.traffic_buffer(m)
			for i in range(0, b.size(), 16):
				var p := Vector3(b[i + 3], b[i + 7], b[i + 11])
				var d := p.distance_to(player.global_position)
				if d < nearest:
					nearest = d
					nearest_pos = p
		print("nearest traffic: %.1f m at %s (player %s)" % [nearest, nearest_pos, player.global_position])
	if args.has("quit_after_shot"):
		get_tree().quit()
