class_name LightPool
extends Node3D
## At night, assigns a small pool of real OmniLight3Ds to the nearest street lamps / neon / tunnel
## lights around the camera (mobile renderer: few real lights, the rest are emissive + bloom).

## Mobile renderer: 8 omni lights per mesh. Chunk meshes are large, so keep the pool small
## enough that the car's headlights and nearby rivals' lights still fit.
@export var size := 6
var streamer: WorldStreamer
var camera: Camera3D
var night := 0.0
var _lights: Array[OmniLight3D] = []
var _timer := 0.0

func _ready() -> void:
	for i in range(size):
		var l := OmniLight3D.new()
		l.omni_range = 16.0
		l.omni_attenuation = 1.4
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)

static func hue_to_color(h: float) -> Color:
	if h < 0.13:
		return Color(1.0, 0.72, 0.4) # sodium / warm street lamp
	return Color.from_hsv(h, 0.75, 1.0)

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or streamer == null or camera == null:
		return
	_timer = 0.25
	if night < 0.05:
		for l in _lights:
			l.visible = false
		return
	var cam := camera.global_position
	var data := streamer.lights_near(cam, 140.0)
	var n := data.size() / 5
	var order := []
	for i in range(n):
		var dx := data[i * 5] - cam.x
		var dy := data[i * 5 + 1] - cam.y
		var dz := data[i * 5 + 2] - cam.z
		order.append([dx * dx + dy * dy + dz * dz, i])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for k in range(_lights.size()):
		var l := _lights[k]
		if k >= order.size():
			l.visible = false
			continue
		var i: int = order[k][1]
		l.global_position = Vector3(data[i * 5], data[i * 5 + 1], data[i * 5 + 2])
		l.light_color = hue_to_color(data[i * 5 + 4])
		l.light_energy = data[i * 5 + 3] * 2.2 * night
		l.omni_range = 10.0 + 10.0 * data[i * 5 + 3]
		l.visible = true
