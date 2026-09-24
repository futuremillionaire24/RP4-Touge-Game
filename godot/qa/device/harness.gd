extends Node
## QA "device" harness. Modes (after --): mode=perf | mode=nav | mode=freeroam
## Spawns a persistent driver node under root so it survives scene changes.

const OUT := "D:/Android_RP4_Game/build/qa/device/"

func _ready() -> void:
	var mode := "perf"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mode="):
			mode = a.substr(5)
	var d := Node.new()
	d.set_script(load("res://qa/device/driver.gd"))
	d.set("mode", mode)
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(d)
