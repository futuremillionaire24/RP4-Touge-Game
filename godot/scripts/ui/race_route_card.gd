class_name RaceRouteCard
extends Control
## High-definition Vector Race Map Preview Card.
## Renders the actual 2D track spline, direction arrows, start/finish line,
## sector checkpoints, hairpin warnings, and an elevation profile diagram.

var _route_data: Dictionary = {}
var _font: Font
var _cached_screen_pts: PackedVector2Array = PackedVector2Array()
var _pulse := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(560, 250)
	_font = ThemeDB.fallback_font
	resized.connect(_cache_points)

func set_event_id(id: String) -> void:
	_route_data = RaceRoutes.get_route(id)
	_cache_points()
	queue_redraw()

func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 2.5, TAU)
	queue_redraw()

var _cached_hairpins: Array = [] # Array of {pos: Vector2, num: int}

func _cache_points() -> void:
	_cached_screen_pts.clear()
	_cached_hairpins.clear()
	var raw_pts: Array = _route_data.get("points", [])
	if raw_pts.size() < 2:
		return
	
	var bbox: Array = _route_data.get("bbox", [0, 0, 100, 100])
	var min_x: float = bbox[0]
	var min_z: float = bbox[1]
	var w: float = maxf(bbox[2], 10.0)
	var h: float = maxf(bbox[3], 10.0)

	var cur_w := maxf(size.x, custom_minimum_size.x)
	var cur_h := maxf(size.y, custom_minimum_size.y)

	# Drawing area inside card (leave room for elevation profile at bottom)
	var map_rect := Rect2(20.0, 36.0, maxf(cur_w - 40.0, 100.0), maxf(cur_h - 106.0, 80.0))
	var scale_factor: float = minf(map_rect.size.x / w, map_rect.size.y / h) * 0.88
	var center_world := Vector2(min_x + w * 0.5, min_z + h * 0.5)
	var center_screen := map_rect.position + map_rect.size * 0.5

	for p in raw_pts:
		var pos_2d := Vector2(p[0], p[1])
		var offset := (pos_2d - center_world) * scale_factor
		_cached_screen_pts.append(center_screen + Vector2(offset.x, offset.y))

	var turns: Array = _route_data.get("turns", [])
	var corner_num := 1
	for t in turns:
		if bool(t.get("hairpin", false)):
			var p_world := Vector2(t.pos[0], t.pos[1])
			var scr_pos := center_screen + (p_world - center_world) * scale_factor
			_cached_hairpins.append({"pos": scr_pos, "num": corner_num})
			corner_num += 1

func _draw() -> void:
	var s := size
	# 1. Background Frosted Panel
	var bg_rect := Rect2(Vector2.ZERO, s)
	draw_rect(bg_rect, Color(0.08, 0.08, 0.12, 0.94), true)
	draw_rect(bg_rect, Color(1, 1, 1, 0.08), false, 1.0)
	# Amber-gold subtle top accent
	draw_rect(Rect2(0, 0, s.x, 3.0), UIKit.NEON)

	if _route_data.is_empty() or _cached_screen_pts.size() < 2:
		draw_string(_font, Vector2(s.x * 0.5 - 60, s.y * 0.5), "COURSE MAP", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, UIKit.DIM)
		return

	# 2. Track Route Drawing
	var pts := _cached_screen_pts
	var is_closed: bool = bool(_route_data.get("closed", false))

	# Underglow / Road base
	draw_polyline(pts, Color(0.04, 0.04, 0.06, 0.85), 8.0, true)
	draw_polyline(pts, Color(UIKit.NEON.r, UIKit.NEON.g, UIKit.NEON.b, 0.35), 6.0, true)

	# Main Racing Surface Line
	var track_col := UIKit.NEON if is_closed else Color(0.2, 0.85, 1.0)
	draw_polyline(pts, track_col, 3.2, true)

	# Closed loop connector if closed
	if is_closed and pts.size() > 2:
		draw_line(pts[pts.size() - 1], pts[0], track_col, 3.2, true)

	# 3. Directional Arrows along track (animated flow)
	var arrow_step := maxi(1, pts.size() / 6)
	var flow_shift := int((_pulse / TAU) * arrow_step)
	for i in range(flow_shift, pts.size() - 1, arrow_step):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var dir := (p1 - p0).normalized()
		if dir.length_squared() > 0.01:
			var mid := (p0 + p1) * 0.5
			var perp := dir.orthogonal() * 3.5
			var tri := PackedVector2Array([
				mid + dir * 4.5,
				mid - dir * 3.0 + perp,
				mid - dir * 3.0 - perp
			])
			draw_colored_polygon(tri, Color.WHITE)

	# 4. Hairpin / Sharp Corner Badges
	for hp in _cached_hairpins:
		var scr_pos: Vector2 = hp.pos
		# Red/Amber corner badge
		draw_circle(scr_pos, 7.0, Color(0.85, 0.15, 0.15, 0.95))
		draw_arc(scr_pos, 7.0, 0, TAU, 16, Color.WHITE, 1.2)
		draw_string(_font, scr_pos + Vector2(-3.5, 3.5), "%d" % int(hp.num), HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)

	# 5. Start / Finish Line Banner
	if pts.size() > 0:
		var start_p: Vector2 = pts[0]
		var start_dir := (pts[1] - pts[0]).normalized() if pts.size() > 1 else Vector2.RIGHT
		var start_perp := start_dir.orthogonal() * 7.0
		# Checkered bar
		draw_line(start_p - start_perp, start_p + start_perp, Color.WHITE, 3.5)
		draw_circle(start_p, 4.5, Color(0.2, 0.95, 0.35)) # Green start pip

		# Finish Line (if sprint)
		if not is_closed:
			var finish_p: Vector2 = pts[pts.size() - 1]
			var f_dir := (finish_p - pts[pts.size() - 2]).normalized()
			var f_perp := f_dir.orthogonal() * 7.0
			draw_line(finish_p - f_perp, finish_p + f_perp, Color(0.95, 0.2, 0.2), 3.5)
			draw_circle(finish_p, 4.5, Color.WHITE)

	# 6. Elevation Profile Diagram (Bottom 60 px)
	_draw_elevation_profile(s)

	# 7. Route Telemetry Chips (Top Overlay)
	var length_km: float = float(_route_data.get("length_m", 0)) / 1000.0
	var gain_m: int = int(_route_data.get("elev_gain", 0))
	var turns_n: int = int(_route_data.get("turns_count", 0))
	var type_str: String = "CIRCUIT" if is_closed else "SPRINT"

	var stats_text := "%s  ·  %.2f KM  ·  %d TURNS  ·  ▲%d M" % [type_str, length_km, turns_n, gain_m]
	draw_string(_font, Vector2(24, 28), stats_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.NEON)

func _draw_elevation_profile(s: Vector2) -> void:
	var elevs: Array = _route_data.get("elevations", [])
	if elevs.size() < 2:
		return
	
	var prof_rect := Rect2(20.0, s.y - 56.0, s.x - 40.0, 42.0)
	draw_rect(prof_rect, Color(0.04, 0.04, 0.06, 0.6), true)
	draw_rect(prof_rect, Color(1, 1, 1, 0.05), false, 1.0)

	var min_e: float = float(_route_data.get("elev_min", 0))
	var max_e: float = float(_route_data.get("elev_max", 100))
	var span_e := maxf(max_e - min_e, 10.0)

	var poly := PackedVector2Array()
	var line_pts := PackedVector2Array()
	var n := elevs.size()

	for i in range(n):
		var t := float(i) / float(n - 1)
		var x := prof_rect.position.x + t * prof_rect.size.x
		var norm_y := (float(elevs[i]) - min_e) / span_e
		var y := prof_rect.end.y - 4.0 - norm_y * (prof_rect.size.y - 8.0)
		line_pts.append(Vector2(x, y))

	# Filled profile under curve
	poly.append(Vector2(prof_rect.position.x, prof_rect.end.y))
	poly.append_array(line_pts)
	poly.append(Vector2(prof_rect.end.x, prof_rect.end.y))
	draw_colored_polygon(poly, Color(UIKit.NEON.r, UIKit.NEON.g, UIKit.NEON.b, 0.18))

	# Profile Line
	draw_polyline(line_pts, UIKit.NEON * 0.9, 1.5, true)

	# Elevation Labels
	draw_string(_font, Vector2(prof_rect.position.x + 6, prof_rect.position.y + 14), "ALTITUDE PROFILE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.DIM)
	draw_string(_font, Vector2(prof_rect.end.x - 65, prof_rect.position.y + 14), "%d m" % roundi(max_e), HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, Color(0.85, 0.85, 0.9))
	draw_string(_font, Vector2(prof_rect.end.x - 65, prof_rect.end.y - 4), "%d m" % roundi(min_e), HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, UIKit.DIM)
