extends Node
## Frame-time monitor + quality governor. Holds 60 FPS by moving the 3D render scale between
## the resolution floor and the supersampling ceiling, then stepping effect tiers. On device it
## also reads thermal headroom from the RP4Bridge Android plugin to act before throttling.

signal tier_changed(level: int)

const WINDOW := 90
var frame_ms := PackedFloat32Array()
var _idx := 0
var fps := 60.0
var avg_ms := 16.6
var low1_ms := 16.6 # 99th percentile frame time
var scale := 1.0
var level := 0 # 0 = full effects; each step trims one effect tier
var thermal := -1.0 # 0 cool .. 1 throttling; -1 unknown
var battery := -1.0
var enabled := true
var _bridge: Object = null
var _cooldown := 0.0
var _thermal_timer := 0.0
var _viewport: Viewport

func _ready() -> void:
	frame_ms.resize(WINDOW)
	frame_ms.fill(16.6)
	if Engine.has_singleton("RP4Bridge"):
		_bridge = Engine.get_singleton("RP4Bridge")
		_bridge.call("setSustainedPerformance", true)
		_bridge.call("startHintSession", 16_666_666)
	_viewport = get_viewport()
	if _viewport:
		RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	tier_changed.connect(_on_tier_changed)
	_apply_fps_target()
	Settings.changed.connect(func(sec): if sec == "graphics": _apply_fps_target())

func _apply_fps_target() -> void:
	var target: int = Settings.get_value("graphics", "fps_target", 60)
	Engine.max_fps = 0 if target >= 60 else target
	if _bridge:
		_bridge.call("startHintSession", int(1_000_000_000.0 / float(target)))

func target_ms() -> float:
	return 1000.0 / float(Settings.get_value("graphics", "fps_target", 60))

func _process(delta: float) -> void:
	var ms := delta * 1000.0
	frame_ms[_idx] = ms
	_idx = (_idx + 1) % WINDOW
	var sum := 0.0
	for v in frame_ms:
		sum += v
	avg_ms = sum / WINDOW
	fps = 1000.0 / maxf(avg_ms, 0.1)
	if _bridge:
		_bridge.call("reportFrameTime", int(ms * 1_000_000.0))
		_thermal_timer -= delta
		if _thermal_timer <= 0.0:
			_thermal_timer = 1.0
			thermal = float(_bridge.call("thermalHeadroom"))
			battery = float(_bridge.call("batteryLevel"))
	if enabled and Settings.get_value("graphics", "dynamic_resolution", true):
		_govern(delta)

func _govern(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var sorted := frame_ms.duplicate()
	sorted.sort()
	low1_ms = sorted[int(WINDOW * 0.97)]
	var budget := target_ms()
	var ceiling: float = Settings.get_value("graphics", "supersample_max", 1.3)
	var floor_s: float = Settings.get_value("graphics", "resolution_floor", 0.8)
	# Thermal pressure lowers the ceiling before the SoC throttles.
	if thermal > 0.75:
		ceiling = minf(ceiling, 1.0)
	if thermal > 0.9:
		ceiling = minf(ceiling, 0.9)

	var v_rid := _viewport.get_viewport_rid()
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(v_rid)
	var cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(v_rid)
	var proc_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var work_ms := maxf(proc_ms, maxf(gpu_ms, cpu_ms))
	var has_measure := (gpu_ms + cpu_ms) > 0.05

	var missed_frames := low1_ms > (budget * 1.06)
	var has_headroom := (work_ms < budget * 0.78) if has_measure else (low1_ms <= budget * 1.01 and avg_ms <= budget * 1.01)

	if missed_frames:
		if scale > floor_s + 0.01:
			scale = maxf(floor_s, scale - 0.05)
		elif level < 4:
			level += 1
			tier_changed.emit(level)
		_cooldown = 0.5
	elif has_headroom:
		if level > 0:
			level -= 1
			tier_changed.emit(level)
		elif scale < ceiling - 0.01:
			scale = minf(ceiling, scale + 0.05)
		_cooldown = 1.5
	elif scale > ceiling:
		scale = ceiling
	_viewport.scaling_3d_scale = scale

func _on_tier_changed(lvl: int) -> void:
	match lvl:
		0:
			_viewport.msaa_3d = Viewport.MSAA_4X
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		1:
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		2:
			_viewport.msaa_3d = Viewport.MSAA_DISABLED
		3:
			_viewport.scaling_3d_scale = maxf(scale, 0.75)
		4:
			_viewport.msaa_3d = Viewport.MSAA_DISABLED
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
