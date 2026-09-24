class_name UpgradeData
extends RefCounted
## Upgrade catalogue. Each category has levels (0 = stock). Each level maps to physics overrides
## applied by the native roster (apply_override) and a price. Tuning values are layered on top.

const CATEGORIES := [
	{"id": "intake", "name": "Intake", "group": "Engine", "levels": [
		{"name": "Stock"}, {"name": "Street", "price": 1800, "mul": {"torque_scale": 1.03}},
		{"name": "Sport", "price": 4200, "mul": {"torque_scale": 1.05}}, {"name": "Race", "price": 9000, "mul": {"torque_scale": 1.08}}]},
	{"id": "exhaust", "name": "Exhaust", "group": "Engine", "levels": [
		{"name": "Stock"}, {"name": "Street", "price": 2200, "mul": {"torque_scale": 1.03}},
		{"name": "Sport", "price": 5000, "mul": {"torque_scale": 1.05}}, {"name": "Race", "price": 11000, "mul": {"torque_scale": 1.07}}]},
	{"id": "cams", "name": "Camshafts", "group": "Engine", "levels": [
		{"name": "Stock"}, {"name": "Street", "price": 3000, "add": {"torque_top_end": 0.10, "redline_rpm": 250, "limiter_rpm": 250}},
		{"name": "Sport", "price": 7500, "add": {"torque_top_end": 0.18, "redline_rpm": 500, "limiter_rpm": 500}},
		{"name": "Race", "price": 16000, "add": {"torque_top_end": 0.28, "redline_rpm": 800, "limiter_rpm": 800}}]},
	{"id": "ecu", "name": "ECU", "group": "Engine", "levels": [
		{"name": "Stock"}, {"name": "Sport", "price": 3500, "mul": {"torque_scale": 1.04}}, {"name": "Race", "price": 9500, "mul": {"torque_scale": 1.08}}]},
	{"id": "forced", "name": "Forced Induction", "group": "Engine", "levels": [
		{"name": "Stock"}, {"name": "Street Turbo", "price": 12000, "add": {"max_boost": 0.3}, "turbo": true},
		{"name": "Sport Turbo", "price": 24000, "add": {"max_boost": 0.55}, "turbo": true},
		{"name": "Race Turbo", "price": 42000, "add": {"max_boost": 0.9, "spool_rpm": 700}, "turbo": true}]},
	{"id": "displacement", "name": "Displacement", "group": "Engine", "levels": [
		{"name": "Stock"}, {"name": "Stroker", "price": 14000, "mul": {"torque_scale": 1.1, "mass": 1.01}},
		{"name": "Big Bore", "price": 28000, "mul": {"torque_scale": 1.18, "mass": 1.02}}]},
	{"id": "clutch", "name": "Clutch", "group": "Drivetrain", "levels": [
		{"name": "Stock"}, {"name": "Sport", "price": 1500, "mul": {"clutch_torque": 1.35, "engine_inertia": 0.95}},
		{"name": "Race", "price": 4000, "mul": {"clutch_torque": 1.9, "engine_inertia": 0.85}}]},
	{"id": "gearbox", "name": "Transmission", "group": "Drivetrain", "levels": [
		{"name": "Stock"}, {"name": "Sport", "price": 6000, "mul": {"shift_time": 0.7}},
		{"name": "Race", "price": 14000, "mul": {"shift_time": 0.45}}, {"name": "Sequential", "price": 26000, "mul": {"shift_time": 0.28}}]},
	{"id": "diff", "name": "Differential", "group": "Drivetrain", "levels": [
		{"name": "Stock"}, {"name": "Street LSD", "price": 2500, "set": {"diff_rear": 1}, "add": {"lsd_accel": 0.08}},
		{"name": "Sport LSD", "price": 5500, "set": {"diff_rear": 1}, "add": {"lsd_accel": 0.15, "lsd_decel": 0.1}},
		{"name": "Drift LSD", "price": 8000, "set": {"diff_rear": 1}, "add": {"lsd_accel": 0.3, "lsd_decel": 0.25, "lsd_preload": 60}}]},
	{"id": "awd", "name": "Drivetrain Swap", "group": "Drivetrain", "levels": [
		{"name": "Stock"}, {"name": "AWD Conversion", "price": 38000, "set": {"layout": 3, "awd_front_split": 0.35, "diff_front": 1}, "mul": {"mass": 1.05}}]},
	{"id": "compound", "name": "Tyre Compound", "group": "Tyres", "levels": [
		{"name": "Stock"}, {"name": "Sport", "price": 2500, "set": {"tire_compound": 1}},
		{"name": "Semi-Slick", "price": 6500, "set": {"tire_compound": 2}}, {"name": "Drift", "price": 4000, "set": {"tire_compound": 3}},
		{"name": "Rally", "price": 4500, "set": {"tire_compound": 4}}, {"name": "Snow", "price": 3500, "set": {"tire_compound": 5}}]},
	{"id": "width", "name": "Tyre Width", "group": "Tyres", "levels": [
		{"name": "Stock"}, {"name": "+10 mm", "price": 1200, "add": {"tire_width_front": 0.01, "tire_width_rear": 0.01}},
		{"name": "+20 mm", "price": 2400, "add": {"tire_width_front": 0.02, "tire_width_rear": 0.02}},
		{"name": "+30 mm", "price": 3800, "add": {"tire_width_front": 0.03, "tire_width_rear": 0.03}}]},
	{"id": "brakes", "name": "Brakes", "group": "Chassis", "levels": [
		{"name": "Stock"}, {"name": "Street", "price": 2000, "mul": {"brake_torque": 1.15}},
		{"name": "Sport", "price": 4800, "mul": {"brake_torque": 1.3}}, {"name": "Race", "price": 10500, "mul": {"brake_torque": 1.5}}]},
	{"id": "springs", "name": "Springs & Dampers", "group": "Chassis", "levels": [
		{"name": "Stock"}, {"name": "Street", "price": 2500, "mul": {"spring_front": 1.15, "spring_rear": 1.15, "bump_front": 1.1, "bump_rear": 1.1, "rebound_front": 1.1, "rebound_rear": 1.1}, "add": {"mount_height": -0.01}},
		{"name": "Sport", "price": 6000, "mul": {"spring_front": 1.3, "spring_rear": 1.3, "bump_front": 1.2, "bump_rear": 1.2, "rebound_front": 1.2, "rebound_rear": 1.2}, "add": {"mount_height": -0.02}},
		{"name": "Race", "price": 12000, "mul": {"spring_front": 1.5, "spring_rear": 1.5, "bump_front": 1.35, "bump_rear": 1.35, "rebound_front": 1.35, "rebound_rear": 1.35}, "add": {"mount_height": -0.03}}]},
	{"id": "arb", "name": "Anti-Roll Bars", "group": "Chassis", "levels": [
		{"name": "Stock"}, {"name": "Sport", "price": 1800, "mul": {"arb_front": 1.25, "arb_rear": 1.25}}, {"name": "Race", "price": 4200, "mul": {"arb_front": 1.6, "arb_rear": 1.6}}]},
	{"id": "weight", "name": "Weight Reduction", "group": "Chassis", "levels": [
		{"name": "Stock"}, {"name": "Street", "price": 3000, "mul": {"mass": 0.96}}, {"name": "Sport", "price": 8000, "mul": {"mass": 0.92, "cg_height": 0.98}},
		{"name": "Race", "price": 18000, "mul": {"mass": 0.87, "cg_height": 0.96}}]},
	{"id": "aero", "name": "Aero", "group": "Aero", "levels": [
		{"name": "Stock"}, {"name": "Street Kit", "price": 4000, "add": {"lift_front": 0.12, "lift_rear": 0.18, "drag_area": 0.02}},
		{"name": "Race Wing", "price": 11000, "add": {"lift_front": 0.3, "lift_rear": 0.5, "drag_area": 0.05}}]},
]

## Engine swap options per car (donor keys). Level 0 = original engine.
const SWAPS := {
	"abarth_500": ["golf_gti", "bmw_m3_e30", "audi_quattro"],
	"golf_gti": ["audi_quattro", "bmw_m4", "audi_r8"],
	"bmw_m3_e30": ["bmw_m4", "porsche_930", "lambo_svj"],
	"porsche_930": ["porsche_992", "ferrari_f40", "porsche_918"],
	"jaguar_etype": ["jaguar_ftype", "jaguar_xj220", "ferrari_testarossa"],
	"mb_300sl": ["mb_g63", "bmw_m4", "ferrari_testarossa"],
	"defender_90": ["mb_g63", "jaguar_ftype", "bmw_m4"],
	"audi_quattro": ["audi_r8", "porsche_992", "jaguar_xj220"],
	"jaguar_ftype": ["jaguar_xj220", "audi_r8", "lambo_svj"],
	"mb_g63": ["jaguar_ftype", "lambo_svj", "audi_r8"],
	"bmw_m4": ["audi_r8", "jaguar_ftype", "ferrari_f40"],
	"audi_r8": ["lambo_svj", "porsche_992", "ferrari_laferrari"],
	"porsche_992": ["porsche_918", "ferrari_f40", "audi_r8"],
	"ferrari_testarossa": ["ferrari_f40", "lambo_svj", "ferrari_laferrari"],
	"ferrari_f40": ["ferrari_laferrari", "lambo_svj", "porsche_918"],
	"lambo_svj": ["ferrari_laferrari", "porsche_918", "audi_r8"],
	"jaguar_xj220": ["ferrari_f40", "lambo_svj", "porsche_992"],
	"porsche_918": ["ferrari_laferrari", "lambo_svj", "porsche_992"],
	"ferrari_laferrari": ["lambo_svj", "porsche_918", "ferrari_f40"],
}
const SWAP_PRICE := [0, 30000, 45000, 65000]

## Native override dictionary for a car build. Order matters (dictionaries keep insertion order):
## engine swap -> set -> turbo conversion -> "*"/"+" stacking -> torque shaping -> tuning.
## Keys prefixed "*" multiply and "+" add to the current native value (see roster.cpp).
static func build_overrides(key: String, upgrades: Dictionary, tune: Dictionary) -> Dictionary:
	var out := {}
	var swap_donor := swap_donor_key(key, int(upgrades.get("swap", 0)))
	if swap_donor != "":
		out["engine_swap"] = NTSim.car_keys().find(swap_donor)
	var engine_key := swap_donor if swap_donor != "" else key
	var mul := {}
	var add := {}
	for cat in CATEGORIES:
		var lvl: int = int(upgrades.get(cat.id, 0))
		if lvl <= 0 or lvl >= cat.levels.size():
			continue
		var L: Dictionary = cat.levels[lvl]
		for k in L.get("set", {}):
			out[k] = L.set[k]
		if L.get("turbo", false) and not _is_boosted(engine_key):
			out["engine_kind"] = 1 # NA -> turbo conversion
			out["spool_rpm"] = 3400.0
			out["spool_rate"] = 2.4
			out["boost_gain"] = 0.55
		for k in L.get("mul", {}):
			mul[k] = float(mul.get(k, 1.0)) * float(L.mul[k])
		for k in L.get("add", {}):
			add[k] = float(add.get(k, 0.0)) + float(L.add[k])
	for k in mul:
		if k == "torque_scale":
			out["torque_scale"] = mul[k]
		else:
			out["*" + k] = mul[k]
	for k in add:
		if k == "torque_top_end":
			continue
		out["+" + k] = add[k]
	if add.has("torque_top_end"):
		out["torque_top_end"] = add.torque_top_end # after redline changes
	var valid_tune := tune.duplicate()
	if not upgrades.has("aero") or int(upgrades.aero) < 1:
		valid_tune.erase("lift_front")
		valid_tune.erase("lift_rear")
	if not upgrades.has("gearbox") or int(upgrades.gearbox) < 1:
		valid_tune.erase("final_drive")
		for g in range(1, 9):
			valid_tune.erase("gear_%d" % g)
	if not upgrades.has("arb") or int(upgrades.arb) < 1:
		valid_tune.erase("arb_front")
		valid_tune.erase("arb_rear")
	if not upgrades.has("diff") or int(upgrades.diff) < 1:
		valid_tune.erase("lsd_accel")
		valid_tune.erase("lsd_decel")
		valid_tune.erase("lsd_preload")
		valid_tune.erase("awd_front_split")
	for k in valid_tune:
		out[k] = valid_tune[k]
	return out

static func swap_donor_key(key: String, swap: int) -> String:
	var list: Array = SWAPS.get(key, [])
	if swap <= 0 or swap > list.size():
		return ""
	return list[swap - 1]

static func _is_boosted(engine_key: String) -> bool:
	# Stock forced induction (turbo 1, rotary-turbo 2, hybrid 4 count as boosted).
	var p: Dictionary = NTSim.car_params(engine_key, {})
	return float(p.get("max_boost", 0.0)) > 0.05

## Profile garage entry -> overrides (entry: {key, upgrades, tune, ...}).
static func overrides_for(entry: Dictionary) -> Dictionary:
	return build_overrides(entry.get("key", CarData.DEFAULT_KEY), entry.get("upgrades", {}), entry.get("tune", {}))

static func price_of(cat_id: String, level: int) -> int:
	for cat in CATEGORIES:
		if cat.id == cat_id and level < cat.levels.size():
			return int(cat.levels[level].get("price", 0))
	return 0

static func level_name(cat_id: String, level: int) -> String:
	for cat in CATEGORIES:
		if cat.id == cat_id and level < cat.levels.size():
			return cat.levels[level].name
	return ""
