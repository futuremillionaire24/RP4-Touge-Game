extends SceneTree

const ControllerScreen := preload("res://scripts/ui/screens/controller_screen.gd")
const PadScript := preload("res://scripts/core/pad.gd")

func _init() -> void:
	var Pad = PadScript.new()
	root.add_child(Pad)
	print("--- Testing RP4 Controller Compatibility & Remapper ---")
	print("Device: ", Pad.device, " Has Pad: ", Pad.has_pad)
	var raw := Pad.raw_state()
	print("Raw device name: ", raw.name)
	print("Throttle binding: ", Pad.binding_string("throttle"))
	print("Brake binding: ", Pad.binding_string("brake"))
	print("Handbrake binding: ", Pad.binding_string("handbrake"))

	# Test preset switching
	Pad.apply_preset("rp4_retro_abxy")
	print("Retro ABXY Handbrake: ", Pad.binding_string("handbrake"))
	assert(Pad.binding("handbrake").button == JOY_BUTTON_B)

	Pad.apply_preset("bumper_drive")
	print("Bumper Driving Throttle: ", Pad.binding_string("throttle"))
	assert(Pad.binding("throttle").button == JOY_BUTTON_RIGHT_SHOULDER)

	Pad.reset_to_defaults()
	print("Reset Throttle: ", Pad.binding_string("throttle"))

	# Test ControllerScreen instantiation
	var ctrl := ControllerScreen.new()
	ctrl.build()
	ctrl.refresh()
	print("✓ ControllerScreen successfully built and refreshed.")
	ctrl.free()

	print("ALL CONTROLLER TESTS PASS!")
	quit(0)
