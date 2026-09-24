extends Node
## Unified driving input: RP4 Pro gamepad (Hall sticks + analog Hall triggers) with keyboard
## fallback and in-game remapping. Handles both analog axes and digital triggers on Android.

signal device_changed(has_pad: bool)

const ACTIONS := [
	"throttle", "brake", "steer_left", "steer_right",
	"handbrake", "clutch", "shift_up", "shift_down", "camera", "rewind", "look_back",
	"photo", "pause", "map", "lights", "radio_next", "radio_prev", "horn", "reset_car",
]

# Action user-facing display names
const ACTION_LABELS := {
	"throttle": "Accelerate (Gas)",
	"brake": "Brake / Reverse",
	"steer_left": "Steer Left",
	"steer_right": "Steer Right",
	"handbrake": "Handbrake (Drift)",
	"clutch": "Clutch Pedal",
	"shift_up": "Gear Shift Up",
	"shift_down": "Gear Shift Down",
	"camera": "Change Camera",
	"rewind": "Rewind Time",
	"look_back": "Rearview Mirror",
	"photo": "Photo Mode",
	"pause": "Pause Menu",
	"map": "Minimap / GPS",
	"lights": "Headlights Toggle",
	"horn": "Horn",
	"radio_next": "Radio Next Track",
	"radio_prev": "Radio Prev Track",
	"reset_car": "Recover / Reset Car",
}

# Default joypad bindings: {"button": JoyButton} or {"axis": JoyAxis, "sign": +-1}.
const DEFAULT_PAD := {
	"throttle": {"axis": JOY_AXIS_TRIGGER_RIGHT, "sign": 1.0},
	"brake": {"axis": JOY_AXIS_TRIGGER_LEFT, "sign": 1.0},
	"steer_left": {"axis": JOY_AXIS_LEFT_X, "sign": -1.0},
	"steer_right": {"axis": JOY_AXIS_LEFT_X, "sign": 1.0},
	"handbrake": {"button": JOY_BUTTON_A},
	"clutch": {"button": JOY_BUTTON_B},
	"shift_up": {"button": JOY_BUTTON_Y},
	"shift_down": {"button": JOY_BUTTON_X},
	"camera": {"button": JOY_BUTTON_RIGHT_SHOULDER},
	"rewind": {"button": JOY_BUTTON_LEFT_SHOULDER},
	"look_back": {"button": JOY_BUTTON_LEFT_STICK},
	"photo": {"button": JOY_BUTTON_MISC1},
	"pause": {"button": JOY_BUTTON_START},
	"map": {"button": JOY_BUTTON_RIGHT_STICK},
	"lights": {"button": JOY_BUTTON_DPAD_UP},
	"horn": {"button": JOY_BUTTON_DPAD_DOWN},
	"radio_next": {"button": JOY_BUTTON_DPAD_RIGHT},
	"radio_prev": {"button": JOY_BUTTON_DPAD_LEFT},
	"reset_car": {"button": JOY_BUTTON_BACK},
}

const PRESETS := {
	"rp4_default": {
		"name": "Retroid Pocket 4 Pro (Default)",
		"bindings": {
			"throttle": {"axis": JOY_AXIS_TRIGGER_RIGHT, "sign": 1.0},
			"brake": {"axis": JOY_AXIS_TRIGGER_LEFT, "sign": 1.0},
			"steer_left": {"axis": JOY_AXIS_LEFT_X, "sign": -1.0},
			"steer_right": {"axis": JOY_AXIS_LEFT_X, "sign": 1.0},
			"handbrake": {"button": JOY_BUTTON_A},
			"clutch": {"button": JOY_BUTTON_B},
			"shift_up": {"button": JOY_BUTTON_Y},
			"shift_down": {"button": JOY_BUTTON_X},
			"camera": {"button": JOY_BUTTON_RIGHT_SHOULDER},
			"rewind": {"button": JOY_BUTTON_LEFT_SHOULDER},
			"look_back": {"button": JOY_BUTTON_LEFT_STICK},
			"reset_car": {"button": JOY_BUTTON_BACK},
			"pause": {"button": JOY_BUTTON_START},
			"lights": {"button": JOY_BUTTON_DPAD_UP},
			"horn": {"button": JOY_BUTTON_DPAD_DOWN},
		}
	},
	"rp4_retro_abxy": {
		"name": "RP4 Retro Layout (ABXY Swapped)",
		"bindings": {
			"throttle": {"axis": JOY_AXIS_TRIGGER_RIGHT, "sign": 1.0},
			"brake": {"axis": JOY_AXIS_TRIGGER_LEFT, "sign": 1.0},
			"steer_left": {"axis": JOY_AXIS_LEFT_X, "sign": -1.0},
			"steer_right": {"axis": JOY_AXIS_LEFT_X, "sign": 1.0},
			"handbrake": {"button": JOY_BUTTON_B},
			"clutch": {"button": JOY_BUTTON_A},
			"shift_up": {"button": JOY_BUTTON_X},
			"shift_down": {"button": JOY_BUTTON_Y},
			"camera": {"button": JOY_BUTTON_RIGHT_SHOULDER},
			"rewind": {"button": JOY_BUTTON_LEFT_SHOULDER},
			"look_back": {"button": JOY_BUTTON_LEFT_STICK},
			"reset_car": {"button": JOY_BUTTON_BACK},
			"pause": {"button": JOY_BUTTON_START},
			"lights": {"button": JOY_BUTTON_DPAD_UP},
			"horn": {"button": JOY_BUTTON_DPAD_DOWN},
		}
	},
	"bumper_drive": {
		"name": "Bumper Driving (L1/R1 Throttle & Brake)",
		"bindings": {
			"throttle": {"button": JOY_BUTTON_RIGHT_SHOULDER},
			"brake": {"button": JOY_BUTTON_LEFT_SHOULDER},
			"steer_left": {"axis": JOY_AXIS_LEFT_X, "sign": -1.0},
			"steer_right": {"axis": JOY_AXIS_LEFT_X, "sign": 1.0},
			"handbrake": {"button": JOY_BUTTON_A},
			"clutch": {"button": JOY_BUTTON_B},
			"shift_up": {"button": JOY_BUTTON_Y},
			"shift_down": {"button": JOY_BUTTON_X},
			"camera": {"axis": JOY_AXIS_TRIGGER_RIGHT, "sign": 1.0},
			"rewind": {"axis": JOY_AXIS_TRIGGER_LEFT, "sign": 1.0},
			"look_back": {"button": JOY_BUTTON_LEFT_STICK},
			"reset_car": {"button": JOY_BUTTON_BACK},
			"pause": {"button": JOY_BUTTON_START},
			"lights": {"button": JOY_BUTTON_DPAD_UP},
			"horn": {"button": JOY_BUTTON_DPAD_DOWN},
		}
	},
	"arcade_buttons": {
		"name": "Classic Arcade (A = Gas, X = Brake)",
		"bindings": {
			"throttle": {"button": JOY_BUTTON_A},
			"brake": {"button": JOY_BUTTON_X},
			"steer_left": {"axis": JOY_AXIS_LEFT_X, "sign": -1.0},
			"steer_right": {"axis": JOY_AXIS_LEFT_X, "sign": 1.0},
			"handbrake": {"button": JOY_BUTTON_B},
			"clutch": {"button": JOY_BUTTON_Y},
			"shift_up": {"button": JOY_BUTTON_RIGHT_SHOULDER},
			"shift_down": {"button": JOY_BUTTON_LEFT_SHOULDER},
			"camera": {"axis": JOY_AXIS_TRIGGER_RIGHT, "sign": 1.0},
			"rewind": {"axis": JOY_AXIS_TRIGGER_LEFT, "sign": 1.0},
			"look_back": {"button": JOY_BUTTON_LEFT_STICK},
			"reset_car": {"button": JOY_BUTTON_BACK},
			"pause": {"button": JOY_BUTTON_START},
			"lights": {"button": JOY_BUTTON_DPAD_UP},
			"horn": {"button": JOY_BUTTON_DPAD_DOWN},
		}
	}
}

const DEFAULT_KEYS := {
	"throttle": KEY_W, "brake": KEY_S, "steer_left": KEY_A, "steer_right": KEY_D,
	"handbrake": KEY_SPACE, "clutch": KEY_SHIFT, "shift_up": KEY_E, "shift_down": KEY_Q,
	"camera": KEY_C, "rewind": KEY_R, "look_back": KEY_V, "photo": KEY_P, "pause": KEY_ESCAPE,
	"map": KEY_M, "lights": KEY_L, "horn": KEY_H, "radio_next": KEY_PERIOD, "radio_prev": KEY_COMMA,
	"reset_car": KEY_BACKSPACE,
}

var device := -1
var has_pad := false
var steer := 0.0
var throttle := 0.0
var brake := 0.0
var look := Vector2.ZERO
var _held := {}
var _pressed := {}
var _released := {}
var _held_f := {}
var _pressed_f := {}
var _released_f := {}
var _kb_steer := 0.0
var _handbrake_latch := false

func _ready() -> void:
	process_priority = -100
	process_physics_priority = -100
	Input.joy_connection_changed.connect(_on_joy_changed)
	_pick_device()
	for a in ACTIONS:
		_held[a] = false
		_pressed[a] = false
		_released[a] = false
		_held_f[a] = false
		_pressed_f[a] = false
		_released_f[a] = false
	_add_ui_pad_events()

func _add_ui_pad_events() -> void:
	var map := {
		"ui_accept": [JOY_BUTTON_A], "ui_cancel": [JOY_BUTTON_B],
		"ui_up": [JOY_BUTTON_DPAD_UP], "ui_down": [JOY_BUTTON_DPAD_DOWN],
		"ui_left": [JOY_BUTTON_DPAD_LEFT], "ui_right": [JOY_BUTTON_DPAD_RIGHT]
	}
	for action in map:
		for btn in map[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = btn
			ev.device = -1
			if not InputMap.action_has_event(action, ev):
				InputMap.action_add_event(action, ev)

func _on_joy_changed(_d: int, _connected: bool) -> void:
	_pick_device()

func _pick_device() -> void:
	var pads := Input.get_connected_joypads()
	device = pads[0] if pads.size() > 0 else -1
	var now := device >= 0
	if now != has_pad:
		has_pad = now
		device_changed.emit(has_pad)

func binding(action: String) -> Dictionary:
	var custom: Dictionary = Settings.get_value("controls", "bindings", {})
	if custom.has(action):
		return custom[action]
	return DEFAULT_PAD.get(action, {})

func rebind(action: String, spec: Dictionary) -> void:
	var custom: Dictionary = Settings.get_value("controls", "bindings", {}).duplicate()
	custom[action] = spec
	Settings.set_value("controls", "bindings", custom)

func reset_to_defaults() -> void:
	Settings.set_value("controls", "bindings", {})

func apply_preset(preset_key: String) -> void:
	if PRESETS.has(preset_key):
		var b: Dictionary = PRESETS[preset_key]["bindings"]
		Settings.set_value("controls", "bindings", b.duplicate())

func _pad_action(action: String) -> float:
	if device < 0:
		return 0.0
	var b := binding(action)
	if b.has("button"):
		return 1.0 if Input.is_joy_button_pressed(device, b.button) else 0.0
	if b.has("axis"):
		var raw: float = Input.get_joy_axis(device, b.axis) * float(b.get("sign", 1.0))
		return clampf(raw, 0.0, 1.0)
	return 0.0

static func shape(v: float, deadzone: float, linearity: float, saturation: float) -> float:
	var s := signf(v)
	var a := absf(v)
	if a <= deadzone:
		return 0.0
	a = clampf((a - deadzone) / maxf(saturation - deadzone, 0.01), 0.0, 1.0)
	return s * pow(a, linearity)

func _physics_process(delta: float) -> void:
	var c: Dictionary = Settings.section("controls")
	var pad_steer := 0.0
	var pad_thr := 0.0
	var pad_brk := 0.0
	var pad_look := Vector2.ZERO

	if device >= 0:
		# Steering reading
		var st_left := binding("steer_left")
		var st_right := binding("steer_right")
		var raw_steer := 0.0
		if st_left.has("axis"):
			raw_steer = Input.get_joy_axis(device, st_left.axis)
		elif st_left.has("button") or st_right.has("button"):
			if st_left.has("button") and Input.is_joy_button_pressed(device, st_left.button):
				raw_steer -= 1.0
			if st_right.has("button") and Input.is_joy_button_pressed(device, st_right.button):
				raw_steer += 1.0
		else:
			raw_steer = Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		pad_steer = shape(raw_steer, c.get("steer_deadzone", 0.06), c.get("steer_linearity", 1.35), c.get("steer_saturation", 0.97))

		# Throttle reading: axis or button with digital trigger fallback for RP4
		var thr_b := binding("throttle")
		if thr_b.has("axis"):
			var raw_axis := Input.get_joy_axis(device, thr_b.axis) * float(thr_b.get("sign", 1.0))
			pad_thr = shape(raw_axis, c.get("throttle_deadzone", 0.03), c.get("throttle_curve", 1.0), 0.98)
		elif thr_b.has("button"):
			pad_thr = 1.0 if Input.is_joy_button_pressed(device, thr_b.button) else 0.0
		if pad_thr < 0.05 and thr_b.has("alt_button"):
			if Input.is_joy_button_pressed(device, thr_b.alt_button):
				pad_thr = 1.0

		# Brake reading: axis or button with digital trigger fallback for RP4
		var brk_b := binding("brake")
		if brk_b.has("axis"):
			var raw_axis := Input.get_joy_axis(device, brk_b.axis) * float(brk_b.get("sign", 1.0))
			pad_brk = shape(raw_axis, c.get("brake_deadzone", 0.03), c.get("brake_curve", 1.15), 0.98)
		elif brk_b.has("button"):
			pad_brk = 1.0 if Input.is_joy_button_pressed(device, brk_b.button) else 0.0
		if pad_brk < 0.05 and brk_b.has("alt_button"):
			if Input.is_joy_button_pressed(device, brk_b.alt_button):
				pad_brk = 1.0

		pad_look = Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
		if pad_look.length() < 0.15:
			pad_look = Vector2.ZERO

	# Keyboard fallback
	var kb_dir := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		kb_dir -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		kb_dir += 1.0
	var rate := 3.5 if kb_dir != 0.0 and signf(kb_dir) == signf(_kb_steer) else 6.0
	_kb_steer = move_toward(_kb_steer, kb_dir, rate * delta)
	var kb_thr := 1.0 if (Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) else 0.0
	var kb_brk := 1.0 if (Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) else 0.0

	steer = pad_steer if absf(pad_steer) > absf(_kb_steer) else _kb_steer
	throttle = maxf(pad_thr, kb_thr)
	brake = maxf(pad_brk, kb_brk)
	look = pad_look
	if bool(c.get("invert_look", false)):
		look.y = -look.y

	for a in ACTIONS:
		var down := _action_down(a)
		_pressed[a] = down and not _held[a]
		_released[a] = (not down) and _held[a]
		_held[a] = down
	if Settings.get_value("gameplay", "handbrake_toggle", false) and _pressed.get("handbrake", false):
		_handbrake_latch = not _handbrake_latch

func held(action: String) -> bool:
	return _held.get(action, false)

func pressed(action: String) -> bool:
	if Engine.is_in_physics_frame():
		return _pressed.get(action, false)
	return _pressed_f.get(action, false)

func released(action: String) -> bool:
	if Engine.is_in_physics_frame():
		return _released.get(action, false)
	return _released_f.get(action, false)

func _action_down(a: String) -> bool:
	if a == "throttle":
		return throttle > 0.3
	elif a == "brake":
		return brake > 0.3
	elif a == "steer_left":
		return steer < -0.3
	elif a == "steer_right":
		return steer > 0.3
	return _pad_action(a) > 0.5 or (DEFAULT_KEYS.has(a) and Input.is_key_pressed(DEFAULT_KEYS[a]))

func _process(_delta: float) -> void:
	for a in ACTIONS:
		var down := _action_down(a)
		_pressed_f[a] = down and not _held_f[a]
		_released_f[a] = (not down) and _held_f[a]
		_held_f[a] = down

func handbrake() -> float:
	if Settings.get_value("gameplay", "handbrake_toggle", false):
		return 1.0 if _handbrake_latch else 0.0
	return 1.0 if _held.get("handbrake", false) else 0.0

func clutch() -> float:
	return 1.0 if _held.get("clutch", false) else 0.0

## Human-readable string for any button index
static func button_name(btn: int) -> String:
	match btn:
		JOY_BUTTON_A: return "A Button"
		JOY_BUTTON_B: return "B Button"
		JOY_BUTTON_X: return "X Button"
		JOY_BUTTON_Y: return "Y Button"
		JOY_BUTTON_LEFT_SHOULDER: return "L1 (Left Bumper)"
		JOY_BUTTON_RIGHT_SHOULDER: return "R1 (Right Bumper)"
		JOY_BUTTON_BACK: return "Select / Back"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_LEFT_STICK: return "L3 (Left Stick Click)"
		JOY_BUTTON_RIGHT_STICK: return "R3 (Right Stick Click)"
		JOY_BUTTON_DPAD_UP: return "D-Pad Up"
		JOY_BUTTON_DPAD_DOWN: return "D-Pad Down"
		JOY_BUTTON_DPAD_LEFT: return "D-Pad Left"
		JOY_BUTTON_DPAD_RIGHT: return "D-Pad Right"
		JOY_BUTTON_MISC1: return "Share / M1"
		_: return "Button %d" % btn

## Human-readable string for any joypad axis
static func axis_name(axis: int, sgn: float = 1.0) -> String:
	match axis:
		JOY_AXIS_LEFT_X: return "Left Stick Left" if sgn < 0 else "Left Stick Right"
		JOY_AXIS_LEFT_Y: return "Left Stick Up" if sgn < 0 else "Left Stick Down"
		JOY_AXIS_RIGHT_X: return "Right Stick Left" if sgn < 0 else "Right Stick Right"
		JOY_AXIS_RIGHT_Y: return "Right Stick Up" if sgn < 0 else "Right Stick Down"
		JOY_AXIS_TRIGGER_LEFT: return "LT / L2 Trigger"
		JOY_AXIS_TRIGGER_RIGHT: return "RT / R2 Trigger"
		_: return "Axis %d %s" % [axis, "+" if sgn > 0 else "-"]

## Formats current binding of an action into a clean UI label
func binding_string(action: String) -> String:
	var b := binding(action)
	if b.has("button"):
		return button_name(int(b.button))
	if b.has("axis"):
		return axis_name(int(b.axis), float(b.get("sign", 1.0)))
	if DEFAULT_KEYS.has(action):
		return OS.get_keycode_string(DEFAULT_KEYS[action])
	return "Unbound"

## Full raw state for the interactive controller test screen.
func raw_state() -> Dictionary:
	var d := {
		"device": device,
		"name": Input.get_joy_name(device) if device >= 0 else "Keyboard / None",
		"guid": Input.get_joy_guid(device) if device >= 0 else "",
		"axes": [],
		"buttons": []
	}
	if device >= 0:
		for a in range(8):
			d.axes.append(Input.get_joy_axis(device, a))
		for b in range(16):
			d.buttons.append(Input.is_joy_button_pressed(device, b))
	return d
