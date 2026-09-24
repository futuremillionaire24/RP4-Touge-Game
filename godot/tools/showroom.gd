extends Node3D
## Car art review: renders every car in a professional automotive photo studio (dark cyclorama,
## overhead + strip softboxes, semi-gloss floor, soft contact shadow) and saves contact sheets.
##   car_<key>.png         3/4 front low, 3/4 rear, side profile
##   car_<key>_detail.png  front wheel, headlight corner, tail corner (skip with detail=0)
## Usage: godot --path . --resolution 1334x750 -- scene=showroom out=D:/path/dir [cars=a,b]
##        [tonemap=agx|aces] [exposure=1.0] [detail=0|1] [probe=0|1] [bg=dark|light]

const Studio := preload("res://scripts/vehicle/present_studio.gd")

var out_dir := "user://showroom"
var cars: PackedStringArray = []
var tonemap := "agx"
var exposure := 1.0
var detail := true
var use_probe := true
var bg := "dark"
var balls := false
var cam: Camera3D
var env: Environment
var probe: ReflectionProbe

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"out": out_dir = kv[1]
			"cars": cars = kv[1].split(",")
			"tonemap": tonemap = kv[1]
			"exposure": exposure = float(kv[1])
			"detail": detail = kv[1] != "0"
			"probe": use_probe = kv[1] != "0"
			"bg": bg = kv[1]
			"balls": balls = kv[1] != "0"
	if cars.is_empty():
		cars = PackedStringArray(CarData.keys())
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_build_studio()
	var sim := NTSim.new()
	sim.running = false
	add_child(sim)
	var g := 50.0
	sim.set_collision_chunk(1, PackedVector3Array([Vector3(-g, 0, -g), Vector3(-g, 0, g), Vector3(g, 0, g), Vector3(-g, 0, -g), Vector3(g, 0, g), Vector3(g, 0, -g)]), PackedByteArray([0, 0]), PackedByteArray([3, 3]))
	cam = Camera3D.new()
	cam.current = true
	cam.cull_mask = 0xFFFFF & ~(1 << (Studio.RIG_LAYER - 1))
	add_child(cam)
	# Let the sky radiance and the probe settle once (the car is not in the probe).
	for f in range(12):
		await RenderingServer.frame_post_draw
	for key in cars:
		var id := sim.add_car(key, {}, false, 1)
		var spec := sim.get_car_spec(id)
		sim.reset_car(id, Transform3D(Basis(), Vector3(0, spec.cg_height, 0)), 0.0)
		# Settle suspension for the static pose.
		for i in range(240):
			sim.step(1.0 / 120.0)
		var view := CarView.new()
		add_child(view)
		view.setup(sim, id, key, true)
		view.set_physics_process(false)
		view.global_transform = sim.get_transform(id)
		view.audio.player.stop()
		view.audio.set_process(false)
		view.telemetry = sim.get_telemetry(id)
		view.wheel_data = sim.get_wheel_data(id)
		_pose_wheels(view)
		Studio.set_layer_recursive(view, Studio.CAR_LAYER)
		await RenderingServer.frame_post_draw
		var bb := Studio.visual_aabb(view.visual)
		var main := []
		# 3/4 front low (the hero), 3/4 rear from the other side, side profile on a long lens.
		main.append(await _shot(bb, 38.0, 0.72, 27.0, 0.86))
		main.append(await _shot(bb, 218.0, 1.05, 27.0, 0.86))
		main.append(await _shot(bb, 90.0, 0.62, 18.0, 0.9))
		_save_sheet(main, out_dir.path_join("car_%s.png" % key))
		if detail:
			var shots := []
			shots.append(await _detail_wheel(view, bb))
			shots.append(await _detail_lamp(view, bb, true))
			shots.append(await _detail_lamp(view, bb, false))
			_save_sheet(shots, out_dir.path_join("car_%s_detail.png" % key))
		print("SHOWROOM ", key)
		view.queue_free()
		sim.set_frozen(id, true)
		sim.reset_car(id, Transform3D(Basis(), Vector3(0, -50, 0)), 0.0)
		await RenderingServer.frame_post_draw
	get_tree().quit()

func _pose_wheels(view: CarView) -> void:
	var wd := view.wheel_data
	var stride := NTSim.WHEEL_STRIDE
	var wheels: Array = view.visual.get_meta("wheels")
	for i in range(4):
		var o := i * stride
		var w: Node3D = wheels[i]
		w.position = Vector3(wd[o], wd[o + 1], wd[o + 2])
		# A little steering lock on the fronts reads as "parked for a photo".
		w.rotation.y = 0.0

## Studio: dark cyclorama, big overhead softbox, two long side strips (belt-line highlight),
## two vertical front-corner strips, a rear kicker, plus shadow/fill lights that only add diffuse
## (the softboxes provide all the specular through the sky radiance map and the probe).
func _build_studio() -> void:
	var light_bg := bg == "light"
	var white := Color(1.0, 0.985, 0.96)
	var panels := [
		# Overhead scrim: a big softbox over the whole car (hood/roof/boot streak, even at the
		# grazing angles a low camera sees on the bonnet).
		{"c": Vector3(0, 4.4, -0.4), "u": Vector3(1.9, 0, 0), "v": Vector3(0, 0, 5.2), "color": white, "energy": 2.6, "soft": 0.05},
		# Front-top angled box (bonnet and windscreen seen from the front three-quarter).
		{"c": Vector3(0, 3.4, -7.8), "u": Vector3(2.6, 0, 0), "v": Vector3(0, 1.0, -0.55), "color": white, "energy": 1.6, "soft": 0.08},
		# Side strips, slightly tilted toward the car (horizontal belt-line highlight).
		{"c": Vector3(-6.2, 1.55, 0.0), "u": Vector3(0, 0, 5.2), "v": Vector3(0.14, 0.5, 0), "color": white, "energy": 2.2, "soft": 0.08},
		{"c": Vector3(6.2, 1.55, 0.0), "u": Vector3(0, 0, 5.2), "v": Vector3(-0.14, 0.5, 0), "color": white, "energy": 2.2, "soft": 0.08},
		# Low side strips (rocker / lower door line).
		{"c": Vector3(-5.8, 0.35, 0.0), "u": Vector3(0, 0, 4.2), "v": Vector3(0, 0.12, 0), "color": white, "energy": 1.2, "soft": 0.2},
		{"c": Vector3(5.8, 0.35, 0.0), "u": Vector3(0, 0, 4.2), "v": Vector3(0, 0.12, 0), "color": white, "energy": 1.2, "soft": 0.2},
		# Vertical strips at the front and rear corners (fender / quarter verticals).
		{"c": Vector3(-4.8, 2.0, -5.6), "u": Vector3(0, 1.8, 0), "v": Vector3(0.3, 0, -0.26), "color": white, "energy": 1.8, "soft": 0.1},
		{"c": Vector3(4.8, 2.0, -5.6), "u": Vector3(0, 1.8, 0), "v": Vector3(0.3, 0, 0.26), "color": white, "energy": 1.8, "soft": 0.1},
		{"c": Vector3(-4.8, 2.0, 5.8), "u": Vector3(0, 1.8, 0), "v": Vector3(0.3, 0, 0.26), "color": white, "energy": 1.4, "soft": 0.1},
		{"c": Vector3(4.8, 2.0, 5.8), "u": Vector3(0, 1.8, 0), "v": Vector3(0.3, 0, -0.26), "color": white, "energy": 1.4, "soft": 0.1},
		# Rear top kicker (separates the roofline and boot from the backdrop).
		{"c": Vector3(0, 3.2, 7.6), "u": Vector3(2.8, 0, 0), "v": Vector3(0, 0.9, 0.5), "color": white, "energy": 1.3, "soft": 0.12},
	]
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_1024
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var room := {
		"origin": Vector3(0, 0.6, 0),
		"top_color": Color(0.012, 0.012, 0.014) if not light_bg else Color(0.5, 0.5, 0.52),
		"wall_color": Color(0.03, 0.03, 0.034) if not light_bg else Color(0.42, 0.42, 0.44),
		"horizon_color": Color(0.07, 0.07, 0.075) if not light_bg else Color(0.55, 0.55, 0.56),
		"floor_color": Color(0.02, 0.02, 0.022) if not light_bg else Color(0.3, 0.3, 0.31),
		"pool_color": Color(0.07, 0.07, 0.072) if not light_bg else Color(0.6, 0.6, 0.6),
		"pool_radius": 7.0,
		"horizon_width": 9.0,
	}
	sky.sky_material = Studio.sky_material(panels, room)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.022)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX if tonemap == "agx" else Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = exposure
	env.tonemap_white = 12.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var cyc := MeshInstance3D.new()
	cyc.name = "Cyclorama"
	cyc.mesh = Studio.cyclorama(20.0, 4.0, 14.0)
	var fa := Color(0.06, 0.06, 0.063) if not light_bg else Color(0.55, 0.55, 0.56)
	var wa := Color(0.035, 0.035, 0.04) if not light_bg else Color(0.62, 0.62, 0.63)
	cyc.material_override = Studio.cyc_material(fa, wa, 0.3, 4.0)
	cyc.set_meta("present_ignore", true)
	add_child(cyc)
	Studio.add_panels(self, panels, Studio.RIG_LAYER)

	# Overhead soft key: soft shadow + diffuse. Punctual lights carry almost no specular, so the
	# reflection of the softboxes (not a point highlight) carries the shape of the body.
	var key := SpotLight3D.new()
	key.position = Vector3(0, 7.0, 0.0)
	key.rotation_degrees = Vector3(-90, 0, 0)
	key.spot_range = 12.0
	key.spot_angle = 48.0
	key.spot_angle_attenuation = 2.2
	key.spot_attenuation = 0.2
	key.light_energy = 4.0
	key.light_color = Color(1.0, 0.98, 0.95)
	key.light_specular = 0.08
	key.light_size = 3.0
	key.shadow_enabled = true
	key.shadow_blur = 2.5
	key.shadow_bias = 0.03
	key.shadow_normal_bias = 0.8
	add_child(key)
	for side in [-1.0, 1.0]:
		var fill := SpotLight3D.new()
		fill.look_at_from_position(Vector3(side * 6.5, 1.4, 0), Vector3(0, 0.55, 0), Vector3.UP)
		fill.spot_range = 10.0
		fill.spot_angle = 32.0
		fill.spot_angle_attenuation = 1.8
		fill.light_energy = 1.2
		fill.light_specular = 0.0
		fill.light_color = Color(1.0, 0.99, 0.97)
		add_child(fill)
	var front := SpotLight3D.new()
	front.look_at_from_position(Vector3(0, 2.4, -8.0), Vector3(0, 0.5, 0), Vector3.UP)
	front.spot_range = 13.0
	front.spot_angle = 26.0
	front.spot_angle_attenuation = 1.8
	front.light_energy = 1.0
	front.light_specular = 0.0
	add_child(front)
	if balls:
		# Look-dev references: chrome ball and gloss black ball beside the car.
		for b in [[Vector3(-2.2, 0.3, -2.9), Color(0.95, 0.95, 0.95), 1.0, 0.02], [Vector3(-2.2, 0.3, -2.1), Color(0.02, 0.02, 0.02), 0.0, 0.05]]:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.3
			sm.height = 0.6
			mi.mesh = sm
			var m := StandardMaterial3D.new()
			m.albedo_color = b[1]
			m.metallic = b[2]
			m.roughness = b[3]
			mi.material_override = m
			mi.position = b[0]
			mi.layers = 1 << (Studio.CAR_LAYER - 1)
			mi.set_meta("present_ignore", true)
			add_child(mi)
	if use_probe:
		probe = ReflectionProbe.new()
		probe.name = "StudioProbe"
		probe.size = Vector3(40, 16, 40)
		probe.position = Vector3(0, 7.9, 0)
		probe.origin_offset = Vector3(0, -7.3, 0)
		probe.box_projection = true
		probe.interior = true
		probe.enable_shadows = false
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.cull_mask = (1 << (Studio.SET_LAYER - 1)) | (1 << (Studio.RIG_LAYER - 1))
		probe.reflection_mask = 1 << (Studio.CAR_LAYER - 1)
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		probe.max_distance = 60.0
		probe.mesh_lod_threshold = 0.0
		add_child(probe)

## Frames the car from `yaw_deg` (0 = straight ahead of the nose, 90 = right side) at eye height
## `height`, vertical fov `fov`, so its projected bounds fill `fill` of the frame width.
func _shot(bb: AABB, yaw_deg: float, height: float, fov: float, fill: float) -> Image:
	cam.fov = fov
	cam.h_offset = 0.0
	cam.v_offset = 0.0
	var a := deg_to_rad(yaw_deg)
	var dir := Vector3(sin(a), 0.0, -cos(a))
	var center := bb.get_center()
	var target := Vector3(center.x, bb.position.y + bb.size.y * 0.42, center.z)
	var dist := 7.0
	var r := Rect2()
	for it in range(5):
		var p := target + dir * dist
		p.y = height
		cam.look_at_from_position(p, target, Vector3.UP)
		r = _screen_rect(bb, fov)
		# r is in normalized device units (-1..1); fill = wanted width fraction.
		var k := maxf(r.size.x * 0.5 / fill, r.size.y * 0.5 / (fill * 0.72))
		dist *= k
	var p2 := target + dir * dist
	p2.y = height
	cam.look_at_from_position(p2, target, Vector3.UP)
	r = _screen_rect(bb, fov)
	# Center the car, slightly low in the frame (car photos breathe above the roof).
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / vs.y
	var tv := tan(deg_to_rad(fov) * 0.5)
	var d := (p2 - target).length()
	var c := r.get_center()
	cam.h_offset = c.x * tv * aspect * d
	cam.v_offset = (c.y + 0.06) * tv * d
	return await _grab()

## Projected bounds of `bb` in normalized device units (x right, y up, -1..1).
func _screen_rect(bb: AABB, fov: float) -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / vs.y
	var tv := tan(deg_to_rad(fov) * 0.5)
	var inv := cam.global_transform.affine_inverse()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for i in range(8):
		var q := inv * bb.get_endpoint(i)
		var z := maxf(-q.z, 0.05)
		var s := Vector2(q.x / z / (tv * aspect), q.y / z / tv)
		mn = mn.min(s)
		mx = mx.max(s)
	return Rect2(mn, mx - mn)
func _detail_wheel(view: CarView, bb: AABB) -> Image:
	var wheels: Array = view.visual.get_meta("wheels")
	var w: Node3D = wheels[1] # front right
	var c := w.global_position
	var r := view.wheel_value(1, 5)
	cam.fov = 30.0
	cam.h_offset = 0.0
	cam.v_offset = 0.0
	var dir := Vector3(0.55, 0.0, -0.45).normalized()
	var p := c + dir * (r * 7.0)
	p.y = c.y + r * 0.35
	cam.look_at_from_position(p, c + Vector3(0, r * 0.15, 0), Vector3.UP)
	return await _grab()

func _detail_lamp(view: CarView, bb: AABB, front: bool) -> Image:
	var target := _lamp_position(view, bb, front)
	cam.fov = 30.0
	cam.h_offset = 0.0
	cam.v_offset = 0.0
	var dir := Vector3(0.6, 0.12, -0.8 if front else 0.8).normalized()
	cam.look_at_from_position(target + dir * 2.3, target, Vector3.UP)
	return await _grab()

## Right-hand head/tail lamp: details-agent metas first, then node names, then the bounds.
func _lamp_position(view: CarView, bb: AABB, front: bool) -> Vector3:
	var meta_name := "headlights_local" if front else "taillights_local"
	var vis := view.visual
	if vis.has_meta(meta_name):
		var arr: Array = vis.get_meta(meta_name)
		var best := Vector3.ZERO
		var found := false
		for p in arr:
			var v: Vector3 = p
			if not found or v.x > best.x:
				best = v
				found = true
		if found:
			return vis.global_transform * best
	var prefix := "Headlight" if front else "Taillight"
	var hits := vis.find_children(prefix + "*", "Node3D", true, false)
	var best_n: Node3D = null
	for n in hits:
		if best_n == null or (n as Node3D).global_position.x > best_n.global_position.x:
			best_n = n
	if best_n:
		return best_n.global_position
	var c := bb.get_center()
	return Vector3(c.x + bb.size.x * 0.3, bb.position.y + bb.size.y * 0.45, bb.position.z if front else bb.end.z)

func _grab() -> Image:
	for f in range(4):
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _save_sheet(shots: Array, path: String) -> void:
	var w: int = shots[0].get_width()
	var h: int = shots[0].get_height()
	var sheet := Image.create(w * shots.size(), h, false, shots[0].get_format())
	for i in range(shots.size()):
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	sheet.resize(w * shots.size() / 2, h / 2, Image.INTERPOLATE_LANCZOS)
	sheet.save_png(path)
