class_name Activities
extends Node3D
## PR stunts placed on the generated roads: speed traps, speed zones, drift zones, danger
## signs. Plus Omamori collectibles. Results earn 1-3 stars (saved per activity in Profile).

signal result(kind: String, id: String, value: float, stars: int)

enum Kind { SPEED_TRAP, SPEED_ZONE, DRIFT_ZONE, DANGER_SIGN }
const KIND_NAMES := ["Speed Trap", "Speed Zone", "Drift Zone", "Danger Sign"]
const KIND_COLORS := [Color(0.2, 0.9, 1.0), Color(0.3, 1.0, 0.5), Color(1.0, 0.3, 0.7), Color(1.0, 0.75, 0.1)]
# Star thresholds: km/h (trap), km/h (zone), points (drift), metres (danger).
const STARS := [[150.0, 190.0, 230.0], [120.0, 150.0, 180.0], [8000.0, 20000.0, 40000.0], [20.0, 45.0, 80.0]]

var world: NTWorld
var sim: NTSim
var player: CarView
var skills: SkillSystem
var enabled := true
var items := [] # {"kind", "id", "road", "pos", "end", "dir"}
var omamori := [] # {"id", "pos", "node"}
var barns := [] # {"id", "name", "car", "pos", "level", "node"}
var _active := {} # running zone: {"item", "t0", "drift0"}
var _jump := {} # {"item", "start", "armed"}
var _prev_pos := Vector3.ZERO

func build(p_world: NTWorld) -> void:
	world = p_world
	_generate()
	for it in items:
		_make_sign(it)
	for p in world.pois():
		if p.type == 7: # POI_OMAMORI
			if Profile.data.omamori.has(p.id):
				continue
			var node := _make_charm(p.position)
			omamori.append({"id": p.id, "pos": p.position + Vector3(0, 1.5, 0), "node": node})
	# Barn Finds
	barns = [
		{"id": "barn_turbie", "name": "La Turbie Hayloft", "car": "mb_300sl", "pos": Vector3(-1250, 22, 1420), "level": 2},
		{"id": "barn_akina", "name": "Mt. Akina Mountain Lodge", "car": "jaguar_etype", "pos": Vector3(1820, 145, -2080), "level": 4}
	]
	for b in barns:
		if not Profile.data.get("barns", []).has(b.id):
			_make_barn_visual(b)

func _make_barn_visual(b: Dictionary) -> void:
	var root := Node3D.new()
	root.position = b.pos
	var shed := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8.0, 4.5, 12.0)
	shed.mesh = box
	shed.position = Vector3(0, 2.25, 0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.22, 0.16, 0.12)
	sm.roughness = 0.9
	shed.material_override = sm
	root.add_child(shed)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3.5, 6.2)
	lamp.light_color = Color(1.0, 0.7, 0.3)
	lamp.light_energy = 2.0
	lamp.omni_range = 14.0
	root.add_child(lamp)
	add_child(root)
	b["node"] = root

func _generate() -> void:
	var roads := ["coast_road", "rural_main", "route1", "mountain_road", "wangan_spur", "shuto_loop", "touge_ascent", "touge_descent", "dock_ew_1_0", "dock_ew_1_1"]
	var trap_n := 0
	var zone_n := 0
	var drift_n := 0
	var danger_n := 0
	for name in roads:
		var rs := world.road_samples(name)
		if rs.is_empty():
			continue
		var c: PackedVector3Array = rs.centers
		var t: PackedVector3Array = rs.tangents
		var n := c.size()
		if n < 80:
			continue
		# Straightness over +-25 samples (75 m) for traps/zones.
		var i := 40
		while i < n - 40:
			var straight := t[i - 25].dot(t[i + 25]) > 0.995
			if straight and trap_n < 8 and name in ["coast_road", "rural_main", "mountain_road", "wangan_spur", "shuto_loop"]:
				items.append({"kind": Kind.SPEED_TRAP, "id": "trap_%d" % trap_n, "road": name, "pos": c[i], "dir": t[i]})
				trap_n += 1
				i += 220
				continue
			i += 20
		# Speed zones on the fastest roads: a 400 m straight-ish run.
		if name in ["wangan_spur", "coast_road", "shuto_loop"] and zone_n < 5:
			var s := n / 3
			if s + 140 < n:
				items.append({"kind": Kind.SPEED_ZONE, "id": "zone_%d" % zone_n, "road": name, "pos": c[s], "end": c[s + 133], "dir": t[s]})
				zone_n += 1
		# Drift zones on the curvy stuff.
		if name in ["touge_ascent", "touge_descent", "dock_ew_1_0", "mountain_road"] and drift_n < 5:
			var best_i := 20
			var best_turn := 0.0
			for k in range(20, n - 160, 15):
				var turn := 0.0
				for q in range(k, k + 140, 10):
					turn += 1.0 - t[q].dot(t[q + 10])
				if turn > best_turn:
					best_turn = turn
					best_i = k
			items.append({"kind": Kind.DRIFT_ZONE, "id": "drift_%d" % drift_n, "road": name, "pos": c[best_i], "end": c[mini(best_i + 140, n - 1)], "dir": t[best_i]})
			drift_n += 1
		# Danger signs at the sharpest crests of country roads.
		if name in ["rural_main", "coast_road", "mountain_road"] and danger_n < 4:
			var crest_i := -1
			var crest_k := 0.0
			for k in range(30, n - 30, 3):
				var k2 := (c[k].y - c[k - 8].y) - (c[k + 8].y - c[k].y)
				if k2 > crest_k:
					crest_k = k2
					crest_i = k
			if crest_i > 0 and crest_k > 0.8:
				items.append({"kind": Kind.DANGER_SIGN, "id": "danger_%d" % danger_n, "road": name, "pos": c[crest_i - 12], "dir": t[crest_i - 12]})
				danger_n += 1

func _make_sign(it: Dictionary) -> void:
	var col: Color = KIND_COLORS[it.kind]
	var root := Node3D.new()
	root.position = it.pos
	add_child(root)
	var right: Vector3 = it.dir.cross(Vector3.UP).normalized()
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.2, 1.3, 0.1)
	board.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.6)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.4
	board.material_override = m
	board.position = right * 7.0 + Vector3(0, 3.2, 0)
	board.look_at_from_position(board.position, board.position - it.dir, Vector3.UP)
	root.add_child(board)
	var label := Label3D.new()
	label.text = KIND_NAMES[it.kind].to_upper()
	label.font_size = 56
	label.pixel_size = 0.012
	label.modulate = Color.WHITE
	label.outline_size = 8
	label.position = right * 7.0 + Vector3(0, 3.2, 0) - it.dir * 0.08
	label.look_at_from_position(label.position, label.position + it.dir, Vector3.UP)
	root.add_child(label)
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.06
	pm.bottom_radius = 0.06
	pm.height = 2.6
	post.mesh = pm
	post.position = right * 7.0 + Vector3(0, 1.3, 0)
	root.add_child(post)

func _make_charm(pos: Vector3) -> Node3D:
	var n := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.7, 0.12)
	n.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.15, 0.2)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.3, 0.35)
	m.emission_energy_multiplier = 2.5
	n.material_override = m
	n.position = pos + Vector3(0, 1.5, 0)
	add_child(n)
	return n

func stars_for(kind: int, value: float) -> int:
	var th: Array = STARS[kind]
	var s := 0
	for v in th:
		if value >= v:
			s += 1
	return s

func _physics_process(delta: float) -> void:
	if not enabled or player == null or sim == null:
		return
	var pos := player.global_position
	var t := player.telemetry
	if t.is_empty():
		return
	var speed_kmh: float = absf(float(t.speed_kmh))
	# Gate crossings: segment prev->pos crossing the plane through the item, within 12 m.
	for it in items:
		var p: Vector3 = it.pos
		if pos.distance_to(p) > 40.0:
			continue
		var d0: float = (_prev_pos - p).dot(it.dir)
		var d1: float = (pos - p).dot(it.dir)
		if d0 < 0.0 and d1 >= 0.0 and (pos - p).length() < 14.0:
			match it.kind:
				Kind.SPEED_TRAP:
					_finish(it, speed_kmh)
				Kind.SPEED_ZONE, Kind.DRIFT_ZONE:
					_active = {"item": it, "t0": Time.get_ticks_msec() / 1000.0, "drift0": skills.total_banked + skills.chain_points if skills else 0.0}
				Kind.DANGER_SIGN:
					_jump = {"item": it, "start": Vector3.ZERO, "armed": true, "timer": 3.0}
	# Zone end gates.
	if not _active.is_empty():
		var it: Dictionary = _active.item
		var e: Vector3 = it.end
		if pos.distance_to(e) < 16.0:
			var dt := Time.get_ticks_msec() / 1000.0 - float(_active.t0)
			if it.kind == Kind.SPEED_ZONE:
				var dist: float = it.pos.distance_to(e)
				_finish(it, dist / maxf(dt, 0.1) * 3.6)
			else:
				var pts: float = (skills.total_banked + skills.chain_points) - float(_active.drift0) if skills else 0.0
				_finish(it, pts)
			_active = {}
		elif pos.distance_to(it.pos) > it.pos.distance_to(e) + 120.0:
			_active = {} # left the zone
	# Danger sign jump measurement.
	if not _jump.is_empty():
		var air: float = t.airborne
		_jump.timer -= delta
		if air > 0.05 and _jump.start == Vector3.ZERO:
			_jump.start = pos
		elif air <= 0.0 and _jump.start != Vector3.ZERO:
			var dist := Vector2(pos.x - _jump.start.x, pos.z - _jump.start.z).length()
			_finish(_jump.item, dist)
			_jump = {}
		elif _jump.timer <= 0.0 and _jump.start == Vector3.ZERO:
			_jump = {}
	# Omamori pickup.
	for o in omamori:
		if o.node and pos.distance_to(o.pos) < 4.0:
			o.node.queue_free()
			o.node = null
			Profile.data.omamori.append(o.id)
			Profile.add_credits(2500)
			Profile.add_xp(300)
			Profile.save()
			result.emit("Omamori", o.id, Profile.data.omamori.size(), 0)
	# Barn Finds discovery.
	for b in barns:
		if b.get("node") != null and pos.distance_to(b.pos) < 22.0:
			var barns_found: Array = Profile.data.get("barns", [])
			if not barns_found.has(b.id):
				barns_found.append(b.id)
				Profile.data["barns"] = barns_found
				Profile.add_car(b.car, "barn_find")
				Profile.add_xp(600)
				Profile.save()
				result.emit("Barn Find", b.name, 1.0, 3)
	_prev_pos = pos

func _process(delta: float) -> void:
	for o in omamori:
		if o.node:
			o.node.rotate_y(delta * 1.5)

func _finish(it: Dictionary, value: float) -> void:
	var stars := stars_for(it.kind, value)
	var rec: Dictionary = Profile.data.records.get(it.id, {"best": 0.0, "stars": 0})
	if value > float(rec.best):
		rec.best = value
	if stars > int(rec.stars):
		Profile.add_xp(250 * (stars - int(rec.stars)))
		Profile.add_credits(1500 * (stars - int(rec.stars)))
		rec.stars = stars
	Profile.data.records[it.id] = rec
	Profile.save()
	result.emit(KIND_NAMES[it.kind], it.id, value, stars)
