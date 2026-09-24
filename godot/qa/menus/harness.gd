extends Node
## QA harness entry: spawns the persistent driver under the root, which then loads the festival.

func _ready() -> void:
	var s = load("res://qa/menus/driver.gd")
	if s == null or not s.can_instantiate():
		print("QA| DRIVER FAILED TO LOAD")
		get_tree().quit(1)
		return
	var d: Node = s.new()
	d.name = "MenusDriver"
	get_tree().root.add_child.call_deferred(d)
