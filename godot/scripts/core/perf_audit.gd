extends Node
## Performance audit (scene `perf_audit`): loads free roam per scenario (day / night, parked /
## AI-driving), lets streaming and shaders settle, samples frame times and renderer statistics,
## then prints one `PERFJSON {...}` line per scenario (read from logcat on the RP4) and writes
## user://perf_report.json. The adaptive governor stays on; its tier and render scale are recorded.
## Args (after --): spawn=<poi> car=<key> settle=<s> sample=<s> only=<tag,tag> out=<path>
##   desktop: godot --path godot --resolution 1334x750 -- scene=perf_audit
##   RP4:     tools/profile_device.ps1

const SCENARIOS := [
	{"tag": "day_parked", "time": 14.0, "drive": false},
	{"tag": "day_driving", "time": 14.0, "drive": true},
	{"tag": "night_parked", "time": 22.5, "drive": false},
	{"tag": "night_driving", "time": 22.5, "drive": true},
]

func _ready() -> void:
	# The runner lives under the root so it survives the scene changes into free roam.
	var d := Runner.new()
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(d)

class Runner:
	extends Node

	var args := {}
	var results := []

	func _ready() -> void:
		for a in OS.get_cmdline_user_args():
			var kv := a.split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
		print("PERF audit on %s  %s x%d  refresh %.0f Hz" % [OS.get_name(), OS.get_processor_name(), OS.get_processor_count(), DisplayServer.screen_get_refresh_rate()])
		var only: PackedStringArray = String(args.get("only", "")).split(",", false)
		for sc in SCENARIOS:
			if only.is_empty() or only.has(sc.tag):
				await _run(sc)
		var report := {"platform": OS.get_name(), "device": OS.get_model_name(), "gpu": RenderingServer.get_video_adapter_name(),
			"date": Time.get_datetime_string_from_system(), "scenarios": results}
		var f := FileAccess.open("user://perf_report.json", FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(report, "  "))
		if args.has("out"):
			var o := FileAccess.open(String(args.out), FileAccess.WRITE)
			if o:
				o.store_string(JSON.stringify(report, "  "))
		print("PERF audit done")
		get_tree().quit()

	func _run(sc: Dictionary) -> void:
		var launch := {"car": args.get("car", "golf_gti"), "spawn": args.get("spawn", "garage_port"), "time": str(sc.time), "weather": "0"}
		if sc.drive:
			launch["autodrive"] = "1"
		get_tree().root.set_meta("launch", launch)
		get_tree().change_scene_to_file("res://scenes/freeroam.tscn")
		# Wait for the world to build and stream in.
		var t0 := Time.get_ticks_msec()
		while true:
			await get_tree().process_frame
			var s = get_tree().current_scene
			if s != null and s.get("_state") == "playing":
				break
			if Time.get_ticks_msec() - t0 > 180000:
				print("PERF %s: world never finished loading" % sc.tag)
				return
		var load_s := (Time.get_ticks_msec() - t0) / 1000.0
		var fr = get_tree().current_scene
		if fr.get("sky") != null:
			fr.sky.time_scale = 0.0 # freeze the clock at the scenario time
		await _secs(float(args.get("settle", "8")))
		var vp := get_viewport().get_viewport_rid()
		var ms := PackedFloat32Array()
		var gpu := 0.0
		var cpu := 0.0
		var draws := 0.0
		var prims := 0.0
		var objs := 0.0
		var n := 0
		var t_end := Time.get_ticks_msec() + int(float(args.get("sample", "12")) * 1000.0)
		while Time.get_ticks_msec() < t_end:
			await get_tree().process_frame
			ms.append(get_process_delta_time() * 1000.0)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			draws += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
			prims += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
			objs += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
			n += 1
		var shadow_draws := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var sorted := ms.duplicate()
		sorted.sort()
		var total := 0.0
		for v in ms:
			total += v
		var avg := total / maxf(1.0, ms.size())
		var p99: float = sorted[int(sorted.size() * 0.99)] if not sorted.is_empty() else 0.0
		var r := {
			"tag": sc.tag, "load_s": snappedf(load_s, 0.1), "frames": ms.size(),
			"fps_avg": snappedf(1000.0 / maxf(avg, 0.01), 0.1), "fps_low1": snappedf(1000.0 / maxf(p99, 0.01), 0.1),
			"frame_ms_avg": snappedf(avg, 0.01), "frame_ms_p99": snappedf(p99, 0.01), "frame_ms_max": snappedf(sorted[-1] if not sorted.is_empty() else 0.0, 0.01),
			"gpu_ms": snappedf(gpu / maxf(1, n), 0.01), "cpu_ms": snappedf(cpu / maxf(1, n), 0.01),
			"draw_calls": int(draws / maxf(1, n)), "shadow_draw_calls": int(shadow_draws), "primitives": int(prims / maxf(1, n)), "objects": int(objs / maxf(1, n)),
			"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
			"texture_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
			"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
			"governor_tier": Perf.level, "render_scale": snappedf(get_viewport().scaling_3d_scale, 0.01),
			"msaa": get_viewport().msaa_3d, "thermal": snappedf(Perf.thermal, 0.01),
		}
		results.append(r)
		print("PERFJSON " + JSON.stringify(r))

	func _secs(s: float) -> void:
		var t := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t < s * 1000.0:
			await get_tree().process_frame
