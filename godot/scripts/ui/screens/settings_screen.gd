class_name SettingsScreen
extends MenuScreen
## Settings: assists & difficulty, controls (deadzones / curves / vibration), audio mixer,
## graphics tier and budgets, gameplay/HUD. Every row writes through Settings immediately
## (systems listen to Settings.changed); X resets the current page to defaults.

const DIFFICULTY := ["Novice", "Easy", "Average", "Skilled", "Pro", "Expert", "Unbeatable"]

const PAGES := {
	"Assists": [
		{"s": "assists", "k": "preset", "name": "Handling preset", "enum": ["Casual", "Touge Sport", "Purist Sim", "Custom"]},
		{"s": "assists", "k": "difficulty", "name": "Rival difficulty", "enum": DIFFICULTY},
		{"s": "assists", "k": "abs", "name": "ABS", "bool": true},
		{"s": "assists", "k": "tcs", "name": "Traction control", "bool": true},
		{"s": "assists", "k": "stm", "name": "Stability control", "bool": true},
		{"s": "assists", "k": "steering", "name": "Steering", "enum": ["Assisted", "Standard", "Simulation"]},
		{"s": "assists", "k": "gearbox", "name": "Gearbox", "enum": ["Automatic", "Manual", "Manual + clutch"]},
		{"s": "assists", "k": "countersteer", "name": "Countersteer assist", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct"},
		{"s": "assists", "k": "rewind", "name": "Rewind (off = +10% payout)", "bool": true},
		{"s": "assists", "k": "mechanical_damage", "name": "Mechanical damage", "bool": true},
	],
	"Controls": [
		{"action": "controller_screen", "name": "▶ CONFIGURE GAMEPAD & REMAP"},
		{"s": "controls", "k": "steer_deadzone", "name": "Steering deadzone", "min": 0.0, "max": 0.3, "step": 0.01, "fmt": "pct"},
		{"s": "controls", "k": "steer_linearity", "name": "Steering linearity", "min": 0.5, "max": 2.5, "step": 0.05, "fmt": "x"},
		{"s": "controls", "k": "steer_saturation", "name": "Steering saturation", "min": 0.7, "max": 1.0, "step": 0.01, "fmt": "pct"},
		{"s": "controls", "k": "throttle_deadzone", "name": "Throttle deadzone", "min": 0.0, "max": 0.3, "step": 0.01, "fmt": "pct"},
		{"s": "controls", "k": "throttle_curve", "name": "Throttle curve", "min": 0.5, "max": 2.5, "step": 0.05, "fmt": "x"},
		{"s": "controls", "k": "brake_deadzone", "name": "Brake deadzone", "min": 0.0, "max": 0.3, "step": 0.01, "fmt": "pct"},
		{"s": "controls", "k": "brake_curve", "name": "Brake curve", "min": 0.5, "max": 2.5, "step": 0.05, "fmt": "x"},
		{"s": "controls", "k": "vibration", "name": "Vibration", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct"},
		{"s": "gameplay", "k": "handbrake_toggle", "name": "Handbrake toggle mode", "bool": true},
	],
	"Audio": [
		{"s": "audio", "k": "master", "name": "Master", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct"},
		{"s": "audio", "k": "engine", "name": "Engine", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct"},
		{"s": "audio", "k": "effects", "name": "Effects", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct"},
		{"s": "audio", "k": "music", "name": "Music", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct"},
		{"s": "audio", "k": "ambience", "name": "Ambience", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct"},
	],
	"Graphics": [
		{"s": "graphics", "k": "tier", "name": "Quality tier", "enum": ["Low", "Medium", "High", "Ultra", "Custom"]},
		{"s": "graphics", "k": "fps_target", "name": "Frame rate", "values": [60, 40], "labels": ["60 locked", "40 battery"]},
		{"s": "graphics", "k": "dynamic_resolution", "name": "Dynamic resolution", "bool": true},
		{"s": "graphics", "k": "supersample_max", "name": "Max supersampling", "min": 1.0, "max": 1.4, "step": 0.05, "fmt": "x"},
		{"s": "graphics", "k": "draw_distance", "name": "Draw distance", "min": 0.6, "max": 1.5, "step": 0.05, "fmt": "pct"},
		{"s": "graphics", "k": "traffic_density", "name": "Traffic density", "min": 0.0, "max": 1.5, "step": 0.05, "fmt": "pct"},
		{"s": "graphics", "k": "foliage", "name": "Foliage", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct"},
		{"s": "graphics", "k": "retro_arcade", "name": "Retro arcade FX", "values": [0, 1, 2], "labels": ["Off", "Subtle Arcade", "Retro CRT"]},
		{"s": "graphics", "k": "show_fps", "name": "Performance overlay", "bool": true},
	],
	"Gameplay": [
		{"s": "gameplay", "k": "units_metric", "name": "Units", "values": [true, false], "labels": ["Metric", "Imperial"]},
		{"s": "gameplay", "k": "hud_scale", "name": "HUD scale", "min": 0.8, "max": 1.2, "step": 0.05, "fmt": "pct"},
		{"s": "gameplay", "k": "camera_shake", "name": "Camera shake", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct"},
		{"s": "gameplay", "k": "reduced_motion", "name": "Reduced motion", "bool": true},
	],
}

var _page := 0
var _tabs: HBoxContainer
var _list: VBoxContainer
var _note: Label

func build() -> void:
	var col := make_column(640)
	col.add_child(UIKit.header("Settings", "", "Audio, Graphics & Controls"))
	_tabs = make_tabs(col, PAGES.keys())
	_list = make_list(col, 470)
	_note = UIKit.label("", 16, UIKit.DIM)
	col.add_child(_note)
	set_hints([["◀▶", "Change"], ["X", "Reset page"], ["L1", ""], ["R1", "Page"], ["B", "Back"]])
	stage.frame_offset = 2.4

func refresh() -> void:
	highlight_tabs(_tabs, _page)
	for c in _list.get_children():
		c.queue_free()
	var page: String = PAGES.keys()[_page]
	_note.text = "Streaming, draw distance and foliage apply the next time the world loads." if page == "Graphics" else ""
	var first: UIRow = null
	for spec in PAGES[page]:
		var row := UIRow.new(spec.name)
		row.on_adjust = _adjust.bind(row, spec)
		row.on_accept = func(): _adjust(1, row, spec)
		_update(row, spec)
		_list.add_child(row)
		if first == null:
			first = row
	if first and is_inside_tree():
		first.call_deferred("grab_focus")

func _read(spec: Dictionary) -> Variant:
	return Settings.get_value(spec.s, spec.k)

const ControllerScreenClass = preload("res://scripts/ui/screens/controller_screen.gd")

func _adjust(dir: int, row: UIRow, spec: Dictionary) -> void:
	if spec.has("action"):
		if spec.action == "controller_screen" and festival != null:
			festival.push(ControllerScreenClass.new())
		return
	var v = _read(spec)
	if spec.has("bool"):
		v = not bool(v)
	elif spec.has("enum"):
		v = wrapi(int(v) + dir, 0, spec.enum.size())
	elif spec.has("values"):
		var i: int = spec.values.find(v)
		v = spec.values[wrapi(i + dir, 0, spec.values.size())]
	else:
		v = clampf(snappedf(float(v) + dir * float(spec.step), float(spec.step)), spec.min, spec.max)
	Settings.set_value(spec.s, spec.k, v)
	if spec.k == "preset":
		Settings.apply_handling_preset(int(v))
		refresh()
		return
	elif spec.s == "assists" and spec.k in ["abs", "tcs", "stm", "steering", "gearbox", "countersteer"]:
		Settings.set_value("assists", "preset", Settings.HandlingPreset.CUSTOM, false)
	if spec.k == "tier":
		_apply_tier(int(v))
	_update(row, spec)

func _update(row: UIRow, spec: Dictionary) -> void:
	if spec.has("action"):
		row.set_value("OPEN", UIKit.NEON)
		return
	var v = _read(spec)
	if spec.has("bool"):
		row.set_value("ON" if bool(v) else "OFF", UIKit.GREEN if bool(v) else UIKit.DIM)
	elif spec.has("enum"):
		row.set_value(spec.enum[clampi(int(v), 0, spec.enum.size() - 1)])
	elif spec.has("values"):
		row.set_value(spec.labels[maxi(0, spec.values.find(v))])
	else:
		var f := float(v)
		row.set_value("%d%%" % roundi(f * 100.0) if spec.fmt == "pct" else "%.2f×" % f)
		row.set_fraction((f - float(spec.min)) / (float(spec.max) - float(spec.min)))

## Tier presets fill the individual graphics budgets (Custom leaves them alone).
func _apply_tier(tier: int) -> void:
	var presets := {
		Settings.Tier.LOW: {"supersample_max": 1.0, "draw_distance": 0.7, "foliage": 0.4, "traffic_density": 0.6, "shadows": 1, "particles": 0.5},
		Settings.Tier.MEDIUM: {"supersample_max": 1.1, "draw_distance": 0.85, "foliage": 0.7, "traffic_density": 0.8, "shadows": 1, "particles": 0.75},
		Settings.Tier.HIGH: {"supersample_max": 1.3, "draw_distance": 1.0, "foliage": 1.0, "traffic_density": 1.0, "shadows": 2, "particles": 1.0},
		Settings.Tier.ULTRA: {"supersample_max": 1.4, "draw_distance": 1.3, "foliage": 1.0, "traffic_density": 1.3, "shadows": 3, "particles": 1.0},
	}
	if not presets.has(tier):
		return
	for k in presets[tier]:
		Settings.set_value("graphics", k, presets[tier][k], false)
	Settings.save_settings()
	Settings.changed.emit("graphics")
	refresh()

func action_x() -> void:
	var page: String = PAGES.keys()[_page]
	var sections := {}
	for spec in PAGES[page]:
		sections[spec.s] = true
	var defaults := Settings._defaults()
	for spec in PAGES[page]:
		Settings.set_value(spec.s, spec.k, defaults[spec.s][spec.k], false)
	Settings.save_settings()
	for s in sections:
		Settings.changed.emit(s)
	festival.toast("%s RESET TO DEFAULTS" % page.to_upper())
	refresh()

func tab(dir: int) -> void:
	_page = wrapi(_page + dir, 0, PAGES.size())
	refresh()

func leave() -> void:
	super.leave()
	stage.frame_offset = 1.3
