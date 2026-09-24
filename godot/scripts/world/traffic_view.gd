class_name TrafficView
extends Node3D
## Draws ambient traffic: one MultiMesh per traffic model, fed every frame from NTSim's packed
## instance buffers (transform + custom data). ~6 draw calls for all traffic.

const MAX_PER_MODEL := 90
const MODELS := 6 # TM_KEI, SEDAN, TAXI, VAN, TRUCK, BUS

var sim: NTSim
var _mm: Array[MultiMesh] = []
var _pad := PackedFloat32Array()

func _ready() -> void:
	for m in range(MODELS):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _build_model(m)
		mm.instance_count = MAX_PER_MODEL
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = PropLibrary.material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Traffic instances are spread over ~800 m; skip per-instance culling cost.
		mmi.custom_aabb = AABB(Vector3(-5000, -100, -5000), Vector3(10000, 1000, 10000))
		add_child(mmi)
		_mm.append(mm)

func _process(_delta: float) -> void:
	if sim == null:
		return
	for m in range(MODELS):
		var buf := sim.traffic_buffer(m)
		var count := buf.size() / 16
		var mm := _mm[m]
		if count == 0:
			mm.visible_instance_count = 0
			continue
		count = mini(count, MAX_PER_MODEL)
		# The buffer must cover every allocated instance; pad the tail.
		if buf.size() < MAX_PER_MODEL * 16:
			var full := PackedFloat32Array()
			full.resize(MAX_PER_MODEL * 16)
			for i in range(buf.size()):
				full[i] = buf[i]
			buf = full
		mm.buffer = buf
		mm.visible_instance_count = count

## Simple merged traffic car: lower body (instance paint), cabin, glass, wheels, lights.
static func _build_model(m: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := PropLibrary.Builder.new(st)
	var dims: Vector3 = [Vector3(1.48, 1.6, 3.4), Vector3(1.72, 1.45, 4.6), Vector3(1.72, 1.52, 4.7), Vector3(1.7, 1.96, 4.7), Vector3(2.1, 2.8, 7.6), Vector3(2.5, 3.0, 11.0)][m]
	var w: float = dims.x
	var h: float = dims.y
	var l: float = dims.z
	var body_h := h * (0.5 if m < 3 else 0.62)
	var ground := -h * 0.5 # instances are placed at body centre
	var paint_mat := 5
	var paint_col := Color(1, 1, 1)
	if m == 2:
		paint_mat = 0
		paint_col = Color(0.06, 0.06, 0.07) # black taxi, with a roof lamp
	b.box(Vector3(0, ground + 0.25 + body_h * 0.5, 0), Vector3(w, body_h, l), paint_col, paint_mat)
	if m <= 3:
		var cab_l := l * (0.5 if m < 3 else 0.8)
		var cab_z := 0.25 if m < 3 else -0.1
		b.box(Vector3(0, ground + 0.25 + body_h + (h - body_h - 0.25) * 0.5, cab_z), Vector3(w * 0.9, h - body_h - 0.25, cab_l), Color(0.05, 0.06, 0.08), 0)
	elif m == 4:
		# Truck: cab + box body.
		b.box(Vector3(0, ground + 0.25 + (h - 0.25) * 0.5, l * 0.3), Vector3(w, h - 0.25, l * 0.65), Color(0.8, 0.8, 0.78), 0)
		b.box(Vector3(0, ground + 1.6, -l * 0.33), Vector3(w * 0.98, 1.1, l * 0.28), Color(0.05, 0.06, 0.08), 0)
	else:
		# Bus: window band.
		b.box(Vector3(0, ground + h * 0.7, 0), Vector3(w * 1.01, h * 0.28, l * 0.92), Color(0.05, 0.06, 0.08), 0)
	if m == 2:
		b.box(Vector3(0, ground + h + 0.08, 0.2), Vector3(0.4, 0.16, 0.2), Color(1, 1, 1), 4)
	# Wheels.
	var r := 0.3 if m < 4 else 0.48
	for zf in [-0.33, 0.33]:
		for xf in [-0.5, 0.5]:
			b.cylinder(Vector3(xf * w - (0.1 if xf < 0 else -0.1), ground + r, zf * l), r, r, 0.22, 10, Color(0.04, 0.04, 0.04), 0, Vector3(1, 0, 0) * signf(xf))
	# Head / tail lights.
	for xf in [-0.36, 0.36]:
		b.box(Vector3(xf * w, ground + 0.25 + body_h * 0.7, -l * 0.5 - 0.02), Vector3(0.3, 0.12, 0.04), Color(1, 1, 1), 3)
		b.box(Vector3(xf * w, ground + 0.25 + body_h * 0.7, l * 0.5 + 0.02), Vector3(0.3, 0.12, 0.04), Color(1, 0.1, 0.1), 8)
	return st.commit()
