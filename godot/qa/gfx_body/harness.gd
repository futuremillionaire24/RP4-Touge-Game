extends Node3D
## Body agent QA harness: dims dump, body build timing / triangle counts and multi-view renders.
## Usage:
##   godot --path . res://qa/gfx_body/harness.tscn -- mode=dump
##   godot --headless --path . res://qa/gfx_body/harness.tscn -- mode=perf
##   godot --path . --resolution 1334x750 res://qa/gfx_body/harness.tscn -- mode=render out=D:/.. cars=a,b [mat=clay|paint|uv2] [body_only=1] [views=...]

const BODY := preload("res://scripts/vehicle/car_body.gd")

var args := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var cars: PackedStringArray = PackedStringArray(CarData.keys())
	if args.has("cars"):
		cars = String(args.cars).split(",")
	var mode: String = args.get("mode", "render")
	var sim := NTSim.new()
	sim.running = false
	add_child(sim)
	var g := 50.0
	sim.set_collision_chunk(1, PackedVector3Array([Vector3(-g, 0, -g), Vector3(-g, 0, g), Vector3(g, 0, g), Vector3(-g, 0, -g), Vector3(g, 0, g), Vector3(g, 0, -g)]), PackedByteArray([0, 0]), PackedByteArray([3, 3]))
	if mode == "dump" or mode == "perf":
		for key in cars:
			var id := sim.add_car(key, {}, false, 1)
			var spec := sim.get_car_spec(id)
			sim.reset_car(id, Transform3D(Basis(), Vector3(0, spec.cg_height, 0)), 0.0)
			for i in range(240):
				sim.step(1.0 / 120.0)
			var wd := sim.get_wheel_data(id)
			var dims := {"hx": spec.half_extents.x, "hz": spec.half_extents.z, "cg": spec.cg_height, "wheels": CarBuilder.wheel_list(wd), "key": key}
			if mode == "dump":
				var ws := ""
				for w in dims.wheels:
					ws += " (%.3f %.3f %.3f r%.3f)" % [w.pos.x, w.pos.y, w.pos.z, w.radius]
				var tr: Transform3D = sim.get_transform(id)
				print("DIMS %s hx=%.3f hy=%.3f hz=%.3f cg=%.3f pose_y=%.3f%s" % [key, spec.half_extents.x, spec.half_extents.y, spec.half_extents.z, spec.cg_height, tr.origin.y, ws])
			else:
				_perf(key, dims)
			sim.set_frozen(id, true)
			sim.reset_car(id, Transform3D(Basis(), Vector3(0, -50, 0)), 0.0)
		get_tree().quit()
		return
	await _render(sim, cars)
	get_tree().quit()

func _tris(m: Mesh) -> int:
	var n := 0
	if m == null:
		return 0
	for s in range(m.get_surface_count()):
		var arr := m.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			n += idx.size() / 3
		else:
			n += arr[Mesh.ARRAY_VERTEX].size() / 3
	return n

func _perf(key: String, dims: Dictionary) -> void:
	var b: Dictionary = CarData.get_car(key).body
	BODY.clear_cache()
	var t0 := Time.get_ticks_usec()
	var body = BODY.build_body(b, dims)
	var t1 := Time.get_ticks_usec()
	var gh = BODY.build_greenhouse(b, dims)
	var t2 := Time.get_ticks_usec()
	var l1 = BODY.build_body_lod(b, dims, 1)
	var l2 = BODY.build_body_lod(b, dims, 2)
	var t3 := Time.get_ticks_usec()
	var t4 := Time.get_ticks_usec()
	BODY.build_body(b, dims)
	BODY.build_greenhouse(b, dims)
	var t5 := Time.get_ticks_usec()
	var names := []
	for s in range(body.get_surface_count()):
		names.append(body.surface_get_name(s))
	var gnames := []
	for s in range(gh.get_surface_count()):
		gnames.append(gh.surface_get_name(s))
	print("PERF %s body %.1f ms (%d tris, %d surf %s) greenhouse %.1f ms (%d tris, %d surf %s) lod1+2 %.1f ms (%d / %d tris) cached %.2f ms" % [key,
		(t1 - t0) / 1000.0, _tris(body), body.get_surface_count(), str(names), (t2 - t1) / 1000.0, _tris(gh), gh.get_surface_count(), str(gnames),
		(t3 - t2) / 1000.0, _tris(l1), _tris(l2), (t5 - t4) / 1000.0])

func _clay() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.72, 0.7)
	m.roughness = 0.45
	m.metallic_specular = 0.6
	return m

func _uv2_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded;
void fragment() {
	float seam = 1.0 - smoothstep(0.002, 0.006, UV2.x);
	ALBEDO = mix(vec3(UV2.y), vec3(1.0, 0.1, 0.1), seam);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func _render(sim: NTSim, cars: PackedStringArray) -> void:
	var out_dir: String = args.get("out", "D:/Android_RP4_Game/build/gfx/body/shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := EnvironmentRig.new()
	add_child(env)
	env.sun.rotation_degrees = Vector3(-50, -30, 0)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(200, 200)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.33, 0.35)
	fm.roughness = 0.35
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = fm
	add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.near = 0.05
	add_child(cam)
	var matmode: String = args.get("mat", "paint")
	var body_only: bool = args.get("body_only", "0") == "1"
	var views: PackedStringArray = String(args.get("views", "side,f34,r34,front,rear,top")).split(",")
	for key in cars:
		var id := sim.add_car(key, {}, false, 1)
		var spec := sim.get_car_spec(id)
		sim.reset_car(id, Transform3D(Basis(), Vector3(0, spec.cg_height, 0)), 0.0)
		for i in range(240):
			sim.step(1.0 / 120.0)
		var view := CarView.new()
		add_child(view)
		view.setup(sim, id, key, false)
		view.set_physics_process(false)
		view.global_transform = sim.get_transform(id)
		view.audio.player.stop()
		var vis: Node3D = view.visual
		if body_only:
			for c in vis.get_children():
				if c.name != "Body" and c.name != "Cabin" and not (c in vis.get_meta("wheels")):
					c.visible = false
		if matmode != "paint":
			var mm: Material = _clay() if matmode == "clay" else _uv2_mat()
			for c in vis.get_children():
				if c is MeshInstance3D and (c.name == "Body" or c.name == "Cabin"):
					for s in range(c.mesh.get_surface_count()):
						var nm: String = c.mesh.surface_get_name(s)
						if matmode == "uv2" or nm == "paint":
							c.set_surface_override_material(s, mm)
		var hz: float = spec.half_extents.z
		var shots := []
		for v in views:
			var d := hz * 2.6 + 1.5
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			match v:
				"side":
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					cam.size = hz * 2.0 + 0.5
					cam.global_position = Vector3(10, 0.62, 0)
					cam.look_at(Vector3(0, 0.62, 0), Vector3.UP)
				"front":
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					cam.size = 2.3 if key != "kaido_van" else 2.6
					cam.global_position = Vector3(0, 0.75, -10)
					cam.look_at(Vector3(0, 0.75, 0), Vector3.UP)
				"rear":
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					cam.size = 2.3 if key != "kaido_van" else 2.6
					cam.global_position = Vector3(0, 0.75, 10)
					cam.look_at(Vector3(0, 0.75, 0), Vector3.UP)
				"top":
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					cam.size = 2.6
					cam.global_position = Vector3(0, 10, 0.001)
					cam.look_at(Vector3(0, 0, 0), Vector3(-1, 0, 0))
				"f34":
					var a := deg_to_rad(38.0)
					cam.global_position = Vector3(sin(a) * d, 1.35, -cos(a) * d)
					cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
				"r34":
					var a2 := deg_to_rad(145.0)
					cam.global_position = Vector3(sin(a2) * d, 1.45, -cos(a2) * d)
					cam.look_at(Vector3(0, 0.55, 0), Vector3.UP)
				"low":
					var a3 := deg_to_rad(60.0)
					cam.global_position = Vector3(sin(a3) * d * 0.8, 0.45, -cos(a3) * d * 0.8)
					cam.look_at(Vector3(0, 0.45, 0), Vector3.UP)
				"arch":
					cam.global_position = Vector3(2.6, 0.55, -1.2)
					cam.look_at(Vector3(0.6, 0.35, dims_front_z(view)), Vector3.UP)
			for f in range(4):
				await RenderingServer.frame_post_draw
			shots.append(get_viewport().get_texture().get_image())
		var w: int = shots[0].get_width()
		var h: int = shots[0].get_height()
		var cols := 3 if shots.size() > 2 else shots.size()
		var rows := int(ceil(shots.size() / float(cols)))
		var sheet := Image.create(w * cols, h * rows, false, shots[0].get_format())
		for i in range(shots.size()):
			sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(w * (i % cols), h * (i / cols)))
		var scale := float(args.get("scale", "0.5"))
		sheet.resize(int(w * cols * scale), int(h * rows * scale), Image.INTERPOLATE_LANCZOS)
		var suffix: String = args.get("tag", "")
		sheet.save_png(out_dir.path_join("%s%s.png" % [key, suffix]))
		print("RENDER ", key)
		view.queue_free()
		sim.set_frozen(id, true)
		sim.reset_car(id, Transform3D(Basis(), Vector3(0, -50, 0)), 0.0)

func dims_front_z(view: CarView) -> float:
	var wd := view.wheel_data
	return wd[2]
