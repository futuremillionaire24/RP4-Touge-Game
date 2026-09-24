extends Control
## Full-Screen Interactive World Map with GPS Road Navigation, Fast Travel, and Event Inspection.
## Bound to Pad.pressed("map") / Right Stick click / 'M' key.

signal closed
signal waypoint_set(pos: Vector3, polyline: PackedVector2Array)
signal fast_travel_requested(pos: Vector3, dir: Vector3)

var world: NTWorld
var player: CarView
var markers: EventMarkers
var activities: Activities
var freeroam_host: Node

var _tex: ImageTexture
var _bounds: Rect2
var _map_size: float = 1024.0

var _cam_pos := Vector2.ZERO # world coordinates the map view is centered on
var _target_cam_pos := Vector2.ZERO
var _zoom := 0.75 # pixels per meter
var _target_zoom := 0.75

var _hovered_item := {}
var _gps_waypoint := Vector3.INF
var _gps_polyline := PackedVector2Array()
var _road_graph := {} # road_name -> {"samples": centers, "start": p0, "end": p1, "neighbors": []}
var _road_graph_built := false
var _open_time := 0

var _card_panel: PanelContainer
var _title_lbl: Label
var _type_lbl: Label
var _stats_lbl: Label
var _prompt_lbl: Label
var _district_lbl: Label
var _legend_lbl: Label

func setup(p_world: NTWorld, p_player: CarView, p_markers: EventMarkers, p_activities: Activities, p_host: Node) -> void:
	world = p_world
	player = p_player
	markers = p_markers
	activities = p_activities
	freeroam_host = p_host
	_bounds = world.bounds()
	_tex = ImageTexture.create_from_image(world.minimap(1024))
	if player:
		_cam_pos = Vector2(player.global_position.x, player.global_position.z)
		_target_cam_pos = _cam_pos
	_build_road_graph()

func _ready() -> void:
	_open_time = Time.get_ticks_msec()
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_PASS
	process_mode = PROCESS_MODE_ALWAYS # runs while tree is paused
	_build_ui()

func _build_ui() -> void:
	# Top District Header
	_district_lbl = Label.new()
	_district_lbl.set_anchors_preset(PRESET_TOP_WIDE)
	_district_lbl.offset_top = 24.0
	_district_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_district_lbl.add_theme_font_size_override("font_size", 24)
	_district_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_district_lbl.add_theme_constant_override("outline_size", 8)
	_district_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_district_lbl)

	# Info Card (top right)
	_card_panel = PanelContainer.new()
	_card_panel.set_anchors_preset(PRESET_TOP_RIGHT)
	_card_panel.offset_left = -380.0
	_card_panel.offset_top = 24.0
	_card_panel.offset_right = -24.0
	_card_panel.offset_bottom = 220.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.15, 0.85, 1.0, 0.6)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 16
	sb.content_margin_top = 14
	sb.content_margin_right = 16
	sb.content_margin_bottom = 14
	_card_panel.add_theme_stylebox_override("panel", sb)
	add_child(_card_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_card_panel.add_child(vb)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 20)
	_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	vb.add_child(_title_lbl)

	_type_lbl = Label.new()
	_type_lbl.add_theme_font_size_override("font_size", 14)
	_type_lbl.add_theme_color_override("font_color", Color(0.15, 0.85, 1.0))
	vb.add_child(_type_lbl)

	_stats_lbl = Label.new()
	_stats_lbl.add_theme_font_size_override("font_size", 13)
	_stats_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	_stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_stats_lbl)

	_prompt_lbl = Label.new()
	_prompt_lbl.add_theme_font_size_override("font_size", 13)
	_prompt_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	vb.add_child(_prompt_lbl)

	# Bottom Legend
	_legend_lbl = Label.new()
	_legend_lbl.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_legend_lbl.offset_bottom = -20.0
	_legend_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legend_lbl.add_theme_font_size_override("font_size", 15)
	_legend_lbl.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	_legend_lbl.add_theme_constant_override("outline_size", 6)
	_legend_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_legend_lbl.text = "◀▶▲▼ Pan   L1/R1 Zoom   A Set GPS   X Fast Travel   Y Center Car   B Back"
	add_child(_legend_lbl)

func _build_road_graph() -> void:
	if _road_graph_built or world == null:
		return
	var names: Array = world.road_names()
	for name in names:
		var rs := world.road_samples(name)
		if rs.is_empty() or rs.centers.size() < 2:
			continue
		var c: PackedVector3Array = rs.centers
		_road_graph[name] = {
			"centers": c,
			"p0": Vector2(c[0].x, c[0].z),
			"p1": Vector2(c[c.size() - 1].x, c[c.size() - 1].z),
			"tangent0": rs.tangents[0],
			"neighbors": []
		}
	# Connect road neighbors whose endpoints are close (junctions)
	for r1 in _road_graph.keys():
		var data1: Dictionary = _road_graph[r1]
		for r2 in _road_graph.keys():
			if r1 == r2:
				continue
			var data2: Dictionary = _road_graph[r2]
			var d00: float = data1.p0.distance_to(data2.p0)
			var d01: float = data1.p0.distance_to(data2.p1)
			var d10: float = data1.p1.distance_to(data2.p0)
			var d11: float = data1.p1.distance_to(data2.p1)
			if minf(minf(d00, d01), minf(d10, d11)) < 22.0:
				data1.neighbors.append(r2)
	_road_graph_built = true

func _world_to_screen(world_xz: Vector2) -> Vector2:
	var center := size * 0.5
	return center + (world_xz - _cam_pos) * _zoom

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var center := size * 0.5
	return _cam_pos + (screen_pos - center) / _zoom

func _process(delta: float) -> void:
	# Navigation Inputs
	var move := Vector2.ZERO
	# Analog Stick / D-Pad Panning
	if Input.is_action_pressed("ui_left") or Pad.held("steer_left"):
		move.x -= 1.0
	if Input.is_action_pressed("ui_right") or Pad.held("steer_right"):
		move.x += 1.0
	if Input.is_action_pressed("ui_up"):
		move.y -= 1.0
	if Input.is_action_pressed("ui_down"):
		move.y += 1.0
	if Pad.device >= 0:
		var lx := Input.get_joy_axis(Pad.device, JOY_AXIS_LEFT_X)
		var ly := Input.get_joy_axis(Pad.device, JOY_AXIS_LEFT_Y)
		if absf(lx) > 0.15:
			move.x += lx
		if absf(ly) > 0.15:
			move.y += ly

	var pan_speed := 1400.0 / maxf(_zoom, 0.2)
	_target_cam_pos += move.normalized() * (pan_speed * delta) if move.length_squared() > 0.01 else Vector2.ZERO

	# Zooming
	if Pad.pressed("rewind") or Input.is_action_just_pressed("ui_page_up"):
		_target_zoom = clampf(_target_zoom * 1.35, 0.25, 2.5)
	if Pad.pressed("camera") or Input.is_action_just_pressed("ui_page_down"):
		_target_zoom = clampf(_target_zoom / 1.35, 0.25, 2.5)

	# Smooth camera interpolation
	_cam_pos = _cam_pos.lerp(_target_cam_pos, clampf(delta * 14.0, 0.0, 1.0))
	_zoom = lerpf(_zoom, _target_zoom, clampf(delta * 14.0, 0.0, 1.0))

	# Center on Car
	if Pad.pressed("shift_up") or Input.is_key_pressed(KEY_Y):
		if player:
			_target_cam_pos = Vector2(player.global_position.x, player.global_position.z)

	# Close Map
	var is_closing := false
	if Time.get_ticks_msec() - _open_time > 180:
		if Pad.pressed("pause") or Pad.pressed("map") or Input.is_action_just_pressed("ui_cancel"):
			is_closing = true
		elif Input.is_key_pressed(KEY_ESCAPE) or (Input.is_key_pressed(KEY_M) and Time.get_ticks_msec() - _open_time > 300):
			is_closing = true
		elif Pad.device >= 0 and (Input.is_joy_button_pressed(Pad.device, JOY_BUTTON_B) or Input.is_joy_button_pressed(Pad.device, JOY_BUTTON_START)):
			is_closing = true
	if is_closing:
		_close()
		return

	# Query Cursor Hover
	var cursor_world := _cam_pos # screen center
	_update_hover(cursor_world)

	# Actions: Waypoint / Fast Travel
	if Pad.pressed("handbrake") or Input.is_action_just_pressed("ui_accept"):
		_handle_select(cursor_world)
	elif Pad.pressed("shift_down") or Input.is_key_pressed(KEY_X):
		_handle_fast_travel(cursor_world)

	queue_redraw()

func _close() -> void:
	closed.emit()
	queue_free()

func _update_hover(cursor_world: Vector2) -> void:
	var best_dist := 120.0 / _zoom
	var found := {}
	# Check Events
	if markers:
		for m in markers.markers:
			var d := cursor_world.distance_to(Vector2(m.pos.x, m.pos.z))
			if d < best_dist:
				best_dist = d
				found = {"type": "event", "data": m, "pos": m.pos}
	# Check Activities
	if activities and found.is_empty():
		for it in activities.items:
			var d := cursor_world.distance_to(Vector2(it.pos.x, it.pos.z))
			if d < best_dist:
				best_dist = d
				found = {"type": "activity", "data": it, "pos": it.pos}
	# Check Barns
	if activities and found.is_empty():
		for b in activities.barns:
			var d := cursor_world.distance_to(Vector2(b.pos.x, b.pos.z))
			if d < best_dist:
				best_dist = d
				found = {"type": "barn", "data": b, "pos": b.pos}

	_hovered_item = found
	var district_id := world.district_at(cursor_world.x, cursor_world.y) if world else 0
	_district_lbl.text = world.district_name(district_id).to_upper() if world else ""

	if not found.is_empty():
		_card_panel.visible = true
		match found.type:
			"event":
				var ev: Dictionary = found.data.event
				_title_lbl.text = ev.get("name", "Event").to_upper()
				_type_lbl.text = "EVENT · %s" % EventData.TYPE_NAMES[ev.get("type", 0)]
				var rec: Dictionary = Profile.data.records.get(ev.get("id", ""), {})
				var wins: int = int(rec.get("wins", 0))
				var best_t: float = float(rec.get("best_time", -1.0))
				var time_str := "None" if best_t <= 0.0 else "%d:%05.2f" % [int(best_t / 60.0), fmod(best_t, 60.0)]
				_stats_lbl.text = "Wins: %d   Best: %s\nClass Max: %s   Rivals: %d" % [wins, time_str, CarData.CLASS_NAMES[int(ev.get("class_max", 6))], int(ev.get("rivals", 1))]
				_prompt_lbl.text = "A: Set GPS Waypoint   X: Fast Travel"
			"activity":
				var it: Dictionary = found.data
				_title_lbl.text = Activities.KIND_NAMES[it.kind].to_upper()
				_type_lbl.text = "PR STUNT · %s" % it.get("road", "").replace("_", " ").to_upper()
				var rec: Dictionary = Profile.data.records.get(it.id, {"best": 0.0, "stars": 0})
				var unit := "km/h" if it.kind in [0, 1] else ("pts" if it.kind == 2 else "m")
				var stars: int = int(rec.get("stars", 0))
				_stats_lbl.text = "Personal Best: %d %s\nRating: %s" % [int(rec.best), unit, "★".repeat(stars) + "☆".repeat(3 - stars)]
				_prompt_lbl.text = "A: Set GPS Waypoint"
			"barn":
				var b: Dictionary = found.data
				var discovered: bool = Profile.data.get("barns", []).has(b.id)
				_title_lbl.text = b.name.to_upper() if discovered else "BARN FIND RUMOR"
				_type_lbl.text = "BARN FIND · %s" % ("RESTORED" if discovered else "UNDISCOVERED")
				_stats_lbl.text = "Vehicle: %s" % (CarData.get_car(b.car).name if discovered else "???")
				_prompt_lbl.text = "A: Set GPS Waypoint"
	else:
		_title_lbl.text = "FREE NAVIGATION"
		_type_lbl.text = "COORDINATES: %d, %d" % [int(cursor_world.x), int(cursor_world.y)]
		_stats_lbl.text = "Set a GPS route to any road or landmark in Japan."
		_prompt_lbl.text = "A: Set GPS Waypoint   X: Fast Travel to Road"

func _handle_select(cursor_world: Vector2) -> void:
	var target_3d := Vector3(cursor_world.x, 0, cursor_world.y)
	if not _hovered_item.is_empty():
		target_3d = _hovered_item.pos

	if _gps_waypoint != Vector3.INF and _gps_waypoint.distance_to(target_3d) < 40.0:
		# Toggle off
		_gps_waypoint = Vector3.INF
		_gps_polyline.clear()
		waypoint_set.emit(Vector3.INF, _gps_polyline)
		return

	_gps_waypoint = target_3d
	_calculate_gps_path()

func _calculate_gps_path() -> void:
	if player == null or world == null or _gps_waypoint == Vector3.INF:
		return
	var start_pos := player.global_position
	var end_pos := _gps_waypoint
	var r_start: Dictionary = world.nearest_road(start_pos, 400.0)
	var r_end: Dictionary = world.nearest_road(end_pos, 400.0)

	_gps_polyline.clear()
	_gps_polyline.append(Vector2(start_pos.x, start_pos.z))

	if not r_start.is_empty() and not r_end.is_empty() and _road_graph.has(r_start.road) and _road_graph.has(r_end.road):
		var path_roads := _find_road_path(r_start.road, r_end.road)
		for r_name in path_roads:
			var data: Dictionary = _road_graph[r_name]
			var c: PackedVector3Array = data.centers
			for pt in c:
				_gps_polyline.append(Vector2(pt.x, pt.z))

	_gps_polyline.append(Vector2(end_pos.x, end_pos.z))
	waypoint_set.emit(_gps_waypoint, _gps_polyline)

func _find_road_path(start_road: String, goal_road: String) -> Array:
	if start_road == goal_road:
		return [start_road]
	var queue := [[start_road]]
	var visited := {start_road: true}
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var curr: String = path[path.size() - 1]
		if curr == goal_road:
			return path
		var neighbors: Array = _road_graph.get(curr, {}).get("neighbors", [])
		for n in neighbors:
			if not visited.has(n):
				visited[n] = true
				var new_path := path.duplicate()
				new_path.append(n)
				queue.append(new_path)
				if queue.size() > 250:
					break
	return [start_road, goal_road]

func _handle_fast_travel(cursor_world: Vector2) -> void:
	var target_3d := Vector3(cursor_world.x, 0, cursor_world.y)
	if not _hovered_item.is_empty():
		target_3d = _hovered_item.pos
	var nearest := world.nearest_road(target_3d, 400.0)
	if nearest.is_empty():
		return
	var dir: Vector3 = nearest.tangent
	var spawn_pos: Vector3 = nearest.position + Vector3(0, 1.2, 0)
	fast_travel_requested.emit(spawn_pos, dir)
	_close()

func _draw() -> void:
	var vp_size := size
	var center := vp_size * 0.5

	# Draw background Map Texture
	if _tex:
		var span := maxf(_bounds.size.x, _bounds.size.y)
		var map_screen_top_left := _world_to_screen(Vector2(_bounds.position.x, _bounds.position.y))
		var map_screen_size := Vector2(span * _zoom, span * _zoom)
		draw_texture_rect(_tex, Rect2(map_screen_top_left, map_screen_size), false)

	# Draw GPS Navigation Route Polyline
	if _gps_polyline.size() > 1:
		var screen_pts := PackedVector2Array()
		for pt in _gps_polyline:
			screen_pts.append(_world_to_screen(pt))
		# Outer glow
		draw_polyline(screen_pts, Color(0.15, 0.85, 1.0, 0.4), 8.0, true)
		# Core bright neon line
		draw_polyline(screen_pts, Color(0.2, 1.0, 0.8, 0.95), 4.0, true)

	# Draw Events
	if markers:
		for m in markers.markers:
			var sp := _world_to_screen(Vector2(m.pos.x, m.pos.z))
			var col := EventMarkers._color_for(m.event.type)
			var is_hover: bool = (_hovered_item.get("data") == m)
			var r := 9.0 if is_hover else 6.5
			draw_circle(sp, r + 2.0, Color.BLACK)
			draw_circle(sp, r, col)
			if is_hover:
				draw_arc(sp, r + 5.0, 0, TAU, 24, Color.WHITE, 2.0, true)

	# Draw Activities (PR Stunts)
	if activities:
		for it in activities.items:
			var sp := _world_to_screen(Vector2(it.pos.x, it.pos.z))
			var col: Color = Activities.KIND_COLORS[it.kind]
			var is_hover: bool = (_hovered_item.get("data") == it)
			var s := 12.0 if is_hover else 8.0
			draw_rect(Rect2(sp - Vector2(s * 0.5 + 1.5, s * 0.5 + 1.5), Vector2(s + 3.0, s + 3.0)), Color.BLACK)
			draw_rect(Rect2(sp - Vector2(s * 0.5, s * 0.5), Vector2(s, s)), col)

	# Draw Barn Finds
	if activities:
		for b in activities.barns:
			var sp := _world_to_screen(Vector2(b.pos.x, b.pos.z))
			var is_hover: bool = (_hovered_item.get("data") == b)
			var r := 8.0 if is_hover else 6.0
			draw_circle(sp, r + 2.0, Color.BLACK)
			draw_circle(sp, r, Color(0.9, 0.6, 0.2))

	# Draw GPS Destination Pin
	if _gps_waypoint != Vector3.INF:
		var wp_sp := _world_to_screen(Vector2(_gps_waypoint.x, _gps_waypoint.z))
		draw_circle(wp_sp, 8.0, Color(0.15, 1.0, 0.5))
		draw_circle(wp_sp, 14.0, Color(0.15, 1.0, 0.5, 0.35))
		draw_line(wp_sp, wp_sp + Vector2(0, -26), Color(0.15, 1.0, 0.5), 3.0)

	# Draw Player Car Arrow
	if player:
		var p_sp := _world_to_screen(Vector2(player.global_position.x, player.global_position.z))
		var fwd := -player.global_basis.z
		var heading := atan2(fwd.x, -fwd.z)
		var pts := PackedVector2Array([Vector2(0, -14), Vector2(9, 10), Vector2(0, 4), Vector2(-9, 10)])
		var rotated_pts := PackedVector2Array()
		for pt in pts:
			rotated_pts.append(p_sp + pt.rotated(heading))
		draw_arc(p_sp, 18.0, 0, TAU, 32, Color(1.0, 1.0, 1.0, 0.5), 1.5, true)
		draw_colored_polygon(rotated_pts, Color(1.0, 0.2, 0.5))
		draw_polyline(rotated_pts, Color.WHITE, 1.5, true)

	# Central Crosshair Reticle
	draw_line(center - Vector2(16, 0), center - Vector2(5, 0), Color(1, 1, 1, 0.7), 2.0)
	draw_line(center + Vector2(5, 0), center + Vector2(16, 0), Color(1, 1, 1, 0.7), 2.0)
	draw_line(center - Vector2(0, 16), center - Vector2(0, 5), Color(1, 1, 1, 0.7), 2.0)
	draw_line(center + Vector2(0, 5), center + Vector2(0, 16), Color(1, 1, 1, 0.7), 2.0)
	draw_arc(center, 7.0, 0, TAU, 16, Color(1, 1, 1, 0.6), 1.5, true)
