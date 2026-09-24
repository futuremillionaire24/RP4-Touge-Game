extends Node
## QA harness (tester "world"): sets up the profile + launch meta, installs a persistent
## director node on the root, then loads free roam (or the festival).

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var d: Node = load("res://qa/world/director.gd").new()
	d.name = "QADirector"
	d.args = args
	get_tree().root.call_deferred("add_child", d)
	var launch := {}
	for k in ["car", "garage_index", "time", "weather", "season", "spawn", "event", "autodrive", "route"]:
		if args.has("l_" + k):
			launch[k] = args["l_" + k]
	# Profile preparation.
	if args.has("reset_profile"):
		Profile.reset()
	if Profile.data.garage.is_empty():
		Profile.choose_starter("sylph_s2")
	if args.has("give_car"):
		for key in String(args.give_car).split(","):
			if not Profile.owns(key):
				Profile.add_car(key, "qa", false)
	if args.has("level"):
		Profile.data.level = int(args.level)
	if args.has("difficulty"):
		Settings.set_value("assists", "difficulty", int(args.difficulty), false)
	if args.has("mph"):
		Settings.set_value("gameplay", "units_metric", false, false)
	if args.has("hud_scale"):
		Settings.set_value("gameplay", "hud_scale", float(args.hud_scale), false)
	Profile.save()
	if not launch.is_empty():
		get_tree().root.set_meta("launch", launch)
	var target := "res://scenes/freeroam.tscn"
	if args.get("start", "") == "festival":
		target = "res://scenes/festival.tscn"
		get_tree().root.set_meta("festival_screen", args.get("fscreen", "hub"))
	get_tree().call_deferred("change_scene_to_file", target)
