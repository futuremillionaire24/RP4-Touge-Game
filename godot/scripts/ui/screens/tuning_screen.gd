class_name TuningScreen
extends MenuScreen
## Tuning for one garage car. Pages: Presets, Tyres, Alignment, Springs, Damping, Anti-roll,
## Gearing (with live speed/rpm graph), Differential, Brakes, Aero. Values are absolute native
## overrides stored in the garage entry's "tune"; some pages need race parts installed (as in
## the upgrade shop). Leaving the screen recomputes PI and saves.

const PAGES := ["Presets", "Tyres", "Align", "Springs", "Damping", "ARBs", "Gearing", "Diff", "Brakes", "Aero"]

const SPECS := {
	"Tyres": [
		{"k": "tire_pressure_front", "name": "Pressure front", "min": 1.5, "max": 3.0, "step": 0.05, "fmt": "bar"},
		{"k": "tire_pressure_rear", "name": "Pressure rear", "min": 1.5, "max": 3.0, "step": 0.05, "fmt": "bar"},
	],
	"Align": [
		{"k": "camber_front", "name": "Camber front", "min": -0.0873, "max": 0.0175, "step": 0.001745, "fmt": "deg"},
		{"k": "camber_rear", "name": "Camber rear", "min": -0.0873, "max": 0.0175, "step": 0.001745, "fmt": "deg"},
		{"k": "toe_front", "name": "Toe front", "min": -0.0175, "max": 0.0175, "step": 0.000873, "fmt": "deg"},
		{"k": "toe_rear", "name": "Toe rear", "min": -0.0175, "max": 0.0175, "step": 0.000873, "fmt": "deg"},
		{"k": "caster_trail", "name": "Caster trail", "min": 0.01, "max": 0.07, "step": 0.002, "fmt": "mm"},
	],
	"Springs": [
		{"k": "spring_front", "name": "Spring rate front", "rel": [0.5, 2.2], "fmt": "nmm", "req": ["springs", 1]},
		{"k": "spring_rear", "name": "Spring rate rear", "rel": [0.5, 2.2], "fmt": "nmm", "req": ["springs", 1]},
		{"k": "mount_height", "name": "Ride height", "off": [-0.05, 0.04], "step": 0.002, "fmt": "mm_rel", "req": ["springs", 1]},
	],
	"Damping": [
		{"k": "bump_front", "name": "Bump front", "rel": [0.5, 2.0], "fmt": "pct_base", "req": ["springs", 2]},
		{"k": "bump_rear", "name": "Bump rear", "rel": [0.5, 2.0], "fmt": "pct_base", "req": ["springs", 2]},
		{"k": "rebound_front", "name": "Rebound front", "rel": [0.5, 2.0], "fmt": "pct_base", "req": ["springs", 2]},
		{"k": "rebound_rear", "name": "Rebound rear", "rel": [0.5, 2.0], "fmt": "pct_base", "req": ["springs", 2]},
	],
	"ARBs": [
		{"k": "arb_front", "name": "Anti-roll front", "rel": [0.0, 2.5], "fmt": "pct_base", "req": ["arb", 1]},
		{"k": "arb_rear", "name": "Anti-roll rear", "rel": [0.0, 2.5], "fmt": "pct_base", "req": ["arb", 1]},
	],
	"Gearing": [
		{"k": "final_drive", "name": "Final drive", "min": 2.2, "max": 6.5, "step": 0.02, "fmt": "ratio", "req": ["gearbox", 1]},
	],
	"Diff": [
		{"k": "lsd_accel", "name": "Acceleration lock", "min": 0.0, "max": 1.0, "step": 0.02, "fmt": "pct", "req": ["diff", 1]},
		{"k": "lsd_decel", "name": "Deceleration lock", "min": 0.0, "max": 1.0, "step": 0.02, "fmt": "pct", "req": ["diff", 1]},
		{"k": "lsd_preload", "name": "Preload", "min": 0.0, "max": 300.0, "step": 5.0, "fmt": "nm", "req": ["diff", 1]},
		{"k": "awd_front_split", "name": "AWD front split", "min": 0.1, "max": 0.7, "step": 0.01, "fmt": "pct", "req": ["diff", 1], "awd": true},
	],
	"Brakes": [
		{"k": "brake_bias", "name": "Balance (front)", "min": 0.45, "max": 0.78, "step": 0.01, "fmt": "pct"},
		{"k": "brake_torque", "name": "Pressure", "rel": [0.7, 1.3], "fmt": "pct_base"},
	],
	"Aero": [
		{"k": "lift_front", "name": "Front downforce", "rel": [0.4, 1.6], "fmt": "pct_base", "req": ["aero", 1]},
		{"k": "lift_rear", "name": "Rear downforce", "rel": [0.4, 1.6], "fmt": "pct_base", "req": ["aero", 1]},
	],
}

var index := 0
var _page := 1
var _tabs: HBoxContainer
var _list: VBoxContainer
var _note: Label
var _graph: Control
var _base := {} # untuned values for the installed parts
var _dirty := false

func _init(garage_index := 0) -> void:
	super._init()
	index = garage_index

func _entry() -> Dictionary:
	return Profile.data.garage[index]

func build() -> void:
	var e := _entry()
	var col := make_column(580)
	col.add_child(UIKit.header("Race Tuning", "", CarData.get_car(e.key).name))
	_tabs = make_tabs(col, PAGES)
	for c in _tabs.get_children():
		for sub_lbl in c.get_children():
			if sub_lbl is Label:
				sub_lbl.add_theme_font_size_override("font_size", 13)
	_list = make_list(col, 420)
	_note = UIKit.label("", 17, UIKit.DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(560, 0)
	col.add_child(_note)
	_graph = Control.new()
	_graph.position = Vector2(670, 180)
	_graph.size = Vector2(610, 360)
	_graph.draw.connect(_draw_gearing)
	_graph.visible = false
	add_child(_graph)
	set_hints([["◀▶", "Adjust"], ["X", "Reset page"], ["L1", ""], ["R1", "Page"], ["B", "Save & back"]])
	_base = NTSim.car_params(e.key, UpgradeData.build_overrides(e.key, e.upgrades, {}))
	stage.show_entry(e)

func refresh() -> void:
	highlight_tabs(_tabs, _page)
	for c in _list.get_children():
		c.queue_free()
	var page: String = PAGES[_page]
	_graph.visible = page == "Gearing"
	_graph.queue_redraw()
	_note.text = ""
	var first: UIRow = null
	if page == "Presets":
		first = _build_presets()
	else:
		for spec in _page_specs(page):
			var row := UIRow.new(spec.name)
			var ok := _available(spec)
			_list.add_child(row)
			if ok:
				row.on_adjust = _adjust.bind(row, spec)
				_update_row(row, spec)
			else:
				row.set_value("Needs %s" % _req_name(spec), UIKit.DIM)
				row.on_accept = func(): festival.toast("INSTALL %s IN UPGRADES TO TUNE THIS" % _req_name(spec).to_upper())
			if first == null:
				first = row
		if page == "Gearing" and not _available(_page_specs(page)[0]):
			_note.text = "Install a Sport transmission to tune the final drive, Race or better for individual gears."
	if first and is_inside_tree():
		first.call_deferred("grab_focus")

func _page_specs(page: String) -> Array:
	var specs: Array = SPECS.get(page, []).duplicate()
	if page == "Diff" and int(_base.get("layout", 1)) != 3:
		specs = specs.filter(func(s): return not s.get("awd", false))
	if page == "Gearing":
		for g in range(int(_base.get("gear_count", 5))):
			var k := "gear_%d" % (g + 1)
			var b := float(_base.get(k, 1.0))
			specs.append({"k": k, "name": "Gear %d" % (g + 1), "min": b * 0.7, "max": b * 1.35, "step": 0.01, "fmt": "ratio", "req": ["gearbox", 2]})
	return specs

func _available(spec: Dictionary) -> bool:
	if not spec.has("req"):
		return true
	return int(_entry().upgrades.get(spec.req[0], 0)) >= int(spec.req[1])

func _req_name(spec: Dictionary) -> String:
	for cat in UpgradeData.CATEGORIES:
		if cat.id == spec.req[0]:
			return "%s %s" % [cat.levels[int(spec.req[1])].name, cat.name]
	return "upgrade"

func _range(spec: Dictionary) -> Vector2:
	var b := float(_base.get(spec.k, 0.0))
	if spec.has("rel"):
		return Vector2(b * spec.rel[0], b * spec.rel[1])
	if spec.has("off"):
		return Vector2(b + spec.off[0], b + spec.off[1])
	return Vector2(spec.min, spec.max)

func _step(spec: Dictionary) -> float:
	if spec.has("step"):
		return spec.step
	var r := _range(spec)
	return maxf((r.y - r.x) / 60.0, 0.0001)

func _value(spec: Dictionary) -> float:
	return float(_entry().tune.get(spec.k, _base.get(spec.k, 0.0)))

func _adjust(dir: int, row: UIRow, spec: Dictionary) -> void:
	var r := _range(spec)
	var v := clampf(_value(spec) + dir * _step(spec), r.x, r.y)
	var b := float(_base.get(spec.k, 0.0))
	if absf(v - b) < _step(spec) * 0.5:
		_entry().tune.erase(spec.k)
	else:
		_entry().tune[spec.k] = v
	_dirty = true
	_update_row(row, spec)
	_graph.queue_redraw()

func _update_row(row: UIRow, spec: Dictionary) -> void:
	var v := _value(spec)
	var b := float(_base.get(spec.k, 0.0))
	var r := _range(spec)
	var changed: bool = _entry().tune.has(spec.k)
	row.set_value(_fmt(spec, v, b), UIKit.AMBER if changed else UIKit.CYAN)
	var span := maxf(r.y - r.x, 0.00001)
	row.set_fraction((v - r.x) / span, (b - r.x) / span)

func _fmt(spec: Dictionary, v: float, b: float) -> String:
	match spec.fmt:
		"bar": return "%.2f bar" % v
		"deg": return "%.1f°" % rad_to_deg(v)
		"mm": return "%d mm" % roundi(v * 1000.0)
		"nmm": return "%d N/mm" % roundi(v / 1000.0)
		"mm_rel": return "%+d mm" % roundi((v - b) * 1000.0) if absf(v - b) > 0.0005 else "base"
		"pct_base": return "%d%%" % roundi(v / maxf(b, 0.0001) * 100.0) if b > 0.0 else "%.2f" % v
		"pct": return "%d%%" % roundi(v * 100.0)
		"nm": return "%d Nm" % roundi(v)
		"ratio": return "%.2f" % v
	return "%.2f" % v

func action_x() -> void:
	var page: String = PAGES[_page]
	for spec in _page_specs(page):
		_entry().tune.erase(spec.k)
	_dirty = true
	festival.toast("%s RESET TO BASE" % page.to_upper())
	refresh()

func tab(dir: int) -> void:
	_page = wrapi(_page + dir, 0, PAGES.size())
	refresh()

func back() -> void:
	if _dirty:
		var e := _entry()
		e.pi = Profile.compute_pi(e)
		Profile.save()
		festival.toast("TUNE SAVED  ·  %s" % CarData.class_label(int(e.pi)))
	super.back()

# ---- Presets ------------------------------------------------------------------------------------

const PRESETS := [
	["Grip", "Balanced street/circuit setup: moderate negative camber, even pressures.",
		{"camber_front": -0.035, "camber_rear": -0.026, "toe_rear": 0.0017, "tire_pressure_front": 2.05, "tire_pressure_rear": 2.05,
		"lsd_accel": 0.35, "lsd_decel": 0.2, "brake_bias": 0.62}],
	["Drift", "Lots of front camber, harder rear, locked diff and rearward brakes for easy slides.",
		{"camber_front": -0.07, "camber_rear": -0.009, "toe_front": 0.0009, "tire_pressure_front": 2.2, "tire_pressure_rear": 2.6,
		"lsd_accel": 0.9, "lsd_decel": 0.8, "lsd_preload": 160.0, "*arb_rear": 1.4, "*arb_front": 0.9, "*spring_rear": 1.15, "brake_bias": 0.57, "*final_drive": 1.08}],
	["Rally", "Raised, softer suspension and lower pressures for gravel, dirt and snow.",
		{"+mount_height": 0.03, "*spring_front": 0.75, "*spring_rear": 0.75, "*bump_front": 0.8, "*bump_rear": 0.8, "*rebound_front": 0.85, "*rebound_rear": 0.85,
		"*arb_front": 0.7, "*arb_rear": 0.7, "tire_pressure_front": 1.8, "tire_pressure_rear": 1.8, "lsd_accel": 0.5, "lsd_decel": 0.3, "camber_front": -0.017, "camber_rear": -0.01}],
	["Top Speed", "Long gearing, lower ride and trimmed downforce for the Wangan.",
		{"*final_drive": 0.88, "*lift_front": 0.6, "*lift_rear": 0.6, "+mount_height": -0.015, "tire_pressure_front": 2.4, "tire_pressure_rear": 2.4, "toe_front": 0.0, "toe_rear": 0.0}],
]

func _build_presets() -> UIRow:
	var first: UIRow = null
	for p in PRESETS:
		var row := UIRow.new(p[0].to_upper())
		row.on_focus = func(): _note.text = p[1] + "  Only tunes your installed parts allow are changed."
		row.on_accept = _apply_preset.bind(p)
		_list.add_child(row)
		if first == null:
			first = row
	var reset := UIRow.new("RESET ALL TO BASE")
	reset.on_focus = func(): _note.text = "Clears every tuning change on this car."
	reset.on_accept = func():
		_entry().tune.clear()
		_dirty = true
		festival.toast("TUNE CLEARED")
	_list.add_child(reset)
	return first

func _apply_preset(p: Array) -> void:
	var allowed := {}
	for page in SPECS:
		for spec in _page_specs(page):
			if _available(spec):
				allowed[spec.k] = spec
	var n := 0
	for raw in p[2]:
		var k: String = raw.trim_prefix("*").trim_prefix("+")
		if not allowed.has(k):
			continue
		var b := float(_base.get(k, 0.0))
		var v: float = p[2][raw]
		if raw.begins_with("*"):
			v = b * v
		elif raw.begins_with("+"):
			v = b + v
		var r := _range(allowed[k])
		_entry().tune[k] = clampf(v, r.x, r.y)
		n += 1
	_dirty = true
	festival.toast("%s PRESET APPLIED  ·  %d SETTINGS" % [p[0].to_upper(), n])

# ---- Gearing graph ------------------------------------------------------------------------------

func _draw_gearing() -> void:
	var w := _graph.size.x
	var h := _graph.size.y
	_graph.draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.015, 0.06, 0.88))
	_graph.draw_string(ThemeDB.fallback_font, Vector2(12, 22), "SPEED / RPM PER GEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIKit.DIM)
	var redline := float(_base.get("redline_rpm", 7000.0))
	var radius := float(_base.get("wheel_radius_rear", 0.31))
	var fd := float(_entry().tune.get("final_drive", _base.get("final_drive", 4.0)))
	var n := int(_base.get("gear_count", 5))
	var vmax := 0.0
	var speeds := []
	for g in range(n):
		var k := "gear_%d" % (g + 1)
		var ratio := float(_entry().tune.get(k, _base.get(k, 1.0)))
		var v := redline / 60.0 * TAU / maxf(ratio * fd, 0.01) * radius # m/s at redline
		speeds.append(v)
		vmax = maxf(vmax, v)
	vmax = maxf(vmax, 1.0)
	var x0 := 40.0
	var y0 := h - 30.0
	var gw := w - x0 - 16.0
	var gh := y0 - 40.0
	for i in range(0, 5):
		var yy := y0 - gh * i / 4.0
		_graph.draw_line(Vector2(x0, yy), Vector2(x0 + gw, yy), Color(1, 1, 1, 0.06))
	for g in range(n):
		var v: float = speeds[g]
		var prev_v: float = speeds[g - 1] if g > 0 else 0.0
		# From the previous gear's redline speed (shift point) up to this gear's redline.
		var rpm_at_prev := redline * prev_v / v if v > 0.0 else 0.0
		var a := Vector2(x0 + gw * prev_v / vmax, y0 - gh * rpm_at_prev / redline)
		var b := Vector2(x0 + gw * v / vmax, y0 - gh)
		var col := UIKit.NEON.lerp(UIKit.CYAN, float(g) / maxf(1.0, n - 1.0))
		_graph.draw_line(Vector2(x0, y0) if g == 0 else a, b, col, 2.0, true)
		_graph.draw_string(ThemeDB.fallback_font, b + Vector2(-8, -6), str(g + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	var top_label := UIKit.speed_str(vmax)
	_graph.draw_string(ThemeDB.fallback_font, Vector2(x0 + gw - 110, h - 8), "max %s" % top_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.TEXT)
	_graph.draw_string(ThemeDB.fallback_font, Vector2(4, 50), "%dk" % roundi(redline / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.DIM)
