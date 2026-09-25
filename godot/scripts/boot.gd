extends Node
## Entry point. `-- scene=<name>` jumps straight to a scene for testing; otherwise the festival title.

const SCENES := {
	"festival": "res://scenes/festival.tscn",
	"launcher": "res://scenes/launcher.tscn",
	"test_drive": "res://scenes/test_drive.tscn",
	"freeroam": "res://scenes/freeroam.tscn",
	"input_test": "res://scenes/input_test.tscn",
	"benchmark": "res://scenes/benchmark.tscn",
	"check": "res://scenes/check.tscn",
	"audio_render": "res://scenes/audio_render.tscn",
	"showroom": "res://scenes/showroom.tscn",
	"car_preview": "res://tools/car_preview.tscn",
	"map_test": "res://qa/map_test.tscn",
	"perf_audit": "res://scenes/perf_audit.tscn",
}

func _ready() -> void:
	var target := "festival"
	for a in LaunchArgs.user_args():
		if a.begins_with("scene="):
			target = a.substr(6)
	var path: String = SCENES.get(target, SCENES["festival"])
	get_tree().call_deferred("change_scene_to_file", path)
