extends SceneTree

func _init() -> void:
	for key in ["mame_k", "hachi_gt", "sylph_s2", "rotora_fd", "raijin_r", "kurogane_hyper"]:
		var t0 := Time.get_ticks_usec()
		var r: Dictionary = NTSim.benchmark(key, {})
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		print("QA| bench %s %.1f ms pi=%s top=%s" % [key, dt, str(r.get("pi")), str(r.get("top_speed"))])
	quit()
