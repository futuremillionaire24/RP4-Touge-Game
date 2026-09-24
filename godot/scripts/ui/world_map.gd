extends CanvasLayer
## Full-Screen Interactive World Map with GPS Road Navigation, Fast Travel, and Event Inspection.
## Built for Retroid Pocket 4 Pro with Forza Horizon / Gran Turismo style vector road topology,
## smooth analog pan/zoom, category filters, and 3D in-world GPS ribbon projection.

signal closed
signal waypoint_set(pos: Vector3, polyline: PackedVector2Array, centers_3d: PackedVector3Array, ups_3d: PackedVector3Array)
signal fast_travel_requested(pos: Vector3, dir: Vector3)

enum FilterTab { ALL, RACES, PR_STUNTS, BARN_FINDS }

var world: NTWorld
var player: CarView
var markers: EventMarkers
var activities: Activities
var freeroam_host: Node

var _bounds: Rect2
var _cam_pos := Vector2.ZERO
var _target_cam_pos := Vector2.ZERO
var _cam_velocity := Vector2.ZERO
var _zoom := 0.65
var _target_zoom := 0.65

var _hovered_item := {}
var _gps_waypoint := Vector3.INF
var _gps_polyline := PackedVector2Array()
var _gps_centers_3d := PackedVector3Array()
var _gps_ups_3d := PackedVector3Array()

var _road_graph := {}
var _cached_road_vectors := [] # Array of {kind, points: PackedVector2Array, color, width}
var _road_graph_built := false
var _open_time := 0
var _active_tab := FilterTab.ALL

# UI Nodes
var _view: Control
var _card_panel: PanelContainer
var _title_lbl: Label
var _type_lbl: Label
var _stats_lbl: Label
var _prompt_lbl: Label
var _district_lbl: Label
var _legend_lbl: Label
var _tab_labels: Array[Label] = []
var _tab_container: HBoxContainer
var _tex: ImageTexture

func _init() -> void:
	layer = 25 # Render cleanly above PauseMenu (layer 20) and DriveHUD (layer 2)
	process_mode = Node.PROCESS_MODE_ALWAYS

func setup(p_world: NTWorld, p_player: CarView, p_markers: EventMarkers, p_activities: Activities, p_host: Node) -> void:
	world = p_world
	player = p_player
	markers = p_markers
	activities = p_activities
	freeroam_host = p_host
	if world:
		_bounds = world.bounds()
	if player:
		_cam_pos = Vector2(player.global_position.x, player.global_position.z)
		_target_cam_pos = _cam_pos
	_build_road_graph()
	if _view:
		_view.queue_redraw()

func _ready() -> void:
	_open_time = Time.get_ticks_msec()
	_build_ui()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()

func _on_viewport_resized() -> void:
	if _view:
		var vp_size := get_viewport().get_visible_rect().size
		_view.custom_minimum_size = vp_size

func _build_ui() -> void:
	_view = Control.new()
	_view.name = "MapView"
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_PASS
	_view.draw.connect(_on_view_draw)
	add_child(_view)

	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x < 100.0 or vp_size.y < 100.0:
		vp_size = Vector2(1334, 750)
	_view.custom_minimum_size = vp_size

	# Top Bar Container
	var top_bar := VBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_top = 18.0
	top_bar.add_theme_constant_override("separation", 6)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(top_bar)

	# District Header
	_district_lbl = Label.new()
	_district_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_district_lbl.add_theme_font_size_override("font_size", 26)
	_district_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_district_lbl.add_theme_constant_override("outline_size", 8)
	_district_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_district_lbl.text = "PORT HERCULE · MONACO"
	top_bar.add_child(_district_lbl)

	# Filter Tabs (Forza Horizon style L1/R1)
	_tab_container = HBoxContainer.new()
	_tab_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_container.add_theme_constant_override("separation", 24)
	top_bar.add_child(_tab_container)

	var tab_names := ["ALL", "RACES", "PR STUNTS", "BARN FINDS"]
	for i in range(tab_names.size()):
		var lbl := Label.new()
		lbl.text = "[ %s ]" % tab_names[i]
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_constant_override("outline_size", 6)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_tab_container.add_child(lbl)
		_tab_labels.append(lbl)
	_update_tab_visuals()

	# Info Card (top right glassmorphic panel)
	_card_panel = PanelContainer.new()
	_card_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_card_panel.offset_left = -390.0
	_card_panel.offset_top = 22.0
	_card_panel.offset_right = -24.0
	_card_panel.offset_bottom = 230.0
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.1, 0.9)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.1, 0.85, 0.95, 0.7)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 18
	sb.content_margin_top = 14
	sb.content_margin_right = 18
	sb.content_margin_bottom = 14
	_card_panel.add_theme_stylebox_override("panel", sb)
	_view.add_child(_card_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	_card_panel.add_child(vb)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 18)
	_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	vb.add_child(_title_lbl)

	_type_lbl = Label.new()
	_type_lbl.add_theme_font_size_override("font_size", 13)
	_type_lbl.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
	vb.add_child(_type_lbl)

	_stats_lbl = Label.new()
	_stats_lbl.add_theme_font_size_override("font_size", 12)
	_stats_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	_stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_stats_lbl)

	_prompt_lbl = Label.new()
	_prompt_lbl.add_theme_font_size_override("font_size", 12)
	_prompt_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	vb.add_child(_prompt_lbl)

	# Bottom Legend Bar
	_legend_lbl = Label.new()
	_legend_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_legend_lbl.offset_bottom = -16.0
	_legend_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legend_lbl.add_theme_font_size_override("font_size", 14)
	_legend_lbl.add_theme_color_override("font_color", Color(0.92, 0.94, 0.97))
	_legend_lbl.add_theme_constant_override("outline_size", 6)
	_legend_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_legend_lbl.text = "LS / D-PAD: Pan   RS / TRIGGERS: Zoom   L1/R1: Category   A: Set GPS   X: Fast Travel   Y: Center Car   B: Exit"
	_view.add_child(_legend_lbl)

func _update_tab_visuals() -> void:
	for i in range(_tab_labels.size()):
		var lbl: Label = _tab_labels[i]
		if i == _active_tab:
			lbl.add_theme_color_override("font_color", Color(0.15, 0.95, 1.0))
		else:
			lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))

func _build_road_graph() -> void:
	if _road_graph_built or world == null:
		return
	_road_graph.clear()
	_cached_road_vectors.clear()

	var names: Array = world.road_names()
	for name in names:
		var rs: Dictionary = world.road_samples(name)
		if rs.is_empty():
			continue
		var c: PackedVector3Array = rs.get("centers", PackedVector3Array())
		if c.size() < 2:
			continue
		var ups: PackedVector3Array = rs.get("ups", PackedVector3Array())
		var kind: int = int(rs.get("kind", 0))
		var district: int = int(rs.get("district", 0))

		_road_graph[name] = {
			"centers": c,
			"ups": ups,
			"p0": Vector2(c[0].x, c[0].z),
			"p1": Vector2(c[c.size() - 1].x, c[c.size() - 1].z),
			"kind": kind,
			"district": district,
			"neighbors": []
		}

		# Precalculate 2D polyline points for vector drawing
		var poly2d := PackedVector2Array()
		poly2d.resize(c.size())
		for idx in range(c.size()):
			poly2d[idx] = Vector2(c[idx].x, c[idx].z)

		var col := Color(0.68, 0.74, 0.86, 0.85)
		var width := 2.6
		match kind:
			1: # RK_EXPRESSWAY / AUTOROUTE
				col = Color(0.96, 0.48, 0.16, 0.95)
				width = 4.2
			2: # RK_RAMP
				col = Color(0.88, 0.6, 0.3, 0.85)
				width = 2.6
			3: # RK_AVENUE / COASTAL BOULEVARD
				col = Color(0.92, 0.96, 1.0, 0.95)
				width = 3.4
			4: # RK_TOUGE / CORNICHE PASS
				col = Color(1.0, 0.82, 0.22, 0.95)
				width = 3.6
			5: # RK_FARM / HILLSIDE LANE
				col = Color(0.72, 0.62, 0.48, 0.8)
				width = 2.2
			_:
				col = Color(0.7, 0.75, 0.85, 0.8)
				width = 2.5

		_cached_road_vectors.append({
			"name": name,
			"kind": kind,
			"points": poly2d,
			"color": col,
			"width": width
		})

	# Connect road neighbors whose endpoints are close (junctions)
	var road_keys: Array = _road_graph.keys()
	for i in range(road_keys.size()):
		var r1: String = road_keys[i]
		var data1: Dictionary = _road_graph[r1]
		for j in range(i + 1, road_keys.size()):
			var r2: String = road_keys[j]
			var data2: Dictionary = _road_graph[r2]
			var d00: float = data1.p0.distance_to(data2.p0)
			var d01: float = data1.p0.distance_to(data2.p1)
			var d10: float = data1.p1.distance_to(data2.p0)
			var d11: float = data1.p1.distance_to(data2.p1)
			if minf(minf(d00, d01), minf(d10, d11)) < 26.0:
				data1.neighbors.append(r2)
				data2.neighbors.append(r1)

	_road_graph_built = true

func _world_to_screen(world_xz: Vector2) -> Vector2:
	var vp_size := _view.size if _view else Vector2(1334, 750)
	var center := vp_size * 0.5
	return center + (world_xz - _cam_pos) * _zoom

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var vp_size := _view.size if _view else Vector2(1334, 750)
	var center := vp_size * 0.5
	return _cam_pos + (screen_pos - center) / _zoom

func _process(delta: float) -> void:
	if _view == null:
		return

	# Navigation Inputs
	var move := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Pad.held("steer_left") or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_action_pressed("ui_right") or Pad.held("steer_right") or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1.0

	if Pad.device >= 0:
		var lx := Input.get_joy_axis(Pad.device, JOY_AXIS_LEFT_X)
		var ly := Input.get_joy_axis(Pad.device, JOY_AXIS_LEFT_Y)
		if absf(lx) > 0.15:
			move.x += lx
		if absf(ly) > 0.15:
			move.y += ly

	var pan_speed := 1600.0 / maxf(_zoom, 0.15)
	if move.length_squared() > 0.01:
		_cam_velocity = _cam_velocity.lerp(move.normalized() * pan_speed, clampf(delta * 12.0, 0.0, 1.0))
	else:
		_cam_velocity = _cam_velocity.lerp(Vector2.ZERO, clampf(delta * 10.0, 0.0, 1.0))
	_target_cam_pos += _cam_velocity * delta

	# Zooming via Right Stick, Triggers, or PageUp/Down
	var zoom_delta := 0.0
	if Pad.device >= 0:
		var ry := Input.get_joy_axis(Pad.device, JOY_AXIS_RIGHT_Y)
		if absf(ry) > 0.15:
			zoom_delta -= ry * 2.2 * delta
		var rt := Input.get_joy_axis(Pad.device, JOY_AXIS_TRIGGER_RIGHT)
		var lt := Input.get_joy_axis(Pad.device, JOY_AXIS_TRIGGER_LEFT)
		if rt > 0.1:
			zoom_delta += rt * 2.0 * delta
		if lt > 0.1:
			zoom_delta -= lt * 2.0 * delta

	if Input.is_action_just_pressed("ui_page_up") or Input.is_key_pressed(KEY_EQUAL):
		zoom_delta += 0.35
	if Input.is_action_just_pressed("ui_page_down") or Input.is_key_pressed(KEY_MINUS):
		zoom_delta -= 0.35

	if zoom_delta != 0.0:
		_target_zoom = clampf(_target_zoom * (1.0 + zoom_delta), 0.18, 3.2)

	# Tab Switching (L1/R1 or Q/E)
	if Pad.pressed("rewind") or Input.is_key_pressed(KEY_Q):
		_active_tab = posmod(_active_tab - 1, 4) as FilterTab
		_update_tab_visuals()
	elif Pad.pressed("camera") or Input.is_key_pressed(KEY_E):
		_active_tab = posmod(_active_tab + 1, 4) as FilterTab
		_update_tab_visuals()

	# Smooth camera & zoom interpolation
	_cam_pos = _cam_pos.lerp(_target_cam_pos, clampf(delta * 14.0, 0.0, 1.0))
	_zoom = lerpf(_zoom, _target_zoom, clampf(delta * 14.0, 0.0, 1.0))

	# Center on Player Car (Y button)
	if Pad.pressed("shift_up") or Input.is_key_pressed(KEY_Y):
		if player:
			_target_cam_pos = Vector2(player.global_position.x, player.global_position.z)

	# Actions: Waypoint / Fast Travel
	var cursor_world := _cam_pos
	_update_hover(cursor_world)

	if Pad.pressed("handbrake") or Input.is_action_just_pressed("ui_accept"):
		_handle_select(cursor_world)
	elif Pad.pressed("shift_down") or Input.is_key_pressed(KEY_X):
		_handle_fast_travel(cursor_world)

	_view.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if Time.get_ticks_msec() - _open_time < 220:
		return
	var is_back := false
	if event is InputEventJoypadButton and event.pressed:
		var btn: int = (event as InputEventJoypadButton).button_index
		if btn == JOY_BUTTON_B or btn == JOY_BUTTON_BACK or btn == JOY_BUTTON_START or btn == JOY_BUTTON_RIGHT_STICK:
			is_back = true
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).physical_keycode
		if k == KEY_ESCAPE or k == KEY_M or k == KEY_BACKSPACE:
			is_back = true
	elif event.is_action_pressed("ui_cancel"):
		is_back = true

	if is_back:
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	closed.emit()
	queue_free()

func _update_hover(cursor_world: Vector2) -> void:
	var best_dist := 110.0 / _zoom
	var found := {}

	# Check Events (if active in filter)
	if markers and (_active_tab == FilterTab.ALL or _active_tab == FilterTab.RACES):
		for m in markers.markers:
			var d := cursor_world.distance_to(Vector2(m.pos.x, m.pos.z))
			if d < best_dist:
				best_dist = d
				found = {"type": "event", "data": m, "pos": m.pos}

	# Check Activities (if active in filter)
	if activities and found.is_empty() and (_active_tab == FilterTab.ALL or _active_tab == FilterTab.PR_STUNTS):
		for it in activities.items:
			var d := cursor_world.distance_to(Vector2(it.pos.x, it.pos.z))
			if d < best_dist:
				best_dist = d
				found = {"type": "activity", "data": it, "pos": it.pos}

	# Check Barns (if active in filter)
	if activities and found.is_empty() and (_active_tab == FilterTab.ALL or _active_tab == FilterTab.BARN_FINDS):
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
				var ev_type: int = int(ev.get("type", 0))
				var type_name: String = EventData.TYPE_NAMES[ev_type] if ev_type < EventData.TYPE_NAMES.size() else "RACE"
				_type_lbl.text = "EVENT · %s" % type_name
				var rec: Dictionary = Profile.data.records.get(ev.get("id", ""), {})
				var wins: int = int(rec.get("wins", 0))
				var best_t: float = float(rec.get("best_time", -1.0))
				var time_str := "None" if best_t <= 0.0 else "%d:%05.2f" % [int(best_t / 60.0), fmod(best_t, 60.0)]
				var c_idx: int = int(ev.get("class_max", 6))
				var c_name: String = CarData.CLASS_NAMES[c_idx] if c_idx < CarData.CLASS_NAMES.size() else "X"
				var r_info: Dictionary = RaceRoutes.get_route(ev.get("id", ""))
				var len_km: float = float(r_info.get("length_m", 0)) / 1000.0
				var turns_n: int = int(r_info.get("turns_count", 0))
				var elev_g: int = int(r_info.get("elev_gain", 0))
				_stats_lbl.text = "%.2f km · %d turns · ▲%dm\nClass: ≤%s · Rivals: %d · Wins: %d%s" % [
					len_km, turns_n, elev_g, c_name, int(ev.get("rivals", 1)), wins,
					(" · Best: " + time_str) if time_str != "None" else ""
				]
				_prompt_lbl.text = "A: Set GPS Waypoint   X: Fast Travel"
			"activity":
				var it: Dictionary = found.data
				var k_idx: int = int(it.get("kind", 0))
				var k_name: String = Activities.KIND_NAMES[k_idx] if k_idx < Activities.KIND_NAMES.size() else "STUNT"
				_title_lbl.text = k_name.to_upper()
				_type_lbl.text = "PR STUNT · %s" % it.get("road", "").replace("_", " ").to_upper()
				var rec: Dictionary = Profile.data.records.get(it.get("id", ""), {})
				var unit := "km/h" if k_idx in [0, 1] else ("pts" if k_idx == 2 else "m")
				var best_val: float = float(rec.get("best", 0.0))
				var stars: int = clampi(int(rec.get("stars", 0)), 0, 3)
				_stats_lbl.text = "Personal Best: %d %s\nRating: %s" % [int(best_val), unit, "★".repeat(stars) + "☆".repeat(3 - stars)]
				_prompt_lbl.text = "A: Set GPS Waypoint"
			"barn":
				var b: Dictionary = found.data
				var discovered: bool = Profile.data.get("barns", []).has(b.get("id", ""))
				_title_lbl.text = b.get("name", "Barn").to_upper() if discovered else "BARN FIND RUMOR"
				_type_lbl.text = "BARN FIND · %s" % ("RESTORED" if discovered else "UNDISCOVERED")
				var car_spec := CarData.get_car(b.get("car", ""))
				_stats_lbl.text = "Vehicle: %s" % (car_spec.get("name", "???") if (discovered and not car_spec.is_empty()) else "???")
				_prompt_lbl.text = "A: Set GPS Waypoint"
	else:
		_title_lbl.text = "FREE NAVIGATION"
		_type_lbl.text = "COORDINATES: %d, %d" % [int(cursor_world.x), int(cursor_world.y)]
		_stats_lbl.text = "Explore the coastal avenues of Port Hercule, Monaco GP circuit, and the Grande Corniche hillclimb."
		_prompt_lbl.text = "A: Set GPS Waypoint   X: Fast Travel to Road"

func _handle_select(cursor_world: Vector2) -> void:
	var target_3d := Vector3(cursor_world.x, 0, cursor_world.y)
	if not _hovered_item.is_empty():
		target_3d = _hovered_item.pos

	if _gps_waypoint != Vector3.INF and _gps_waypoint.distance_to(target_3d) < 40.0:
		# Toggle off
		_gps_waypoint = Vector3.INF
		_gps_polyline.clear()
		_gps_centers_3d.clear()
		_gps_ups_3d.clear()
		waypoint_set.emit(Vector3.INF, _gps_polyline, _gps_centers_3d, _gps_ups_3d)
		return

	_gps_waypoint = target_3d
	_calculate_gps_path()

func _calculate_gps_path() -> void:
	if world == null or _gps_waypoint == Vector3.INF:
		return
	var start_pos := player.global_position if player != null else Vector3(_cam_pos.x, 0, _cam_pos.y)
	var end_pos := _gps_waypoint
	var r_start: Dictionary = world.nearest_road(start_pos, 500.0)
	var r_end: Dictionary = world.nearest_road(end_pos, 500.0)

	_gps_polyline.clear()
	_gps_centers_3d.clear()
	_gps_ups_3d.clear()

	_gps_polyline.append(Vector2(start_pos.x, start_pos.z))
	_gps_centers_3d.append(start_pos)
	_gps_ups_3d.append(Vector3.UP)

	if not r_start.is_empty() and not r_end.is_empty():
		var start_road: String = r_start.get("road", "")
		var end_road: String = r_end.get("road", "")
		if _road_graph.has(start_road) and _road_graph.has(end_road):
			var path_roads := _find_road_path(start_road, end_road)
			for r_name in path_roads:
				var data: Dictionary = _road_graph[r_name]
				var c: PackedVector3Array = data.centers
				var ups: PackedVector3Array = data.ups
				for idx in range(c.size()):
					_gps_polyline.append(Vector2(c[idx].x, c[idx].z))
					_gps_centers_3d.append(c[idx])
					if idx < ups.size():
						_gps_ups_3d.append(ups[idx])
					else:
						_gps_ups_3d.append(Vector3.UP)

	_gps_polyline.append(Vector2(end_pos.x, end_pos.z))
	_gps_centers_3d.append(end_pos)
	_gps_ups_3d.append(Vector3.UP)

	waypoint_set.emit(_gps_waypoint, _gps_polyline, _gps_centers_3d, _gps_ups_3d)

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
				if queue.size() > 300:
					break
	return [start_road, goal_road]

func _handle_fast_travel(cursor_world: Vector2) -> void:
	var target_3d := Vector3(cursor_world.x, 0, cursor_world.y)
	if not _hovered_item.is_empty():
		target_3d = _hovered_item.pos
	var nearest: Dictionary = world.nearest_road(target_3d, 500.0)
	if nearest.is_empty():
		return
	var dir: Vector3 = nearest.get("tangent", Vector3.FORWARD)
	var spawn_pos: Vector3 = nearest.get("position", target_3d) + Vector3(0, 1.2, 0)
	fast_travel_requested.emit(spawn_pos, dir)
	_close()

func _on_view_draw() -> void:
	var vp_size := _view.size
	var center := vp_size * 0.5

	# 1. Dark Nocturnal Ocean Backdrop
	_view.draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.02, 0.035, 0.07, 1.0))

	# 2. Island Landmass Background
	if _bounds.size.x > 0:
		var p_min := _world_to_screen(Vector2(_bounds.position.x, _bounds.position.y))
		var p_max := _world_to_screen(Vector2(_bounds.position.x + _bounds.size.x, _bounds.position.y + _bounds.size.y))
		var land_rect := Rect2(p_min, p_max - p_min)
		_view.draw_rect(land_rect, Color(0.06, 0.08, 0.12, 0.95))
		_view.draw_rect(land_rect, Color(0.12, 0.22, 0.35, 0.6), false, 2.0)

	# 3. Vector Road Network
	for road in _cached_road_vectors:
		var pts: PackedVector2Array = road.points
		if pts.size() < 2:
			continue
		var screen_pts := PackedVector2Array()
		screen_pts.resize(pts.size())
		for idx in range(pts.size()):
			screen_pts[idx] = _world_to_screen(pts[idx])
		
		# Draw road casing / dark edge for contrast
		var w: float = maxf(road.width * _zoom, 1.8)
		_view.draw_polyline(screen_pts, Color(0.02, 0.02, 0.04, 0.8), w + 2.0, true)
		# Draw colored core road line
		_view.draw_polyline(screen_pts, road.color, w, true)

	# 4. GPS Navigation Route Polyline
	if _gps_polyline.size() > 1:
		var screen_pts := PackedVector2Array()
		screen_pts.resize(_gps_polyline.size())
		for idx in range(_gps_polyline.size()):
			screen_pts[idx] = _world_to_screen(_gps_polyline[idx])
		# Neon cyan glow
		_view.draw_polyline(screen_pts, Color(0.0, 0.9, 1.0, 0.4), 9.0 * _zoom + 4.0, true)
		# Core bright pulse
		_view.draw_polyline(screen_pts, Color(0.1, 1.0, 0.85, 0.95), 4.5 * _zoom + 2.0, true)

	# 4b. Live Race Course Vector Preview (Forza Horizon style course highlight)
	var active_ev_id := ""
	if not _hovered_item.is_empty() and _hovered_item.get("type", "") == "event":
		active_ev_id = _hovered_item.data.event.get("id", "")
	if not active_ev_id.is_empty():
		var r_data: Dictionary = RaceRoutes.get_route(active_ev_id)
		var raw_pts: Array = r_data.get("points", [])
		if raw_pts.size() > 1:
			var pts := PackedVector2Array()
			pts.resize(raw_pts.size())
			for i in range(raw_pts.size()):
				pts[i] = _world_to_screen(Vector2(raw_pts[i][0], raw_pts[i][1]))

			var is_closed: bool = bool(r_data.get("closed", false))
			var col_glow := Color(0.96, 0.65, 0.12, 0.45) if is_closed else Color(0.12, 0.88, 1.0, 0.45)
			var col_line := Color(1.0, 0.84, 0.24, 0.95) if is_closed else Color(0.35, 0.95, 1.0, 0.95)

			# Outer glow casing
			_view.draw_polyline(pts, col_glow, 11.0 * _zoom + 5.0, true)
			# Crisp track surface
			_view.draw_polyline(pts, col_line, 4.8 * _zoom + 2.0, true)
			if is_closed and pts.size() > 2:
				_view.draw_line(pts[pts.size() - 1], pts[0], col_line, 4.8 * _zoom + 2.0, true)

			# Animated directional chevrons along course
			var pulse := fmod(Time.get_ticks_msec() * 0.0025, 1.0)
			var step := maxi(2, pts.size() / 12)
			for i in range(0, pts.size() - 1, step):
				var p0: Vector2 = pts[i]
				var p1: Vector2 = pts[i + 1]
				var d := (p1 - p0).normalized()
				if d.length_squared() > 0.01:
					var mid := p0.lerp(p1, pulse)
					var perp := d.orthogonal() * (3.8 * _zoom + 1.8)
					var tri := PackedVector2Array([
						mid + d * (5.5 * _zoom + 2.0),
						mid - d * (3.5 * _zoom + 1.2) + perp,
						mid - d * (3.5 * _zoom + 1.2) - perp
					])
					_view.draw_colored_polygon(tri, Color.WHITE)

			# Hairpin badges on world map
			var turns: Array = r_data.get("turns", [])
			var c_num := 1
			for t in turns:
				if bool(t.get("hairpin", false)):
					var hp_scr := _world_to_screen(Vector2(t.pos[0], t.pos[1]))
					_view.draw_circle(hp_scr, 7.5, Color(0.88, 0.16, 0.16, 0.95))
					_view.draw_arc(hp_scr, 7.5, 0, TAU, 16, Color.WHITE, 1.2)
					_view.draw_string(ThemeDB.fallback_font, hp_scr + Vector2(-3.5, 3.5), "%d" % c_num, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)
					c_num += 1

			# Start / Finish indicators
			var start_p: Vector2 = pts[0]
			_view.draw_circle(start_p, 8.5 * _zoom + 3.0, Color.BLACK)
			_view.draw_circle(start_p, 6.5 * _zoom + 2.0, Color(0.2, 0.95, 0.35))
			if not is_closed:
				var finish_p: Vector2 = pts[pts.size() - 1]
				_view.draw_circle(finish_p, 8.5 * _zoom + 3.0, Color.BLACK)
				_view.draw_circle(finish_p, 6.5 * _zoom + 2.0, Color(0.95, 0.25, 0.25))

	# 5. Events (Filter: ALL or RACES)
	if markers and (_active_tab == FilterTab.ALL or _active_tab == FilterTab.RACES):
		for m in markers.markers:
			var sp := _world_to_screen(Vector2(m.pos.x, m.pos.z))
			var is_hover: bool = (_hovered_item.get("data") == m)
			var col: Color = EventMarkers._color_for(m.event.get("type", 0))
			var r := 9.0 if is_hover else 6.5
			_view.draw_circle(sp, r + 2.0, Color.BLACK)
			_view.draw_circle(sp, r, col)
			if is_hover:
				_view.draw_arc(sp, r + 5.0, 0, TAU, 24, Color.WHITE, 2.0, true)

	# 6. Activities / PR Stunts (Filter: ALL or PR_STUNTS)
	if activities and (_active_tab == FilterTab.ALL or _active_tab == FilterTab.PR_STUNTS):
		for it in activities.items:
			var sp := _world_to_screen(Vector2(it.pos.x, it.pos.z))
			var k_idx: int = int(it.get("kind", 0))
			var col: Color = Activities.KIND_COLORS[k_idx] if k_idx < Activities.KIND_COLORS.size() else Color.WHITE
			var is_hover: bool = (_hovered_item.get("data") == it)
			var s := 12.0 if is_hover else 8.0
			_view.draw_rect(Rect2(sp - Vector2(s * 0.5 + 1.5, s * 0.5 + 1.5), Vector2(s + 3.0, s + 3.0)), Color.BLACK)
			_view.draw_rect(Rect2(sp - Vector2(s * 0.5, s * 0.5), Vector2(s, s)), col)
			if is_hover:
				_view.draw_arc(sp, s * 0.8, 0, TAU, 16, Color.WHITE, 2.0, true)

	# 7. Barn Finds (Filter: ALL or BARN_FINDS)
	if activities and (_active_tab == FilterTab.ALL or _active_tab == FilterTab.BARN_FINDS):
		for b in activities.barns:
			var sp := _world_to_screen(Vector2(b.pos.x, b.pos.z))
			var is_hover: bool = (_hovered_item.get("data") == b)
			var r := 8.5 if is_hover else 6.0
			_view.draw_circle(sp, r + 2.0, Color.BLACK)
			_view.draw_circle(sp, r, Color(0.95, 0.65, 0.2))
			if is_hover:
				_view.draw_arc(sp, r + 4.5, 0, TAU, 16, Color.WHITE, 2.0, true)

	# 8. GPS Destination Pin
	if _gps_waypoint != Vector3.INF:
		var wp_sp := _world_to_screen(Vector2(_gps_waypoint.x, _gps_waypoint.z))
		var pulse := (sin(Time.get_ticks_msec() * 0.006) + 1.0) * 0.5
		_view.draw_circle(wp_sp, 8.0, Color(0.1, 1.0, 0.6))
		_view.draw_circle(wp_sp, 14.0 + pulse * 6.0, Color(0.1, 1.0, 0.6, 0.35))
		_view.draw_line(wp_sp, wp_sp + Vector2(0, -28), Color(0.1, 1.0, 0.6), 3.0)

	# 9. Player Car Arrow & Direction
	if player:
		var p_sp := _world_to_screen(Vector2(player.global_position.x, player.global_position.z))
		var fwd := -player.global_basis.z
		var heading := atan2(fwd.x, -fwd.z)
		var pts := PackedVector2Array([Vector2(0, -14), Vector2(9, 10), Vector2(0, 4), Vector2(-9, 10)])
		var rotated_pts := PackedVector2Array()
		for pt in pts:
			rotated_pts.append(p_sp + pt.rotated(heading))
		_view.draw_arc(p_sp, 18.0, 0, TAU, 32, Color(1.0, 1.0, 1.0, 0.6), 1.5, true)
		_view.draw_colored_polygon(rotated_pts, Color(1.0, 0.2, 0.5))
		_view.draw_polyline(rotated_pts, Color.WHITE, 1.5, true)

	# 10. Center Crosshair Reticle
	_view.draw_line(center - Vector2(18, 0), center - Vector2(5, 0), Color(1, 1, 1, 0.75), 2.0)
	_view.draw_line(center + Vector2(5, 0), center + Vector2(18, 0), Color(1, 1, 1, 0.75), 2.0)
	_view.draw_line(center - Vector2(0, 18), center - Vector2(0, 5), Color(1, 1, 1, 0.75), 2.0)
	_view.draw_line(center + Vector2(0, 5), center + Vector2(0, 18), Color(1, 1, 1, 0.75), 2.0)
	_view.draw_arc(center, 7.0, 0, TAU, 16, Color(1, 1, 1, 0.6), 1.5, true)
