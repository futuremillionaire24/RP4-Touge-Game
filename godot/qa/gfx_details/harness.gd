extends Node3D
## Details-agent harness: studio close-ups (day / night / brake) of lights, grilles, plates,
## mirrors, interior; per-car triangle / draw-call / build-time stats.
## godot --path . res://qa/gfx_details/harness.tscn -- out=D:/dir cars=a,b shots=f34,r34,front,rear night=1 stats=1

var out_dir := "D:/Android_RP4_Game/build/gfx/details"
var cars: PackedStringArray = []
var shots: PackedStringArray = ["f34", "r34", "front", "rear"]
var args := {}
var env: EnvironmentRig
var cam: Camera3D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out_dir = args.get("out", out_dir)
	if args.has("cars"):
		cars = args.cars.split(",")
	else:
		cars = PackedStringArray(CarData.keys())
	if args.has("shots"):
		shots = args.shots.split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	env = EnvironmentRig.new()
	add_child(env)
	env.sun.rotation_degrees = Vector3(-42, -35, 0)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(200, 200)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.31, 0.33)
	fm.roughness = 0.45
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = fm
	add_child(floor_mi)
	var sim := NTSim.new()
	sim.running = false
	add_child(sim)
	var g := 50.0
	sim.set_collision_chunk(1, PackedVector3Array([Vector3(-g, 0, -g), Vector3(-g, 0, g), Vector3(g, 0, g), Vector3(-g, 0, -g), Vector3(g, 0, g), Vector3(g, 0, -g)]), PackedByteArray([0, 0]), PackedByteArray([3, 3]))
	cam = Camera3D.new()
	cam.fov = 38
	cam.near = 0.03
	add_child(cam)
	cam.current = true
	var stats_lines := []
	for key in cars:
		var id := sim.add_car(key, {}, false, 1)
		var spec := sim.get_car_spec(id)
		sim.reset_car(id, Transform3D(Basis(), Vector3(0, spec.cg_height, 0)), 0.0)
		for i in range(240):
			sim.step(1.0 / 120.0)
		# Build timing: two cold/warm builds of the rig outside the view.
		var wd := sim.get_wheel_data(id)
		var t0 := Time.get_ticks_usec()
		var probe := CarBuilder.build(key, spec, wd)
		var t1 := Time.get_ticks_usec()
		var det_us: int = CarDetails.last_build_us
		probe.free()
		var t2 := Time.get_ticks_usec()
		var probe2 := CarBuilder.build(key, spec, wd)
		var t3 := Time.get_ticks_usec()
		var det_us2: int = CarDetails.last_build_us
		probe2.free()
		var view := CarView.new()
		add_child(view)
		view.setup(sim, id, key, true)
		view.set_physics_process(false)
		view.global_transform = sim.get_transform(id)
		view.audio.player.stop()
		var he: Vector3 = spec.half_extents
		if args.has("stats"):
			var st := _stats(view.visual)
			var line := "%s hx=%.3f hz=%.3f cg=%.3f | build cold %.1f ms (details %.1f) warm %.1f ms (details %.1f) | %s" % [key, he.x, he.z, spec.cg_height, (t1 - t0) / 1000.0, det_us / 1000.0, (t3 - t2) / 1000.0, det_us2 / 1000.0, st]
			print("STATS ", line)
			stats_lines.append(line)
		if args.has("dump"):
			var car := CarData.get_car(key)
			print("DUMP ", key, " he=", he, " cg=", spec.cg_height, " wheels=", CarBuilder.wheel_list(wd).map(func(w): return [w.pos, w.radius]), " body=", car.body)
		var modes := ["day"]
		if args.get("night", "0") == "1":
			modes.append("night")
		if args.get("night", "0") == "only":
			modes = ["night"]
		for mode in modes:
			_set_mode(mode, view)
			for s in shots:
				_place(s, he, spec.cg_height)
				for f in range(6):
					CarDetails.set_light_state(view.visual, mode == "night" and s in ["r34", "rear", "rearlow"], mode == "night")
					await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				if args.get("half", "0") == "1":
					img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
				img.save_png(out_dir.path_join("%s_%s_%s.png" % [key, mode, s]))
		print("DONE ", key)
		view.queue_free()
		sim.set_frozen(id, true)
		sim.reset_car(id, Transform3D(Basis(), Vector3(0, -50, 0)), 0.0)
		await get_tree().process_frame
	if not stats_lines.is_empty():
		var f := FileAccess.open(out_dir.path_join("stats.txt"), FileAccess.WRITE)
		for l in stats_lines:
			f.store_line(l)
		f.close()
	get_tree().quit()

func _set_mode(mode: String, view: CarView) -> void:
	if mode == "night":
		env.sun.visible = false
		env.sky_mat.sky_top_color = Color(0.01, 0.012, 0.03)
		env.sky_mat.sky_horizon_color = Color(0.04, 0.04, 0.07)
		env.sky_mat.ground_horizon_color = Color(0.02, 0.02, 0.03)
		env.sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.01)
		env.env.ambient_light_energy = 0.25
		view.set_lights(true)
		# Popup animation needs a few ticks of wall time.
		for i in range(40):
			CarDetails.set_light_state(view.visual, false, true)
			await get_tree().process_frame
	else:
		env.sun.visible = true
		env.sky_mat.sky_top_color = Color(0.24, 0.42, 0.72)
		env.sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.86)
		env.sky_mat.ground_horizon_color = Color(0.5, 0.52, 0.55)
		env.sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.22)
		env.env.ambient_light_energy = 0.8
		view.set_lights(false)
		CarDetails.set_light_state(view.visual, false, false)

func _place(s: String, he: Vector3, cg: float) -> void:
	var hx := he.x
	var hz := he.z
	var tgt := Vector3.ZERO
	var pos := Vector3.ZERO
	cam.fov = 38
	match s:
		"f34":
			pos = Vector3(hx + 1.9, 1.25, -hz - 2.3)
			tgt = Vector3(hx * 0.2, 0.55, -hz + 0.5)
		"f34l":
			pos = Vector3(-hx - 1.9, 1.25, -hz - 2.3)
			tgt = Vector3(-hx * 0.2, 0.55, -hz + 0.5)
		"r34":
			pos = Vector3(-hx - 1.9, 1.3, hz + 2.3)
			tgt = Vector3(-hx * 0.2, 0.6, hz - 0.5)
		"front":
			pos = Vector3(0, 0.95, -hz - 3.4)
			tgt = Vector3(0, 0.55, 0)
		"frontlow":
			pos = Vector3(0.6, 0.5, -hz - 1.6)
			tgt = Vector3(0.0, 0.45, -hz)
		"rear":
			pos = Vector3(0, 1.0, hz + 3.4)
			tgt = Vector3(0, 0.6, 0)
		"rearlow":
			pos = Vector3(-0.5, 0.45, hz + 1.5)
			tgt = Vector3(0.0, 0.4, hz)
		"side":
			cam.fov = 40
			pos = Vector3(hx + 5.5, 1.1, 0)
			tgt = Vector3(0, 0.6, 0)
		"int":
			cam.fov = 55
			pos = Vector3(hx + 0.9, 1.45, -0.1)
			tgt = Vector3(0, 0.75, -0.2)
		"intl":
			cam.fov = 55
			pos = Vector3(-hx - 0.9, 1.45, 0.1)
			tgt = Vector3(0, 0.75, -0.3)
		"intf":
			cam.fov = 50
			pos = Vector3(0.0, 1.6, -hz - 1.2)
			tgt = Vector3(0.1, 0.8, 0.0)
		"top":
			cam.fov = 40
			pos = Vector3(hx + 2.8, 3.2, -hz - 1.2)
			tgt = Vector3(0, 0.6, -hz * 0.3)
		"mirror":
			cam.fov = 35
			pos = Vector3(hx + 1.3, 1.35, -0.9)
			tgt = Vector3(hx, 0.95, -0.2)
		"hl":
			cam.fov = 30
			pos = Vector3(hx + 0.5, 0.95, -hz - 1.3)
			tgt = Vector3(hx * 0.6, 0.6, -hz)
		"tl":
			cam.fov = 30
			pos = Vector3(-hx - 0.5, 1.0, hz + 1.3)
			tgt = Vector3(-hx * 0.6, 0.7, hz)
		"wing":
			cam.fov = 40
			pos = Vector3(hx + 2.0, 1.9, hz + 1.8)
			tgt = Vector3(0, 0.95, hz - 0.4)
	cam.global_position = pos
	cam.look_at(tgt, Vector3.UP)

func _stats(root: Node) -> String:
	var groups := {}
	_walk(root, groups, "")
	var parts := []
	var tt := 0
	var dd := 0
	for k in groups:
		parts.append("%s %d tri/%d dc" % [k, groups[k].x, groups[k].y])
		tt += groups[k].x
		dd += groups[k].y
	return "TOTAL %d tri %d dc | " % [tt, dd] + ", ".join(parts)

func _walk(n: Node, groups: Dictionary, top: String) -> void:
	var grp := top
	if n.get_parent() != null and n.get_parent().name == "CarVisual":
		grp = String(n.name)
	if n is MeshInstance3D and n.mesh != null and n.visible:
		var tris := 0
		var m: Mesh = n.mesh
		for s in range(m.get_surface_count()):
			var arr := m.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx != null and idx.size() > 0:
				tris += idx.size() / 3
			else:
				tris += arr[Mesh.ARRAY_VERTEX].size() / 3
		var key := grp.rstrip("0123456789")
		if not groups.has(key):
			groups[key] = Vector2i.ZERO
		var mi := n as MeshInstance3D
		var tag := "" if mi.visibility_range_end == 0.0 else "(<%dm)" % int(mi.visibility_range_end)
		groups[key] += Vector2i(tris, m.get_surface_count())
		if tag != "":
			var k2: String = key + tag
			if not groups.has(k2):
				groups[k2] = Vector2i.ZERO
			groups[k2] += Vector2i(0, 0)
	for c in n.get_children():
		_walk(c, groups, grp)
