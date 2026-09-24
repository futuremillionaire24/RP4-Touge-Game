class_name PropLibrary
extends RefCounted
## Procedural meshes for every world prop type (indices match PropType in chunk_builder.h).
## Each prop is one surface with vertex colours and a material id in UV.x so all props share
## one shader; they're drawn with MultiMesh per chunk.

enum Type { TREE_BROADLEAF, TREE_CEDAR, TREE_SAKURA, BAMBOO, STREET_LAMP, HIGHWAY_LAMP, UTILITY_POLE, VENDING, PIER, CONTAINER, ROCK, AC_UNIT, WATER_TANK, TRAFFIC_LIGHT, CONE, SIGN_CURVE, STONE_LANTERN, BUSH }

const SHADER := preload("res://shaders/prop.gdshader")

## Visibility range per prop type (m). Beyond it the instance is culled by the GPU-side check.
const VIS_RANGE := {
	Type.TREE_BROADLEAF: 600.0, Type.TREE_CEDAR: 700.0, Type.TREE_SAKURA: 500.0, Type.BAMBOO: 350.0,
	Type.STREET_LAMP: 350.0, Type.HIGHWAY_LAMP: 600.0, Type.UTILITY_POLE: 400.0, Type.VENDING: 150.0,
	Type.PIER: 1500.0, Type.CONTAINER: 700.0, Type.ROCK: 300.0, Type.AC_UNIT: 180.0, Type.WATER_TANK: 300.0,
	Type.TRAFFIC_LIGHT: 250.0, Type.CONE: 120.0, Type.SIGN_CURVE: 200.0, Type.STONE_LANTERN: 150.0, Type.BUSH: 200.0,
}

static var _meshes := {}
static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material

static func mesh(t: int) -> Mesh:
	if _meshes.has(t):
		return _meshes[t]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := Builder.new(st)
	match t:
		Type.TREE_BROADLEAF:
			b.cylinder(Vector3.ZERO, 0.22, 0.14, 3.2, 7, Color(0.28, 0.2, 0.13), 0)
			b.blob(Vector3(0, 4.4, 0), Vector3(2.4, 2.0, 2.4), 2, Color(0.2, 0.36, 0.12, 1.0), 1, 11)
			b.blob(Vector3(0.9, 3.7, 0.5), Vector3(1.6, 1.4, 1.6), 1, Color(0.18, 0.33, 0.11, 1.0), 1, 12)
			b.blob(Vector3(-0.8, 3.9, -0.6), Vector3(1.7, 1.5, 1.7), 1, Color(0.22, 0.38, 0.13, 1.0), 1, 13)
		Type.TREE_CEDAR:
			b.cylinder(Vector3.ZERO, 0.28, 0.2, 3.0, 7, Color(0.3, 0.2, 0.14), 0)
			for k in range(5):
				var y := 2.2 + k * 2.1
				var r := 2.6 - k * 0.45
				b.cone(Vector3(0, y, 0), r, 3.2, 9, Color(0.07, 0.17, 0.09, 0.6 + k * 0.1), 1)
		Type.TREE_SAKURA:
			b.cylinder(Vector3.ZERO, 0.24, 0.16, 2.4, 7, Color(0.25, 0.17, 0.14), 0)
			b.cylinder(Vector3(0, 2.2, 0), 0.14, 0.08, 1.6, 6, Color(0.25, 0.17, 0.14), 0, Vector3(0.5, 1, 0).normalized())
			b.blob(Vector3(0, 3.6, 0), Vector3(3.0, 1.8, 3.0), 2, Color(1, 1, 1, 1.0), 2, 21)
			b.blob(Vector3(1.4, 3.2, 0.6), Vector3(1.6, 1.2, 1.6), 1, Color(1, 1, 1, 1.0), 2, 22)
		Type.BAMBOO:
			for k in range(9):
				var a := k * 2.39996
				var p := Vector3(cos(a), 0, sin(a)) * (0.35 + 0.1 * k)
				b.cylinder(p, 0.06, 0.05, 8.5 + (k % 3), 5, Color(0.36, 0.5, 0.2, 0.3), 1)
			b.blob(Vector3(0, 8.0, 0), Vector3(1.8, 2.2, 1.8), 1, Color(0.3, 0.48, 0.16, 1.0), 1, 31)
		Type.STREET_LAMP:
			b.cylinder(Vector3.ZERO, 0.09, 0.07, 7.8, 8, Color(0.35, 0.36, 0.38), 7)
			b.box(Vector3(0, 7.7, 0.7), Vector3(0.1, 0.1, 1.5), Color(0.35, 0.36, 0.38), 7)
			b.box(Vector3(0, 7.6, 1.45), Vector3(0.35, 0.12, 0.6), Color(1, 1, 1), 3)
		Type.HIGHWAY_LAMP:
			b.cylinder(Vector3.ZERO, 0.12, 0.09, 9.8, 8, Color(0.5, 0.52, 0.54), 7)
			b.box(Vector3(0, 9.7, 1.5), Vector3(0.12, 0.12, 3.0), Color(0.5, 0.52, 0.54), 7)
			b.box(Vector3(0, 9.6, 3.0), Vector3(0.4, 0.14, 0.9), Color(1, 1, 1), 3)
		Type.UTILITY_POLE:
			b.cylinder(Vector3.ZERO, 0.16, 0.12, 11.0, 8, Color(0.55, 0.54, 0.5), 0)
			b.box(Vector3(0, 10.2, 0), Vector3(2.2, 0.12, 0.12), Color(0.3, 0.3, 0.3), 7)
			b.box(Vector3(0, 9.3, 0), Vector3(1.6, 0.1, 0.1), Color(0.3, 0.3, 0.3), 7)
			b.cylinder(Vector3(0.3, 7.6, 0.25), 0.28, 0.28, 0.9, 8, Color(0.42, 0.44, 0.45), 7)
			for x in [-1.0, -0.4, 0.4, 1.0]:
				b.cylinder(Vector3(x, 10.26, 0), 0.05, 0.05, 0.18, 5, Color(0.8, 0.8, 0.78), 0)
		Type.VENDING:
			b.box(Vector3(0, 0.9, 0), Vector3(1.0, 1.8, 0.75), Color(1, 1, 1), 5)
			b.box(Vector3(0, 1.1, 0.38), Vector3(0.85, 1.1, 0.02), Color(1, 1, 1), 4)
		Type.PIER:
			b.box(Vector3(0, 0.5, 0), Vector3(2.2, 1.0, 1.4), Color(0.58, 0.57, 0.54), 0)
		Type.CONTAINER:
			b.box(Vector3(0, 1.3, 0), Vector3(12.2, 2.6, 2.44), Color(1, 1, 1), 5)
		Type.ROCK:
			b.blob(Vector3(0, 0.4, 0), Vector3(1.2, 0.9, 1.0), 1, Color(0.4, 0.39, 0.37, 0.0), 0, 41, 0.35)
		Type.AC_UNIT:
			b.box(Vector3(0, 0.35, 0), Vector3(0.9, 0.7, 0.4), Color(0.78, 0.78, 0.76), 0)
			b.cylinder(Vector3(0, 0.35, 0.2), 0.25, 0.25, 0.02, 12, Color(0.15, 0.15, 0.15), 0, Vector3(0, 0, 1))
		Type.WATER_TANK:
			for c in [Vector3(-0.8, 0, -0.8), Vector3(0.8, 0, -0.8), Vector3(0.8, 0, 0.8), Vector3(-0.8, 0, 0.8)]:
				b.box(c + Vector3(0, 0.6, 0), Vector3(0.1, 1.2, 0.1), Color(0.3, 0.3, 0.3), 7)
			b.cylinder(Vector3(0, 1.2, 0), 1.2, 1.2, 2.0, 14, Color(0.75, 0.74, 0.7), 0)
		Type.TRAFFIC_LIGHT:
			b.cylinder(Vector3.ZERO, 0.08, 0.07, 5.2, 8, Color(0.4, 0.41, 0.42), 7)
			b.box(Vector3(0, 5.1, 1.6), Vector3(0.1, 0.1, 3.2), Color(0.4, 0.41, 0.42), 7)
			b.box(Vector3(0, 4.9, 3.0), Vector3(1.2, 0.4, 0.3), Color(0.1, 0.1, 0.1), 0)
			b.box(Vector3(0, 4.9, 3.16), Vector3(1.0, 0.25, 0.02), Color(1, 1, 1), 6)
		Type.CONE:
			b.cone(Vector3.ZERO, 0.17, 0.5, 10, Color(1.0, 0.35, 0.05, 0.0), 0)
		Type.SIGN_CURVE:
			b.box(Vector3(0, 0.6, 0), Vector3(0.08, 1.2, 0.08), Color(0.5, 0.5, 0.5), 7)
			b.box(Vector3(0, 1.4, 0), Vector3(0.9, 0.55, 0.04), Color(0.95, 0.75, 0.05), 0)
			for k in range(3):
				b.box(Vector3(-0.28 + k * 0.28, 1.4, 0.025), Vector3(0.1, 0.4, 0.01), Color(0.05, 0.05, 0.05), 0)
		Type.STONE_LANTERN:
			b.box(Vector3(0, 0.3, 0), Vector3(0.6, 0.6, 0.6), Color(0.5, 0.5, 0.47), 0)
			b.cylinder(Vector3(0, 0.6, 0), 0.15, 0.15, 0.6, 8, Color(0.5, 0.5, 0.47), 0)
			b.box(Vector3(0, 1.4, 0), Vector3(0.5, 0.45, 0.5), Color(0.5, 0.5, 0.47), 0)
			b.cone(Vector3(0, 1.62, 0), 0.55, 0.4, 6, Color(0.46, 0.46, 0.43), 0)
		Type.BUSH:
			b.blob(Vector3(0, 0.6, 0), Vector3(1.2, 0.8, 1.2), 1, Color(0.18, 0.32, 0.1, 0.8), 1, 51)
	st.generate_tangents()
	var m := st.commit()
	_meshes[t] = m
	return m

## Builds a MultiMeshInstance3D for one prop type from packed instances
## (x, y, z, yaw, sx, sy, sz, color) as produced by NTWorld.build_chunk.
static func multimesh_instance(t: int, data: PackedFloat32Array) -> MultiMeshInstance3D:
	var count := data.size() / 8
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh(t)
	mm.instance_count = count
	for i in range(count):
		var o := i * 8
		var basis := Basis(Vector3.UP, data[o + 3])
		if t == Type.PIER:
			basis = basis.scaled(Vector3(1.0, data[o + 5], 1.0))
		else:
			basis = basis.scaled(Vector3(data[o + 4], data[o + 5], data[o + 6]))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(data[o], data[o + 1], data[o + 2])))
		mm.set_instance_custom_data(i, Color(data[o + 7], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material()
	mmi.visibility_range_end = VIS_RANGE.get(t, 400.0)
	mmi.visibility_range_end_margin = 20.0
	var shadows := t in [Type.TREE_BROADLEAF, Type.TREE_CEDAR, Type.TREE_SAKURA, Type.PIER, Type.CONTAINER, Type.UTILITY_POLE]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

## Primitive helpers writing into one SurfaceTool (flat-shaded faces, UV.x = material id).
class Builder:
	var st: SurfaceTool

	func _init(p_st: SurfaceTool) -> void:
		st = p_st

	func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color, mat: int) -> void:
		# Godot front faces are clockwise; callers pass counter-clockwise (outward) order.
		var n := (b - a).cross(c - a).normalized()
		for p in [a, c, b]:
			st.set_color(col)
			st.set_uv(Vector2(mat, 0))
			st.set_normal(n)
			st.add_vertex(p)

	func box(center: Vector3, size: Vector3, col: Color, mat: int) -> void:
		var h := size * 0.5
		var c := [
			center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z), center + Vector3(h.x, h.y, -h.z), center + Vector3(-h.x, h.y, -h.z),
			center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z), center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
		]
		var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
		for f in faces:
			_tri(c[f[0]], c[f[1]], c[f[2]], col, mat)
			_tri(c[f[0]], c[f[2]], c[f[3]], col, mat)

	func cylinder(base: Vector3, r0: float, r1: float, h: float, seg: int, col: Color, mat: int, axis := Vector3.UP) -> void:
		var up := axis.normalized()
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		var fwd := up.cross(side)
		for k in range(seg):
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var d0 := side * cos(a0) + fwd * sin(a0)
			var d1 := side * cos(a1) + fwd * sin(a1)
			var p0 := base + d0 * r0
			var p1 := base + d1 * r0
			var q0 := base + up * h + d0 * r1
			var q1 := base + up * h + d1 * r1
			_tri(p0, p1, q1, col, mat)
			_tri(p0, q1, q0, col, mat)
			_tri(base + up * h, q0, q1, col, mat)

	func cone(base: Vector3, r: float, h: float, seg: int, col: Color, mat: int) -> void:
		var tip := base + Vector3(0, h, 0)
		for k in range(seg):
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var p0 := base + Vector3(cos(a0), 0, sin(a0)) * r
			var p1 := base + Vector3(cos(a1), 0, sin(a1)) * r
			_tri(p0, tip, p1, col, mat)
			_tri(base, p0, p1, Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, col.a), mat)

	## Low-poly lumpy ellipsoid (icosphere subdivided `level` times, radially jittered).
	func blob(center: Vector3, radii: Vector3, level: int, col: Color, mat: int, seed: int, jitter := 0.18) -> void:
		var t := (1.0 + sqrt(5.0)) / 2.0
		var verts := [
			Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
		]
		for i in range(verts.size()):
			verts[i] = verts[i].normalized()
		var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
			[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
		for l in range(level):
			var nf := []
			var cache := {}
			for f in faces:
				var m := []
				for e in [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]]:
					var key := "%d_%d" % [mini(e[0], e[1]), maxi(e[0], e[1])]
					if not cache.has(key):
						cache[key] = verts.size()
						verts.append(((verts[e[0]] + verts[e[1]]) * 0.5).normalized())
					m.append(cache[key])
				nf.append([f[0], m[0], m[2]])
				nf.append([f[1], m[1], m[0]])
				nf.append([f[2], m[2], m[1]])
				nf.append([m[0], m[1], m[2]])
			faces = nf
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var pts := []
		for v in verts:
			var j := 1.0 + rng.randf_range(-jitter, jitter)
			pts.append(center + Vector3(v.x * radii.x, v.y * radii.y, v.z * radii.z) * j)
		for f in faces:
			# Icosphere faces are counter-clockwise from outside.
			_tri(pts[f[0]], pts[f[1]], pts[f[2]], col, mat)
