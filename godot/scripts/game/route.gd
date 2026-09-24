class_name Route
extends RefCounted
## A race route built from world roads: a list of road names (optionally reversed, "~name")
## chained end to end, or waypoints snapped to the road network. Produces the sample arrays the
## native racing line wants plus cumulative distance, checkpoints and a start grid.

var centers := PackedVector3Array()
var tangents := PackedVector3Array()
var ups := PackedVector3Array()
var width_left := PackedFloat32Array()
var width_right := PackedFloat32Array()
var distance := PackedFloat32Array()
var closed := false
var length := 0.0

static func from_roads(world: NTWorld, names: Array, closed_loop: bool, start_fraction := 0.0) -> Route:
	var r := Route.new()
	r.closed = closed_loop
	for entry in names:
		var name: String = entry
		var rev := name.begins_with("~")
		if rev:
			name = name.substr(1)
		var rs := world.road_samples(name)
		if rs.is_empty():
			push_warning("Route: unknown road %s" % name)
			continue
		var n: int = rs.centers.size()
		var idx := range(n)
		if rev:
			idx.reverse()
		# Skip samples that overlap the previous road's end (junction mouth).
		var start_k := 0
		if r.centers.size() > 0:
			var last := r.centers[r.centers.size() - 1]
			while start_k < idx.size() - 1 and rs.centers[idx[start_k]].distance_to(last) < 3.0:
				start_k += 1
			# Bridge the gap across a junction patch with interpolated samples (~3 m apart).
			var first: Vector3 = rs.centers[idx[start_k]]
			var gap := last.distance_to(first)
			if gap > 4.5:
				var steps := int(gap / 3.0)
				var w0 := minf(r.width_left[r.width_left.size() - 1], r.width_right[r.width_right.size() - 1])
				for s in range(1, steps):
					var t := float(s) / steps
					var p := last.lerp(first, t)
					r.centers.append(p)
					r.tangents.append((first - last).normalized())
					r.ups.append(Vector3.UP)
					r.width_left.append(w0 + 2.0)
					r.width_right.append(w0 + 2.0)
		for k in range(start_k, idx.size()):
			var i: int = idx[k]
			r.centers.append(rs.centers[i])
			var t: Vector3 = rs.tangents[i]
			r.tangents.append(-t if rev else t)
			r.ups.append(rs.ups[i])
			# Left/right swap when driving a road backwards.
			r.width_left.append(rs.width_right[i] if rev else rs.width_left[i])
			r.width_right.append(rs.width_left[i] if rev else rs.width_right[i])
	if start_fraction > 0.0 and closed_loop:
		r._rotate_start(int(start_fraction * r.centers.size()))
	r._compute_distance()
	return r

func _rotate_start(k: int) -> void:
	var arrays := [centers, tangents, ups, width_left, width_right]
	for a in arrays:
		var head = a.slice(0, k)
		var tail = a.slice(k)
		a.clear()
		a.append_array(tail)
		a.append_array(head)

func _compute_distance() -> void:
	distance.resize(centers.size())
	var d := 0.0
	for i in range(centers.size()):
		if i > 0:
			d += centers[i].distance_to(centers[i - 1])
		distance[i] = d
	length = d + (centers[centers.size() - 1].distance_to(centers[0]) if closed and centers.size() > 1 else 0.0)

func apply_to(sim: NTSim) -> void:
	sim.set_racing_line(centers, ups, width_left, width_right, closed)

## Start line sample: 0 on circuits (the grid wraps behind it); on point-to-point routes far
## enough in that the whole grid fits behind it.
func start_index(grid_size: int) -> int:
	if closed:
		return 0
	var rows := (grid_size + 1) / 2
	return mini(8 + rows * 3, centers.size() - 1)

## Grid slots behind the start line: two staggered columns, ~9 m between rows.
func grid_slot(slot: int, grid_size: int) -> Transform3D:
	var n := centers.size()
	var i := start_index(grid_size) - 5 - (slot / 2) * 3 - (slot % 2)
	i = (i % n + n) % n if closed else clampi(i, 0, n - 1)
	var c := centers[i]
	var t := tangents[i]
	var right := t.cross(Vector3.UP).normalized()
	var half := minf(width_left[i], width_right[i])
	var off := clampf(half * 0.45, 1.6, 3.2) * (1.0 if slot % 2 == 1 else -1.0)
	return Transform3D(Basis.looking_at(t, Vector3.UP), c + right * off + Vector3(0, 0.9, 0))

## Evenly spaced checkpoint sample indices (for split times and minimap markers).
func checkpoints(count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := centers.size()
	for k in range(1, count + 1):
		out.append(int(float(n) * k / (count + 1)))
	return out

## Downsampled polyline for the minimap.
func polyline(step := 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, centers.size(), step):
		out.append(Vector2(centers[i].x, centers[i].z))
	return out
