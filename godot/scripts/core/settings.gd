extends Node
## Persistent player settings (graphics, audio, controls, assists, accessibility).
## Stored as JSON in user://settings.json with an atomic write.

signal changed(section: String)

var PATH := "user://settings.json" # "-- profile=<name>" isolates test runs
const VERSION := 3

enum Tier { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }

var data := {}

func _defaults() -> Dictionary:
	return {
		"version": VERSION,
		"graphics": {
			"tier": Tier.HIGH,
			"fps_target": 60, # 60 or 40 (battery)
			"supersample_max": 1.3,
			"resolution_floor": 0.8,
			"dynamic_resolution": true,
			"msaa": 2, # Viewport.MSAA_4X
			"shadows": 1, # 0 off, 1 low, 2 high, 3 ultra (RP4 60 fps budget: low)
			"reflections": 2, # 0 probe only, 1 + planar low, 2 planar
			"draw_distance": 1.0,
			"traffic_density": 1.0,
			"foliage": 1.0,
			"particles": 1.0,
			"motion_blur": true,
			"lens_effects": true,
			"retro_arcade": 0, # 0 = off, 1 = subtle, 2 = crt (a full-screen pass: ~1.4 ms on the RP4)
			"show_fps": false,
		},
		"audio": {
			"master": 0.9, "engine": 1.0, "effects": 0.9, "music": 0.6, "ambience": 0.7,
			"radio_station": 0,
		},
		"controls": {
			"steer_deadzone": 0.06,
			"steer_linearity": 1.35,
			"steer_saturation": 0.97,
			"throttle_deadzone": 0.03,
			"throttle_curve": 1.0,
			"brake_deadzone": 0.03,
			"brake_curve": 1.15,
			"vibration": 0.8,
			"invert_look": false,
			"bindings": {},
		},
		"assists": {
			"preset": 1, # 0 casual, 1 touge sport, 2 purist sim, 3 custom
			"abs": true,
			"tcs": false,
			"stm": false,
			"steering": 1, # 0 assisted, 1 standard, 2 simulation
			"gearbox": 1, # 0 auto, 1 manual, 2 manual + clutch
			"countersteer": 0.45,
			"braking_line": 1, # 0 off, 1 brake only, 2 full
			"mechanical_damage": false,
			"rewind": true,
			"difficulty": 3, # AI 0..6
		},
		"gameplay": {
			"units_metric": true,
			"language": "en",
			"hud_scale": 1.0,
			"camera_shake": 1.0,
			"colorblind": 0, # 0 off, 1 deutan, 2 protan, 3 tritan
			"text_scale": 1.0,
			"handbrake_toggle": false,
			"reduced_motion": false,
		},
	}

func _ready() -> void:
	for a in LaunchArgs.user_args():
		if a.begins_with("profile="):
			PATH = "user://settings_%s.json" % a.substr(8).validate_filename()
	load_settings()

func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return data.get(section, {}).get(key, default)

func set_value(section: String, key: String, value: Variant, save := true) -> void:
	if not data.has(section):
		data[section] = {}
	data[section][key] = value
	changed.emit(section)
	if save:
		save_settings()

func section(name: String) -> Dictionary:
	return data.get(name, {})

func load_settings() -> void:
	data = _defaults()
	if not FileAccess.file_exists(PATH):
		return
	var text := FileAccess.get_file_as_string(PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Settings: corrupt file, using defaults")
		return
	# Merge known keys only so new defaults survive old files.
	for sec in data.keys():
		if parsed.has(sec) and typeof(parsed[sec]) == TYPE_DICTIONARY:
			for k in parsed[sec].keys():
				if data[sec].has(k):
					data[sec][k] = parsed[sec][k]
	# v2: the RP4 free-roam budget - 4 shadow cascades only on Ultra (older saves stored "high").
	if int(parsed.get("version", 1)) < 2 and int(data.graphics.tier) != Tier.ULTRA:
		data.graphics.shadows = mini(int(data.graphics.shadows), 1)
	# v3: the retro / CAS filter costs ~1.4 ms of GPU a frame on the RP4 - off unless re-enabled.
	if int(parsed.get("version", 1)) < 3:
		data.graphics.retro_arcade = 0

func save_settings() -> void:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Settings: cannot write %s" % tmp)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH))

func reset_section(name: String) -> void:
	data[name] = _defaults()[name]
	changed.emit(name)
	save_settings()

enum HandlingPreset { CASUAL, TOUGE_SPORT, PURIST_SIM, CUSTOM }

func apply_handling_preset(preset: int) -> void:
	match preset:
		HandlingPreset.CASUAL:
			set_value("assists", "abs", true, false)
			set_value("assists", "tcs", true, false)
			set_value("assists", "stm", true, false)
			set_value("assists", "steering", 0, false) # assisted
			set_value("assists", "gearbox", 0, false) # auto
			set_value("assists", "countersteer", 0.8, false)
			set_value("assists", "preset", HandlingPreset.CASUAL, true)
		HandlingPreset.TOUGE_SPORT:
			set_value("assists", "abs", true, false)
			set_value("assists", "tcs", false, false)
			set_value("assists", "stm", false, false)
			set_value("assists", "steering", 1, false) # standard
			set_value("assists", "gearbox", 1, false) # manual
			set_value("assists", "countersteer", 0.45, false)
			set_value("assists", "preset", HandlingPreset.TOUGE_SPORT, true)
		HandlingPreset.PURIST_SIM:
			set_value("assists", "abs", false, false)
			set_value("assists", "tcs", false, false)
			set_value("assists", "stm", false, false)
			set_value("assists", "steering", 2, false) # simulation
			set_value("assists", "gearbox", 2, false) # manual + clutch
			set_value("assists", "countersteer", 0.0, false)
			set_value("assists", "preset", HandlingPreset.PURIST_SIM, true)
		HandlingPreset.CUSTOM:
			set_value("assists", "preset", HandlingPreset.CUSTOM, true)

func assists_dict() -> Dictionary:
	var a := section("assists")
	return {
		"abs": a.abs, "tcs": a.tcs, "stm": a.stm, "steering": a.steering,
		"gearbox": a.gearbox, "countersteer": a.countersteer, "mechanical_damage": a.mechanical_damage,
	}
