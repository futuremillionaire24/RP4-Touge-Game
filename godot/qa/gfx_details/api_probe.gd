extends SceneTree
## Probe engine APIs used by the details builder (run with -s).

func _init() -> void:
	var bm := BoxMesh.new()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bm.get_mesh_arrays())
	var tm := am.generate_triangle_mesh()
	print("tm ", tm)
	print("methods ", tm.get_method_list().map(func(m): return m.name))
	var r = tm.intersect_ray(Vector3(0, 0, -5), Vector3(0, 0, 1))
	print("ray ", r)
	var s = tm.intersect_segment(Vector3(0.1, 0.2, -5), Vector3(0.1, 0.2, 5))
	print("seg ", s)
	quit()
