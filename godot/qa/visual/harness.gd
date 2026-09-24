extends Node
## QA visual harness (tester "visual"). Loads freeroam as a child, then either dumps world
## metadata (mode=dump) or runs a shot plan (plan=<json>) teleporting the frozen player car
## to road samples, setting time/weather/season and taking screenshots + perf stats.

var fr: Node
var args := {}
var out_dir := "D:/Android_RP4_Game/build/qa/visual/shots"
var log_lines := []
var shotcam: Camera3D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out_dir = args.get("out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	fr = load("res://scenes/freeroam.tscn").instantiate()
	add_child(fr)
	var t0 := Time.get_ticks_msec()
	while fr._state != "playing":
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 240000:
			print("QA TIMEOUT loading")
			get_tree().quit()
			return
	print("QA loaded in %d ms" % (Time.get_ticks_msec() - t0))
	shotcam = Camera3D.new()
	shotcam.far = 3500.0
	shotcam.near = 0.1
	add_child(shotcam)
	fr.sky.weather_lock = true
	fr.sky.time_scale = 0.0
	if args.get("mode", "") == "chunkbench":
		_chunkbench()
		get_tree().quit()
		return
	if args.get("mode", "") == "dump":
		_dump()
		get_tree().quit()
		return
	if args.has("plan"):
		await _run_plan(args.plan)
	if args.has("drive"):
		await _run_drive(float(args.get("drive", "60")))
	var f := FileAccess.open(out_dir.path_join("perf_log.txt"), FileAccess.WRITE)
	for l in log_lines:
		f.store_line(l)
	f.close()
	get_tree().quit()

func _dump() -> void:
	var w: NTWorld = fr.world
	var d := {"pois": [], "roads": [], "bounds": str(w.bounds()), "chunks": [w.chunks_x(), w.chunks_z(), w.chunk_size()]}
	for p in w.pois():
		d.pois.append({"id": p.id, "type": p.type, "pos": [p.position.x, p.position.y, p.position.z], "road": p.road, "data": p.data, "district": w.district_name(w.district_at(p.position.x, p.position.z))})
	for n in w.road_names():
		var rs := w.road_samples(n)
		var types: PackedByteArray = rs.types
		var nb := 0
		var nt := 0
		for t in types:
			if t == 1: nb += 1
			elif t == 2: nt += 1
		var c: PackedVector3Array = rs.centers
		var mid: Vector3 = c[c.size() / 2]
		d.roads.append({"name": n, "kind": rs.kind, "district": w.district_name(rs.district), "len": rs.length, "n": c.size(), "bridge": nb, "tunnel": nt, "mid": [mid.x, mid.y, mid.z], "speed": rs.speed_limit})
		# Runs of sample types (0 ground, 1 bridge, 2 tunnel) as fractions, for shot planning.
		var runs := []
		var start := 0
		for i in range(1, types.size() + 1):
			if i == types.size() or types[i] != types[start]:
				if types[start] != 0:
					var hmin := INF
					var hmax := -INF
					for k in range(start, i):
						var th := w.height_at(c[k].x, c[k].z)
						hmin = minf(hmin, c[k].y - th)
						hmax = maxf(hmax, c[k].y - th)
					runs.append("%s %.3f-%.3f (above terrain %.0f..%.0f m)" % ["bridge" if types[start] == 1 else "tunnel", float(start) / types.size(), float(i) / types.size(), hmin, hmax])
				start = i
		if not runs.is_empty():
			print("QA RUNS ", n, ": ", ", ".join(runs))
	var f := FileAccess.open(out_dir.path_join("world_dump.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	var img: Image = w.minimap(1024)
	img.save_png(out_dir.path_join("minimap.png"))
	print("QA dump done")

## Times the main-thread part of chunk streaming (WorldStreamer._integrate equivalent) per LOD
## at representative locations.
func _chunkbench() -> void:
	var w: NTWorld = fr.world
	var spots := {"city": Vector3(0, 0, -82), "touge_forest": Vector3(-3335, 0, 724), "rural": Vector3(-1905, 0, -2218), "coast": Vector3(833, 0, 2070), "docks": Vector3(2525, 0, 550)}
	for name in spots.keys():
		var c: Vector2i = w.chunk_of(spots[name])
		for lod in range(4):
			var t0 := Time.get_ticks_usec()
			var d := w.build_chunk(c.x, c.y, lod, lod == 0, lod <= 2, [1.0, 0.7, 0.35, 0.0][lod])
			var t1 := Time.get_ticks_usec()
			var mesh: ArrayMesh = NTWorld.make_mesh(d)
			var t2 := Time.get_ticks_usec()
			var n_inst := 0
			var props: Dictionary = d.get("props", {})
			var holder := Node3D.new()
			for t in props.keys():
				n_inst += props[t].size() / 8
				holder.add_child(PropLibrary.multimesh_instance(int(t), props[t]))
			var t3 := Time.get_ticks_usec()
			var verts := 0
			for s in range(mesh.get_surface_count()):
				verts += mesh.surface_get_array_len(s)
			var col_ms := 0.0
			if d.has("collision_faces"):
				var tc := Time.get_ticks_usec()
				fr.sim.set_collision_chunk(99999, d.collision_faces, d.collision_surfaces, d.collision_flags)
				col_ms = (Time.get_ticks_usec() - tc) / 1000.0
				fr.sim.remove_collision_chunk(99999)
			var line := "chunkbench %s lod%d: build %.1f ms (worker) mesh %.1f ms | props %d inst -> multimesh %.1f ms (MAIN THREAD) | collision upload %.1f ms (MAIN) | verts %d lights %d" % [name, lod, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, n_inst, (t3 - t2) / 1000.0, col_ms, verts, d.lights.size() / 5]
			print("QA ", line)
			log_lines.append(line)
			holder.free()
	var f := FileAccess.open(out_dir.path_join("chunkbench.txt"), FileAccess.WRITE)
	for l in log_lines:
		f.store_line(l)
	f.close()

func _teleport(road: String, frac: float, lateral := 0.0) -> Transform3D:
	var w: NTWorld = fr.world
	var rs := w.road_samples(road)
	if rs.is_empty():
		print("QA no road ", road)
		return Transform3D()
	var c: PackedVector3Array = rs.centers
	var tg: PackedVector3Array = rs.tangents
	var i := clampi(int(frac * (c.size() - 1)), 0, c.size() - 1)
	var dir: Vector3 = tg[i]
	var side := dir.cross(Vector3.UP).normalized()
	var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), c[i] + side * lateral + Vector3(0, 0.9, 0))
	var id: int = fr.player.car_id
	fr.sim.set_frozen(id, false)
	fr.sim.reset_car(id, xf, 0.0)
	fr.sim.set_frozen(id, true)
	fr.camera.snap()
	return xf

func _wait_stream(max_s := 25.0) -> void:
	var t := 0.0
	var calm := 0.0
	while t < max_s:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		if fr.streamer.pending_count() == 0:
			calm += dt
			if calm > 1.5:
				break
		else:
			calm = 0.0

func _set_cond(s: Dictionary) -> void:
	var sky: SkyWeather = fr.sky
	sky.time_of_day = float(s.get("time", 12.0))
	sky.season = float(s.get("season", 0.0))
	sky.set_weather(int(s.get("weather", 0)), true)
	sky.snow_cover = float(s.get("snow", 0.0))
	sky.wetness = float(s.get("wet", sky.wetness))

func _measure(frames := 60) -> Dictionary:
	var vp := get_viewport().get_viewport_rid()
	var cpu := 0.0
	var gpu := 0.0
	var fms := 0.0
	var worst := 0.0
	for i in range(frames):
		await get_tree().process_frame
		var dt := get_process_delta_time() * 1000.0
		fms += dt
		worst = maxf(worst, dt)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	return {
		"frame_ms": fms / frames, "worst_ms": worst, "rs_cpu_ms": cpu / frames, "gpu_ms": gpu / frames,
		"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objs": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"vmem_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		"scale": get_viewport().scaling_3d_scale, "chunks": fr.streamer.loaded_count(), "traffic": fr.sim.traffic_active_count(),
		"sim_us": fr.sim.get_step_usec(),
	}

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))

func _place_cam(mode: String, xf: Transform3D) -> void:
	var fwd := -xf.basis.z
	var side := xf.basis.x
	var o := xf.origin
	match mode:
		"high":
			shotcam.fov = 60
			shotcam.global_position = o - fwd * 30.0 + Vector3(0, 28, 0)
			shotcam.look_at(o + fwd * 60.0, Vector3.UP)
		"vista":
			shotcam.fov = 55
			shotcam.global_position = o - fwd * 80.0 + side * 40.0 + Vector3(0, 90, 0)
			shotcam.look_at(o + fwd * 200.0, Vector3.UP)
		"side":
			shotcam.fov = 50
			shotcam.global_position = o + side * 7.0 + Vector3(0, 1.2, 0) + fwd * 1.0
			shotcam.look_at(o + Vector3(0, 0.4, 0), Vector3.UP)
		"low":
			shotcam.fov = 70
			shotcam.global_position = o + side * 5.5 + Vector3(0, 1.4, 0) - fwd * 2.0
			shotcam.look_at(o + fwd * 50.0 + Vector3(0, 1.5, 0), Vector3.UP)
		"under":
			var p := o + side * 30.0 - fwd * 20.0
			p.y = fr.world.height_at(p.x, p.z) + 1.7
			shotcam.fov = 65
			shotcam.global_position = p
			shotcam.look_at(o + fwd * 10.0, Vector3.UP)
		"back":
			shotcam.fov = 68
			shotcam.global_position = o + Vector3(0, 2.0, 0) - fwd * 1.0
			shotcam.look_at(o - fwd * 50.0 + Vector3(0, 1.5, 0), Vector3.UP)
	shotcam.current = true

func _run_plan(path: String) -> void:
	var plan = JSON.parse_string(FileAccess.get_file_as_string(path))
	for loc in plan:
		var xf := _teleport(loc.road, float(loc.get("frac", 0.5)), float(loc.get("lat", 0.0)))
		await _wait_stream()
		for cond in loc.conds:
			_set_cond(cond)
			for cam in loc.get("cams", ["chase"]):
				if cam == "chase":
					fr.camera.current = true
					fr.hud.get_parent().visible = true
				elif cam == "custom":
					var cp: Array = loc.cam_pos
					var ct: Array = loc.cam_target
					shotcam.fov = float(loc.get("fov", 55.0))
					shotcam.global_position = Vector3(cp[0], cp[1], cp[2])
					shotcam.look_at(Vector3(ct[0], ct[1], ct[2]), Vector3.UP)
					shotcam.current = true
				else:
					_place_cam(cam, xf)
					fr.hud.get_parent().visible = cam == "chase"
				# Let weather/particles/camera settle.
				for i in range(40):
					await get_tree().process_frame
				var m := await _measure(45)
				var name := "%s_%s_%s" % [loc.name, cond.get("tag", "c"), cam]
				await _shot(name)
				var line := "%s road=%s frac=%s pos=%s | frame %.1f ms worst %.1f | rs_cpu %.2f gpu %.2f | draws %d prims %d objs %d vmem %.0fMB | scale %.2f chunks %d traffic %d sim_us %d" % [name, loc.road, loc.get("frac", 0.5), xf.origin.snappedf(0.1), m.frame_ms, m.worst_ms, m.rs_cpu_ms, m.gpu_ms, m.draws, m.prims, m.objs, m.vmem_mb, m.scale, m.chunks, m.traffic, m.sim_us]
				print("QA ", line)
				log_lines.append(line)
		fr.camera.current = true
		fr.hud.get_parent().visible = true

## Let the AI drive the player car along a road and screenshot every few seconds (pop-in check).
func _run_drive(seconds: float) -> void:
	var road: String = args.get("road", "")
	var xf := _teleport(road, float(args.get("frac", "0.1")))
	await _wait_stream()
	_set_cond({"time": float(args.get("time", "12")), "weather": int(args.get("weather", "0")), "season": float(args.get("season", "0"))})
	var id: int = fr.player.car_id
	var rs: Dictionary = fr.world.road_samples(road)
	fr.sim.set_racing_line(rs.centers, rs.ups, rs.width_left, rs.width_right, rs.closed)
	fr.sim.set_frozen(id, false)
	fr.sim.set_ai(id, true)
	fr.sim.set_ai_difficulty(id, 5)
	fr.driver.enabled = false
	fr.camera.current = true
	var t := 0.0
	var k := 0
	var every := float(args.get("every", "3"))
	var next := every
	var worst := 0.0
	var acc := 0.0
	var n := 0
	var hitches := 0
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		acc += dt
		n += 1
		worst = maxf(worst, dt * 1000.0)
		if dt > 0.05:
			hitches += 1
		if t >= next:
			next += every
			var tel: Dictionary = fr.player.telemetry
			var line := "drive_%s_%02d t=%.1f pos=%s speed=%.0fkmh avg %.1fms worst %.1fms hitches>50ms %d pending %d chunks %d dist=%s" % [args.get("tag", "d"), k, t, fr.player.global_position.snappedf(0.1), float(tel.get("speed", 0.0)) * 3.6, acc * 1000.0 / n, worst, hitches, fr.streamer.pending_count(), fr.streamer.loaded_count(), fr.world.district_name(fr.world.district_at(fr.player.global_position.x, fr.player.global_position.z))]
			print("QA ", line)
			log_lines.append(line)
			await _shot("drive_%s_%02d" % [args.get("tag", "d"), k])
			k += 1
			acc = 0.0
			n = 0
			worst = 0.0
			hitches = 0
