extends Node
## QA physics: exports override dictionaries built by the real UpgradeData.build_overrides /
## tuning-range logic for every scenario, plus NTSim.benchmark PI for each, to a text file the
## native probe (build/qa/physics/probe.cpp) replays. One line per scenario:
## name \t key \t k=v;k=v;... \t pi_from_godot

const OUT := "D:/Android_RP4_Game/build/qa/physics/scenarios.txt"

var lines := PackedStringArray()

func _ready() -> void:
	var keys := NTSim.car_keys()
	for key in keys:
		_add("stock", key, {}, {})
		# Every single upgrade level.
		for cat in UpgradeData.CATEGORIES:
			for lvl in range(1, cat.levels.size()):
				_add("up:%s:%d" % [cat.id, lvl], key, {cat.id: lvl}, {})
		# Engine swaps.
		for s in range(1, UpgradeData.SWAPS.get(key, []).size() + 1):
			_add("swap:%d:%s" % [s, UpgradeData.swap_donor_key(key, s)], key, {"swap": s}, {})
		# Engine-only max (all engine parts max) +/- swaps.
		var eng := {"intake": 3, "exhaust": 3, "cams": 3, "ecu": 2, "forced": 3, "displacement": 2}
		_add("engine_max", key, eng, {})
		for s in range(1, 4):
			var u := eng.duplicate()
			u["swap"] = s
			_add("engine_max+swap:%d" % s, key, u, {})
		# Full build (semi-slicks, sport LSD, race everything).
		var full := {"intake": 3, "exhaust": 3, "cams": 3, "ecu": 2, "forced": 3, "displacement": 2, "clutch": 2,
			"gearbox": 3, "diff": 2, "compound": 2, "width": 3, "brakes": 3, "springs": 3, "arb": 2, "weight": 3, "aero": 2}
		_add("full", key, full, {})
		var full_awd := full.duplicate()
		full_awd["awd"] = 1
		_add("full+awd", key, full_awd, {})
		for s in range(1, 4):
			var u := full.duplicate()
			u["swap"] = s
			_add("full+swap:%d" % s, key, u, {})
		# Handling-only build (no power) -- PI should rise.
		var chassis := {"compound": 2, "width": 3, "brakes": 3, "springs": 3, "arb": 2, "weight": 3, "aero": 2}
		_add("chassis_max", key, chassis, {})
		# Tuning extremes on the full build (every tune page unlocked).
		var base: Dictionary = NTSim.car_params(key, UpgradeData.build_overrides(key, full, {}))
		for page in TuningScreen.SPECS:
			for spec in _page_specs(page, base):
				var r := _range(spec, base)
				_add("tune:%s:min" % spec.k, key, full, {spec.k: r.x})
				_add("tune:%s:max" % spec.k, key, full, {spec.k: r.y})
		# Presets.
		for p in TuningScreen.PRESETS:
			_add("preset:%s" % p[0], key, full, _preset(p, base))
		# Stock-car presets (only unlocked specs apply) to catch presets doing nothing.
		var sbase: Dictionary = NTSim.car_params(key, {})
		for p in TuningScreen.PRESETS:
			_add("stock_preset:%s" % p[0], key, {}, _preset(p, sbase, {}))
		# Combined extremes.
		var tall := {"final_drive": 2.2}
		var short := {"final_drive": 6.5}
		for g in range(int(base.gear_count)):
			var b := float(base["gear_%d" % (g + 1)])
			tall["gear_%d" % (g + 1)] = b * 0.7
			short["gear_%d" % (g + 1)] = b * 1.35
		_add("combo:all_tall", key, full, tall)
		_add("combo:all_short", key, full, short)
		_add("combo:slammed_soft_aero", key, full, {"mount_height": float(base.mount_height) - 0.05,
			"spring_front": float(base.spring_front) * 0.5, "spring_rear": float(base.spring_rear) * 0.5,
			"bump_front": float(base.bump_front) * 0.5, "bump_rear": float(base.bump_rear) * 0.5,
			"lift_front": float(base.lift_front) * 1.6, "lift_rear": float(base.lift_rear) * 1.6})
		_add("combo:high_soft", key, full, {"mount_height": float(base.mount_height) + 0.04,
			"spring_front": float(base.spring_front) * 0.5, "spring_rear": float(base.spring_rear) * 0.5,
			"arb_front": 0.0, "arb_rear": 0.0})
		_add("combo:brake_rear_all", key, full, {"brake_bias": 0.45, "brake_torque": float(base.brake_torque) * 1.3})
		_add("combo:toe_out_rear", key, full, {"toe_rear": -0.0175, "toe_front": 0.0175})
		_add("combo:diff_zero", key, full, {"lsd_accel": 0.0, "lsd_decel": 0.0, "lsd_preload": 0.0})
		_add("combo:diff_full", key, full, {"lsd_accel": 1.0, "lsd_decel": 1.0, "lsd_preload": 300.0})
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("QA_GEN wrote %d scenarios" % lines.size())
	get_tree().quit()

func _add(name: String, key: String, upgrades: Dictionary, tune: Dictionary) -> void:
	var ov := UpgradeData.build_overrides(key, upgrades, tune)
	var parts := PackedStringArray()
	for k in ov:
		parts.append("%s=%s" % [k, String.num(float(ov[k]), 10)])
	var pi := -1
	if name == "stock" or name.begins_with("full") or name == "engine_max":
		pi = int(NTSim.benchmark(key, ov).pi)
	lines.append("%s\t%s\t%s\t%d" % [name, key, ";".join(parts), pi])

# Mirrors TuningScreen._page_specs / _range (the full build unlocks every requirement).
func _page_specs(page: String, base: Dictionary) -> Array:
	var specs: Array = TuningScreen.SPECS.get(page, []).duplicate()
	if page == "Differential" and int(base.get("layout", 1)) != 3:
		specs = specs.filter(func(s): return not s.get("awd", false))
	if page == "Gearing":
		for g in range(int(base.get("gear_count", 5))):
			var k := "gear_%d" % (g + 1)
			var b := float(base.get(k, 1.0))
			specs.append({"k": k, "name": "Gear %d" % (g + 1), "min": b * 0.7, "max": b * 1.35, "step": 0.01, "fmt": "ratio", "req": ["gearbox", 2]})
	return specs

func _range(spec: Dictionary, base: Dictionary) -> Vector2:
	var b := float(base.get(spec.k, 0.0))
	if spec.has("rel"):
		return Vector2(b * spec.rel[0], b * spec.rel[1])
	if spec.has("off"):
		return Vector2(b + spec.off[0], b + spec.off[1])
	return Vector2(spec.min, spec.max)

func _preset(p: Array, base: Dictionary, upgrades = null) -> Dictionary:
	var allowed := {}
	for page in TuningScreen.SPECS:
		for spec in _page_specs(page, base):
			if upgrades is Dictionary and spec.has("req") and int(upgrades.get(spec.req[0], 0)) < int(spec.req[1]):
				continue
			allowed[spec.k] = spec
	var tune := {}
	for raw in p[2]:
		var k: String = raw.trim_prefix("*").trim_prefix("+")
		if not allowed.has(k):
			continue
		var b := float(base.get(k, 0.0))
		var v: float = p[2][raw]
		if raw.begins_with("*"):
			v = b * v
		elif raw.begins_with("+"):
			v = b + v
		var r := _range(allowed[k], base)
		tune[k] = clampf(v, r.x, r.y)
	return tune
