extends Node
## Offline engine-sound check: sweeps each car's synth through idle -> redline under load, a
## lift-off (blow-off / pops), the limiter and a tire slide, recording the Master bus to WAV.
## Usage: godot --path . -- scene=audio_render cars=sylph_s2,rotora_fd out=D:/path/dir

func _ready() -> void:
	var cars := ["sylph_s2"]
	var out_dir := "user://audio"
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv[0] == "cars":
			cars = kv[1].split(",")
		elif kv[0] == "out":
			out_dir = kv[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	for key in cars:
		var stream := NTEngineAudio.new()
		stream.configure(key, true)
		var p := AudioStreamPlayer.new()
		p.stream = stream
		add_child(p)
		p.play()
		var spec_sim := NTSim.new()
		add_child(spec_sim)
		var id := spec_sim.add_car(key, {}, false, 1)
		var spec := spec_sim.get_car_spec(id)
		var idle: float = spec.idle_rpm
		var red: float = spec.redline_rpm
		var mb: float = spec.max_boost
		rec.set_recording_active(true)
		var t := 0.0
		while t < 9.0:
			var dt := get_process_delta_time()
			await get_tree().process_frame
			t += dt
			var rpm := idle
			var thr := 0.0
			var boost := 0.0
			var slip := 0.0
			var limiter := false
			if t < 1.0:
				rpm = idle
			elif t < 4.5:
				var k := (t - 1.0) / 3.5
				rpm = lerpf(idle * 1.5, red, k)
				thr = 1.0
				boost = mb * clampf(k * 1.5, 0.0, 1.0)
			elif t < 5.2:
				rpm = red + 150.0 * sin(t * 90.0)
				thr = 1.0
				boost = mb
				limiter = fmod(t, 0.14) < 0.07
			elif t < 7.0:
				rpm = lerpf(red, idle * 1.4, (t - 5.2) / 1.8)
				thr = 0.0
				boost = mb * maxf(0.0, 1.0 - (t - 5.2) * 3.0)
			else:
				rpm = 4500.0
				thr = 0.6
				slip = 0.8
			stream.set_state({"rpm": rpm, "throttle": thr, "load": thr, "boost": boost, "speed": rpm / 200.0,
				"gear_ratio": 8.0, "slip": slip, "slip_pitch": 0.5, "limiter": limiter})
		rec.set_recording_active(false)
		var wav := rec.get_recording()
		var path := out_dir.path_join("engine_%s.wav" % key)
		wav.save_to_wav(path)
		print("AUDIO_RENDER ", path)
		p.queue_free()
		spec_sim.queue_free()
	get_tree().quit()
