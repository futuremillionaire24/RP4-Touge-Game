class_name CarStatsPanel
extends PanelContainer
## Car performance card: name, class/PI badge, stat bars (speed / handling / acceleration /
## launch / braking) and headline numbers. Runs the C++ PI benchmark on a worker thread and
## caches results; a preview build is compared against the current one (green/red deltas).

static var _cache := {} # signature -> benchmark result

signal benchmarked(sig: String, result: Dictionary)

var _name: Label
var _sub: Label
var _badge_holder: HBoxContainer
var _bars := {}
var _nums: Label
var _base := {}
var _preview := {}
var _base_sig := ""
var _preview_sig := ""
var _task := -1
var _task_sig := ""
var _task_args := []
var _task_result := {}
var _queue := [] # [[sig, key, overrides]]

const BARS := [["speed_score", "SPEED"], ["handling_score", "HANDLING"], ["accel_score", "ACCELERATION"],
	["launch_score", "LAUNCH"], ["braking_score", "BRAKING"]]

func _init() -> void:
	custom_minimum_size = Vector2(430, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	_name = UIKit.label("", 24, Color.WHITE)
	names.add_child(_name)
	_sub = UIKit.label("", 16, UIKit.DIM)
	names.add_child(_sub)
	_badge_holder = HBoxContainer.new()
	top.add_child(_badge_holder)
	for b in BARS:
		var row := HBoxContainer.new()
		var l := UIKit.label(b[1], 15, UIKit.DIM)
		l.custom_minimum_size = Vector2(120, 0)
		row.add_child(l)
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(240, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.draw.connect(_draw_bar.bind(bar, b[0]))
		row.add_child(bar)
		var num := UIKit.label("", 15, UIKit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		num.custom_minimum_size = Vector2(40, 0)
		row.add_child(num)
		v.add_child(row)
		_bars[b[0]] = [bar, num]
	_nums = UIKit.label("", 16, UIKit.TEXT)
	v.add_child(_nums)

## Show a car build; `preview_overrides` (optional Dictionary) is compared against it.
func show_build(key: String, overrides: Dictionary, preview_overrides = null) -> void:
	var car := CarData.get_car(key)
	_name.text = car.name
	_sub.text = "%s  ·  %d  ·  %s" % [car.maker, int(car.year), layout_name(key, overrides)]
	_base_sig = sig_of(key, overrides)
	_base = _cache.get(_base_sig, {})
	if _base.is_empty():
		_request(_base_sig, key, overrides)
	_preview_sig = ""
	_preview = {}
	if preview_overrides is Dictionary and sig_of(key, preview_overrides) != _base_sig:
		_preview_sig = sig_of(key, preview_overrides)
		_preview = _cache.get(_preview_sig, {})
		if _preview.is_empty():
			_request(_preview_sig, key, preview_overrides)
	_redraw()

static func layout_name(key: String, overrides: Dictionary) -> String:
	var layout := int(NTSim.car_params(key, overrides).get("layout", 1))
	return ["FR", "FF", "MR", "AWD", "RR"][clampi(layout, 0, 4)]

static func sig_of(key: String, overrides: Dictionary) -> String:
	return key + JSON.stringify(overrides)

static func cached(key: String, overrides: Dictionary) -> Dictionary:
	return _cache.get(sig_of(key, overrides), {})

func _request(sig: String, key: String, overrides: Dictionary) -> void:
	if sig == _task_sig:
		return
	for q in _queue:
		if q[0] == sig:
			return
	# Only the latest preview matters: drop stale queued previews.
	_queue = _queue.filter(func(q): return q[0] == _base_sig)
	_queue.append([sig, key, overrides.duplicate(true)])
	_pump()

func _pump() -> void:
	if _task >= 0 or _queue.is_empty():
		return
	var q: Array = _queue.pop_front()
	_task_sig = q[0]
	_task_args = [q[1], q[2]]
	_task = WorkerThreadPool.add_task(_run_task, false, "PI benchmark")

func _run_task() -> void:
	_task_result = NTSim.benchmark(_task_args[0], _task_args[1])

func _process(_delta: float) -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var sig := _task_sig
	_task_sig = ""
	_cache[sig] = _task_result
	if sig == _base_sig:
		_base = _task_result
	if sig == _preview_sig:
		_preview = _task_result
	benchmarked.emit(sig, _task_result)
	_redraw()
	_pump()

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _redraw() -> void:
	for c in _badge_holder.get_children():
		c.queue_free()
	var r: Dictionary = _preview if not _preview.is_empty() else _base
	for k in _bars:
		_bars[k][0].queue_redraw()
		_bars[k][1].text = "%.1f" % float(r.get(k, 0.0)) if not r.is_empty() else ""
	if r.is_empty():
		_badge_holder.add_child(UIKit.label("PI …", 20, UIKit.DIM))
		_nums.text = "Benchmarking…"
		return
	_badge_holder.add_child(UIKit.class_badge(int(r.pi), 22))
	if not _preview.is_empty() and not _base.is_empty():
		var d := int(_preview.pi) - int(_base.pi)
		if d != 0:
			_badge_holder.add_child(UIKit.label("%+d" % d, 20, UIKit.GREEN if d > 0 else UIKit.RED))
	var t100 := float(r.t_0_100)
	_nums.text = "%d hp   %d kg   0-100 %s   %s" % [roundi(float(r.power_kw) * 1.341), roundi(float(r.weight_kg)),
		("%.2f s" % t100) if t100 < 90.0 else "—", UIKit.speed_str(float(r.top_speed) / 3.6)]

func _draw_bar(bar: Control, key: String) -> void:
	var w := bar.size.x
	var h := bar.size.y
	bar.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.08))
	if _preview.is_empty() or _base.is_empty():
		var r: Dictionary = _preview if not _preview.is_empty() else _base
		bar.draw_rect(Rect2(0, 0, w * clampf(float(r.get(key, 0.0)) / 10.0, 0.0, 1.0), h), UIKit.CYAN)
		return
	var base := clampf(float(_base.get(key, 0.0)) / 10.0, 0.0, 1.0)
	var pv := clampf(float(_preview.get(key, 0.0)) / 10.0, 0.0, 1.0)
	bar.draw_rect(Rect2(0, 0, w * minf(base, pv), h), UIKit.CYAN)
	if pv > base:
		bar.draw_rect(Rect2(w * base, 0, w * (pv - base), h), UIKit.GREEN)
	elif pv < base:
		bar.draw_rect(Rect2(w * pv, 0, w * (base - pv), h), UIKit.RED)
