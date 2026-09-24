extends Node3D
## Materials QA harness (materials agent). Close-up renders of the paint finishes, glass and the
## shared library, plus real-car close-ups.
## Usage: godot --path . --resolution 1334x750 res://qa/gfx_materials/harness.tscn -- mode=<spheres|panel|library|car>
##   out=<dir> [car=<key>] [finish=<name>] [wet=0..1] [rain=0..1] [night=1] [sun=<elev>,<azim>] [tag=<name>]

var args := {}
var out_dir := "D:/Android_RP4_Game/build/gfx/materials/qa"
var cam: Camera3D
var env_rig: EnvironmentRig

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out_dir = args.get("out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	RenderingServer.global_shader_parameter_set("nt_wetness", float(args.get("wet", "0")))
	RenderingServer.global_shader_parameter_set("nt_rain", float(args.get("rain", "0")))
	RenderingServer.global_shader_parameter_set("nt_night", 1.0 if args.has("night") else 0.0)
	env_rig = EnvironmentRig.new()
	add_child(env_rig)
	var sun: Array = str(args.get("sun", "35,-30")).split(",")
	env_rig.sun.rotation_degrees = Vector3(-float(sun[0]), float(sun[1]), 0)
	if args.has("night"):
		env_rig.sun.light_energy = 0.03
		env_rig.sky_mat.sky_top_color = Color(0.01, 0.012, 0.03)
		env_rig.sky_mat.sky_horizon_color = Color(0.05, 0.04, 0.07)
		env_rig.sky_mat.ground_horizon_color = Color(0.03, 0.03, 0.04)
		env_rig.sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.01)
		env_rig.env.ambient_light_energy = 0.4
		for p in [Vector3(-3, 4.5, -2), Vector3(4, 4.0, 3)]:
			var o := OmniLight3D.new()
			o.position = p
			o.light_color = Color(1.0, 0.78, 0.5) if p.x < 0 else Color(0.7, 0.85, 1.0)
			o.light_energy = 6.0
			o.omni_range = 14.0
			o.shadow_enabled = true
			add_child(o)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(200, 200)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.33, 0.35)
	fm.roughness = 0.35 if float(args.get("wet", "0")) < 0.5 else 0.08
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = fm
	add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	match args.get("mode", "spheres"):
		"spheres": await _spheres()
		"panel": await _panel()
		"library": await _library()
		"car": await _car()
	get_tree().quit()

func _shot(name: String, pos: Vector3, target: Vector3, fov := 40.0) -> Image:
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	for f in range(5):
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var tag: String = args.get("tag", "")
	img.save_png(out_dir.path_join("%s%s.png" % [name, ("_" + tag) if tag != "" else ""]))
	return img

func _sphere(pos: Vector3, mat: Material, r := 0.45) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 64
	s.rings = 32
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

func _spheres() -> void:
	var finishes := ["gloss", "metallic", "pearl", "matte", "satin", "chrome", "candy"]
	var cols := [Color(0.75, 0.04, 0.06), Color(0.12, 0.2, 0.55), Color(0.08, 0.08, 0.09), Color(0.2, 0.22, 0.24),
		Color(0.1, 0.85, 0.55), Color(0.85, 0.86, 0.88), Color(0.05, 0.05, 0.06)]
	for i in range(finishes.size()):
		var m := CarMaterials.paint_material("senko" if finishes[i] == "pearl" else ("kurogane_hyper" if finishes[i] == "candy" else "sylph_s2"), cols[i], finishes[i])
		_sphere(Vector3((i - 3) * 1.05, 0.6, 0), m)
	# Reference: StandardMaterial3D equivalent of the gloss sphere (lighting calibration).
	var ref := StandardMaterial3D.new()
	ref.albedo_color = cols[0]
	ref.roughness = 0.25
	ref.clearcoat_enabled = true
	ref.clearcoat = 1.0
	ref.clearcoat_roughness = 0.08
	_sphere(Vector3(-3.15, 0.6, 1.2), ref)
	var m2 := CarMaterials.paint_material("sylph_s2", cols[0], "gloss")
	_sphere(Vector3(-2.1, 0.6, 1.2), m2)
	await _shot("spheres", Vector3(0, 1.4, 6.2), Vector3(0, 0.55, 0.3))
	await _shot("spheres_close", Vector3(-1.1, 0.9, 1.5), Vector3(-2.1, 0.62, 0.0))

## Curved car-like panel with synthetic UV2 (panel seams + AO) for gap/flake/bead close-ups.
func _panel() -> void:
	var finish: String = args.get("finish", "metallic")
	var key: String = args.get("car", "sylph_s2")
	var m := CarMaterials.paint_material(key, null, finish)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 120
	var nv := 60
	var w := 3.0
	var h := 1.2
	var pts := []
	for j in range(nv + 1):
		var row := []
		for i in range(nu + 1):
			var u := float(i) / nu
			var v := float(j) / nv
			var x := (u - 0.5) * w
			var ang := (v - 0.5) * 1.6
			var y := sin(ang) * 0.9 + 0.8
			var z := -cos(ang) * 0.9 + 0.2 * sin(u * PI)
			row.append(Vector3(x, y, z))
		pts.append(row)
	for j in range(nv):
		for i in range(nu):
			var q := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			for o in [0, 2, 1, 0, 3, 2]:
				var ii: int = q[o][0]
				var jj: int = q[o][1]
				var p: Vector3 = pts[jj][ii]
				var x := p.x
				var seam := minf(absf(x - 0.4), absf(p.y - 1.25) if x < 0.4 else 9.0)
				var ao := clampf(0.55 + 0.45 * smoothstep(0.0, 0.3, p.y - 0.1), 0.02, 1.0)
				var nrm := Vector3(0, sin(float(jj) / nv * 1.6 - 0.8), -cos(float(jj) / nv * 1.6 - 0.8)).normalized()
				st.set_normal(nrm)
				st.set_uv(Vector2(float(ii) / nu, float(jj) / nv))
				st.set_uv2(Vector2(minf(seam, 1.0), ao))
				st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	add_child(mi)
	await _shot("panel_far", Vector3(1.2, 1.6, -4.5), Vector3(0.2, 0.9, -0.6))
	await _shot("panel_mid", Vector3(0.9, 1.3, -2.2), Vector3(0.3, 0.9, -0.5))
	await _shot("panel_close", Vector3(0.55, 1.2, -1.25), Vector3(0.4, 1.1, -0.6))

func _library() -> void:
	var names := ["glass", "glass_tinted", "trim_black", "trim_gloss", "rubber", "chrome", "brushed_alloy", "carbon",
		"underbody", "grille_mesh", "plate", "tire", "rim", "rim_dark", "trim", "caliper", "disc", "paint2"]
	var backdrop := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(12, 3, 0.1)
	backdrop.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.8, 0.5, 0.2)
	backdrop.material_override = bmat
	backdrop.position = Vector3(0, 1.5, -1.3)
	add_child(backdrop)
	for i in range(names.size()):
		var col := i % 9
		var row := i / 9
		var pos := Vector3((col - 4) * 1.0, 1.9 - row * 1.05, 0)
		var box := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.42
		sm.height = 0.84
		sm.radial_segments = 48
		sm.rings = 24
		box.mesh = sm
		box.material_override = CarMaterials.shared(names[i])
		box.position = pos
		add_child(box)
		var l := Label3D.new()
		l.text = names[i]
		l.font_size = 28
		l.position = pos + Vector3(0, -0.5, 0.3)
		add_child(l)
	await _shot("library", Vector3(0, 1.5, 7.0), Vector3(0, 1.4, 0))
	await _shot("library_close", Vector3(-2.3, 2.0, 2.0), Vector3(-2.5, 1.7, 0))
	await _shot("library_close2", Vector3(2.0, 1.2, 2.0), Vector3(1.8, 1.0, 0))

func _car() -> void:
	var key: String = args.get("car", "sylph_s2")
	var sim := NTSim.new()
	sim.running = false
	add_child(sim)
	var g := 50.0
	sim.set_collision_chunk(1, PackedVector3Array([Vector3(-g, 0, -g), Vector3(-g, 0, g), Vector3(g, 0, g), Vector3(-g, 0, -g), Vector3(g, 0, g), Vector3(g, 0, -g)]), PackedByteArray([0, 0]), PackedByteArray([3, 3]))
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
	if args.has("finish"):
		var m: ShaderMaterial = view._paint
		var cd: Dictionary = CarData.get_car(key)
		var f: Dictionary = CarData.FINISHES[args.finish]
		for k in [["metallic", "metallic"], ["roughness", "roughness"], ["flake_amount", "flake"], ["pearl", "pearl"], ["clearcoat_amount", "coat"], ["clearcoat_gloss", "gloss"], ["candy", "candy"]]:
			m.set_shader_parameter(k[0], f[k[1]])
	if args.has("dirt"):
		view._paint.set_shader_parameter("dirt", float(args.dirt))
		view._paint.set_shader_parameter("scratches", float(args.dirt))
	var hz: float = spec.half_extents.z
	await _shot("car_%s_front34" % key, Vector3(2.6, 1.25, -hz - 2.2), Vector3(0, 0.35, -hz * 0.4))
	await _shot("car_%s_side" % key, Vector3(3.4, 0.9, 0.3), Vector3(0, 0.3, 0.1))
	await _shot("car_%s_glass" % key, Vector3(1.6, 1.7, -hz - 1.4), Vector3(0, 0.6, -0.3))
	await _shot("car_%s_rear34" % key, Vector3(-2.8, 1.3, hz + 2.4), Vector3(0, 0.35, hz * 0.4))
	await _shot("car_%s_hood" % key, Vector3(0.9, 1.05, -hz - 0.6), Vector3(0.1, 0.35, -hz * 0.5), 35.0)
