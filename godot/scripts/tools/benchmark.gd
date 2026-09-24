extends Node3D
## M0 hardware benchmark: finds the loads this device sustains at 60 FPS so the game's budgets
## are set from measurements, not guesses. Uses the renderer's measured GPU time (works with
## vsync on) and ramps each test until GPU time crosses the 60 FPS budget.
## Args (after --): stages=draw,tris,fill,shader,cpu,thermal  thermal_seconds=300  out=<path>

const GPU_BUDGET_MS := 15.5 # leave ~1 ms for compositor/present
const SETTLE_FRAMES := 20
const SAMPLE_FRAMES := 45

var results := {}
var stages: PackedStringArray = ["draw", "tris", "fill", "shader", "cpu"]
var thermal_seconds := 300.0
var out_path := ""
var _vp_rid: RID
var _font: Font
var _status := "starting"
var _cam: Camera3D
var _holder: Node3D
var _label: Label

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv[0] == "stages":
			stages = kv[1].split(",")
		elif kv[0] == "thermal_seconds":
			thermal_seconds = float(kv[1])
		elif kv[0] == "out":
			out_path = kv[1]
	Perf.enabled = false # the governor must not fight the benchmark
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 0, 12)
	add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 18)
	layer.add_child(_label)
	results["device"] = {
		"model": OS.get_model_name(), "os": OS.get_name(), "version": OS.get_version(),
		"gpu": RenderingServer.get_video_adapter_name(), "api": RenderingServer.get_video_adapter_api_version(),
		"cpu": OS.get_processor_name(), "cores": OS.get_processor_count(),
		"resolution": get_viewport().get_visible_rect().size,
		"msaa": get_viewport().msaa_3d,
	}
	_run()

func _process(_d: float) -> void:
	_label.text = "BENCHMARK  %s\nGPU %.2f ms  CPU %.2f ms  FPS %d" % [_status, gpu_ms(), cpu_ms(), Engine.get_frames_per_second()]

func gpu_ms() -> float:
	return RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)

func cpu_ms() -> float:
	return RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu()

func _measure() -> Dictionary:
	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame
	var g := 0.0
	var c := 0.0
	var worst := 0.0
	for i in range(SAMPLE_FRAMES):
		await get_tree().process_frame
		var gm := gpu_ms()
		g += gm
		c += cpu_ms()
		worst = maxf(worst, gm)
	return {"gpu": g / SAMPLE_FRAMES, "cpu": c / SAMPLE_FRAMES, "worst": worst}

func _clear() -> void:
	if _holder:
		_holder.queue_free()
	_holder = Node3D.new()
	add_child(_holder)

func _run() -> void:
	for s in stages:
		match s:
			"draw": await _stage_draw_calls()
			"tris": await _stage_triangles()
			"fill": await _stage_fill()
			"shader": await _stage_shader()
			"cpu": await _stage_cpu()
			"thermal": await _stage_thermal()
	_status = "done"
	_save()

## Distinct materials defeat batching: each instance is a real draw call.
func _stage_draw_calls() -> void:
	_clear()
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.2, 0.2)
	var count := 0
	var step := 100
	var last_ok := 0
	var curve := []
	while count < 8000:
		for i in range(step):
			var mi := MeshInstance3D.new()
			mi.mesh = box
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(randf(), randf(), randf())
			mi.material_override = m
			var k := count + i
			mi.position = Vector3((k % 80) * 0.25 - 10, ((k / 80) % 60) * 0.25 - 7, -(k / 4800) * 2.0)
			_holder.add_child(mi)
		count += step
		_status = "draw calls: %d" % count
		var m := await _measure()
		curve.append([count, m.gpu, m.cpu])
		if maxf(m.gpu, m.cpu) > GPU_BUDGET_MS:
			break
		last_ok = count
		if count >= 1000:
			step = 250
	results["draw_calls_60fps"] = last_ok
	results["draw_calls_curve"] = curve

func _stage_triangles() -> void:
	_clear()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 64
	sphere.rings = 32
	var tris_per := 64 * 32 * 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = 4000
	mm.visible_instance_count = 0
	for i in range(4000):
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.3), Vector3((i % 40) * 0.5 - 10, ((i / 40) % 25) * 0.5 - 6, -(i / 1000) * 3.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.7, 0.75)
	mmi.material_override = mat
	_holder.add_child(mmi)
	var n := 0
	var last_ok := 0
	var curve := []
	while n < 4000:
		n += 50
		mm.visible_instance_count = n
		_status = "triangles: %.2f M" % (n * tris_per / 1e6)
		var m := await _measure()
		curve.append([n * tris_per, m.gpu])
		if m.gpu > GPU_BUDGET_MS:
			break
		last_ok = n * tris_per
	results["triangles_60fps"] = last_ok
	results["triangles_curve"] = curve

func _fullscreen_quad(mat: Material, z: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(40, 24)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position = Vector3(0, 0, z)
	return mi

func _stage_fill() -> void:
	_clear()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.3, 0.6, 0.04)
	mat.no_depth_test = true
	var layers := 0
	var last_ok := 0
	var curve := []
	while layers < 200:
		for i in range(2):
			_holder.add_child(_fullscreen_quad(mat, -layers * 0.01))
			layers += 1
		_status = "overdraw layers: %d" % layers
		var m := await _measure()
		curve.append([layers, m.gpu])
		if m.gpu > GPU_BUDGET_MS:
			break
		last_ok = layers
	results["fullscreen_overdraw_60fps"] = last_ok
	results["fill_curve"] = curve

func _stage_shader() -> void:
	_clear()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
uniform int iterations = 1;
void fragment() {
	vec2 p = UV * 8.0;
	float acc = 0.0;
	for (int i = 0; i < iterations; i++) {
		p = vec2(sin(p.x * 1.3 + p.y), cos(p.y * 1.7 - p.x)) * 1.1 + 0.1;
		acc += p.x * p.y;
	}
	ALBEDO = vec3(fract(acc * 0.01), 0.2, 0.4);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_holder.add_child(_fullscreen_quad(mat, 0.0))
	var it := 0
	var last_ok := 0
	var curve := []
	while it < 2000:
		it += 8 if it < 64 else 32
		mat.set_shader_parameter("iterations", it)
		_status = "fragment ALU iterations: %d" % it
		var m := await _measure()
		curve.append([it, m.gpu])
		if m.gpu > GPU_BUDGET_MS:
			break
		last_ok = it
	# Each iteration ~ 2 sin/cos + 6 mad at native res.
	results["fullscreen_shader_iterations_60fps"] = last_ok
	results["shader_curve"] = curve

func _stage_cpu() -> void:
	_clear()
	var out := {}
	var keys := NTSim.car_keys()
	for count in [12, 24, 48, 96]:
		var sim := NTSim.new()
		sim.running = false
		_holder.add_child(sim)
		var faces := PackedVector3Array()
		var s := PackedByteArray()
		var f := PackedByteArray()
		for gx in range(-8, 8):
			for gz in range(-8, 8):
				var a := Vector3(gx * 100, 0, gz * 100)
				faces.append_array([a, a + Vector3(0, 0, 100), a + Vector3(100, 0, 100), a, a + Vector3(100, 0, 100), a + Vector3(100, 0, 0)])
				s.append_array([0, 0])
				f.append_array([3, 3])
		sim.set_collision_chunk(1, faces, s, f)
		for i in range(count):
			var id := sim.add_car(keys[i % keys.size()], {}, false, i)
			sim.reset_car(id, Transform3D(Basis(), Vector3((i % 10) * 8.0 - 40, 0.8, (i / 10) * 12.0 - 60)), 15.0)
			sim.set_input(id, sin(i) * 0.4, 0.7, 0.0, 0.0, 0.0)
		var total := 0.0
		var samples := 240
		for k in range(samples):
			sim.step(1.0 / 120.0)
			total += sim.get_step_usec()
		var serial_total := 0.0
		sim.parallel = false
		for k in range(samples):
			sim.step(1.0 / 120.0)
			serial_total += sim.get_step_usec()
		out[str(count)] = {"parallel_us": total / samples, "serial_us": serial_total / samples}
		_status = "physics %d cars: %.0f us/tick (serial %.0f)" % [count, total / samples, serial_total / samples]
		sim.queue_free()
		await get_tree().process_frame
	results["physics_step_us"] = out

## Sustained load: 70% of the measured ceilings for N seconds, logging GPU time and thermals.
func _stage_thermal() -> void:
	_clear()
	var sphere := SphereMesh.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	var tri_budget: int = int(results.get("triangles_60fps", 1_000_000) * 0.7)
	var tris_per := 64 * 32 * 2
	mm.instance_count = maxi(1, tri_budget / tris_per)
	for i in range(mm.instance_count):
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.3), Vector3((i % 40) * 0.5 - 10, ((i / 40) % 25) * 0.5 - 6, -(i / 1000) * 3.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_holder.add_child(mmi)
	var log := []
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < thermal_seconds:
		var m := await _measure()
		var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
		log.append([elapsed, m.gpu, Engine.get_frames_per_second(), Perf.thermal, Perf.battery])
		_status = "thermal soak %.0f / %.0f s  gpu %.2f ms  thermal %.2f" % [elapsed, thermal_seconds, m.gpu, Perf.thermal]
	results["thermal_log"] = log

func _save() -> void:
	var path := out_path
	if path == "":
		DirAccess.make_dir_recursive_absolute("user://benchmarks")
		path = "user://benchmarks/bench_%d.json" % Time.get_unix_time_from_system()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t"))
	f.close()
	print("BENCHMARK_RESULT ", ProjectSettings.globalize_path(path))
	print(JSON.stringify(results))
	_status = "done -> " + path
	if OS.get_cmdline_user_args().has("quit"):
		get_tree().quit()
