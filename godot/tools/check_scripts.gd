extends Node
## Loads every GDScript and shader in the project (with autoloads registered) and reports
## parse/compile failures, then quits with a non-zero code on failure.
## Usage: godot --headless --path . -- scene=check

func _ready() -> void:
	var failures := 0
	var files := []
	_collect("res://", files)
	for path in files:
		# Reloading the running script with the cache bypassed would swap its bytecode mid-call.
		if path == get_script().resource_path:
			continue
		var res = ResourceLoader.load(path)
		if res == null:
			printerr("FAIL load ", path)
			failures += 1
		elif res is GDScript and not res.can_instantiate():
			printerr("FAIL compile ", path)
			failures += 1
	print("CHECK: %d files, %d failures" % [files.size(), failures])
	get_tree().quit(1 if failures > 0 else 0)

func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null or d.file_exists(".gdignore"):
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not name.begins_with("."):
			var p := dir.path_join(name)
			if d.current_is_dir():
				_collect(p, out)
			elif name.ends_with(".gd") or name.ends_with(".gdshader"):
				out.append(p)
		name = d.get_next()
