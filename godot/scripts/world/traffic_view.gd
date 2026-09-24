class_name TrafficView
extends Node3D
## Draws ambient traffic: one MultiMesh per traffic model, fed every frame from NTSim's packed
## instance buffers (transform + custom data). ~6 draw calls for all traffic.

const MAX_PER_MODEL := 90
const MODELS := 6 # TM_KEI, SEDAN, TAXI, VAN, TRUCK, BUS

var sim: NTSim
var _mm: Array[MultiMesh] = []
var _pad := PackedFloat32Array()

const TRAFFIC_MODELS := [
	"res://assets/models/traffic/traffic_kei.glb",
	"res://assets/models/traffic/traffic_sedan.glb",
	"res://assets/models/traffic/traffic_taxi.glb",
	"res://assets/models/traffic/traffic_van.glb",
	"res://assets/models/traffic/traffic_truck.glb",
	"res://assets/models/traffic/traffic_bus.glb"
]

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

## Builds authentic 3D model for traffic vehicle m.
static func _build_model(m: int) -> Mesh:
	var path: String = TRAFFIC_MODELS[m] if m < TRAFFIC_MODELS.size() else ""
	if path != "" and ResourceLoader.exists(path):
		var scn := load(path) as PackedScene
		if scn:
			var inst := scn.instantiate() as Node3D
			var target_dims: Vector3 = [
				Vector3(1.48, 1.4, 3.4),
				Vector3(1.72, 1.45, 4.6),
				Vector3(1.72, 1.52, 4.7),
				Vector3(1.7, 1.96, 4.7),
				Vector3(2.1, 2.6, 7.6),
				Vector3(2.5, 3.0, 11.0)
			][m]

			var mis: Array[MeshInstance3D] = []
			var stack: Array[Node] = [inst]
			var min_v := Vector3(INF, INF, INF)
			var max_v := Vector3(-INF, -INF, -INF)
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
					var mi := n as MeshInstance3D
					mis.append(mi)
					var aabb: AABB = mi.get_aabb()
					for corner in [
						aabb.position,
						aabb.position + Vector3(aabb.size.x, 0, 0),
						aabb.position + Vector3(0, aabb.size.y, 0),
						aabb.position + Vector3(0, 0, aabb.size.z),
						aabb.end
					]:
						var wpt: Vector3 = mi.transform * corner
						min_v.x = minf(min_v.x, wpt.x)
						min_v.y = minf(min_v.y, wpt.y)
						min_v.z = minf(min_v.z, wpt.z)
						max_v.x = maxf(max_v.x, wpt.x)
						max_v.y = maxf(max_v.y, wpt.y)
						max_v.z = maxf(max_v.z, wpt.z)
				for c in n.get_children():
					stack.push_back(c)

			var orig_size := max_v - min_v
			var scale_vec := Vector3(
				target_dims.x / maxf(orig_size.x, 0.1),
				target_dims.y / maxf(orig_size.y, 0.1),
				target_dims.z / maxf(orig_size.z, 0.1)
			)
			var center_orig := (min_v + max_v) * 0.5

			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var shared_mat: Material = null
			var rot_basis := Basis(Vector3.UP, PI if m < 5 else 0.0)

			for mi in mis:
				var cur_mat := mi.get_surface_override_material(0)
				if not cur_mat:
					cur_mat = mi.mesh.surface_get_material(0)
				if shared_mat == null and cur_mat != null:
					shared_mat = cur_mat
				var local_xform: Transform3D = mi.transform
				var origin_adj: Vector3 = local_xform.origin - center_orig
				var final_origin: Vector3 = rot_basis * (origin_adj * scale_vec)
				var final_basis: Basis = rot_basis * (local_xform.basis.scaled(scale_vec))
				var final_xform := Transform3D(final_basis, final_origin)
				st.append_from(mi.mesh, 0, final_xform)

			var merged := st.commit()
			if merged and merged.get_surface_count() > 0 and shared_mat != null:
				merged.surface_set_material(0, shared_mat)
			inst.free()
			if merged:
				return merged

	# Fallback procedural box model
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := PropLibrary.Builder.new(st)
	var dims: Vector3 = [Vector3(1.48, 1.6, 3.4), Vector3(1.72, 1.45, 4.6), Vector3(1.72, 1.52, 4.7), Vector3(1.7, 1.96, 4.7), Vector3(2.1, 2.8, 7.6), Vector3(2.5, 3.0, 11.0)][m]
	var w: float = dims.x
	var h: float = dims.y
	var l: float = dims.z
	var body_h := h * (0.5 if m < 3 else 0.62)
	var ground := -h * 0.5
	var paint_mat := 5
	var paint_col := Color(1, 1, 1)
	if m == 2:
		paint_mat = 0
		paint_col = Color(0.06, 0.06, 0.07)
	b.box(Vector3(0, ground + 0.25 + body_h * 0.5, 0), Vector3(w, body_h, l), paint_col, paint_mat)
	if m <= 3:
		var cab_l := l * (0.5 if m < 3 else 0.8)
		var cab_z := 0.25 if m < 3 else -0.1
		b.box(Vector3(0, ground + 0.25 + body_h + (h - body_h - 0.25) * 0.5, cab_z), Vector3(w * 0.9, h - body_h - 0.25, cab_l), Color(0.05, 0.06, 0.08), 0)
	elif m == 4:
		b.box(Vector3(0, ground + 0.25 + (h - 0.25) * 0.5, l * 0.3), Vector3(w, h - 0.25, l * 0.65), Color(0.8, 0.8, 0.78), 0)
		b.box(Vector3(0, ground + 1.6, -l * 0.33), Vector3(w * 0.98, 1.1, l * 0.28), Color(0.05, 0.06, 0.08), 0)
	else:
		b.box(Vector3(0, ground + h * 0.7, 0), Vector3(w * 1.01, h * 0.28, l * 0.92), Color(0.05, 0.06, 0.08), 0)
	return st.commit()
