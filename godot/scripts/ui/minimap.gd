class_name Minimap
extends Control
## Rotating circular minimap (bottom-left): dynamic speed-zoom (240m-800m), crisp vector road
## topology, off-screen bezel radar clamping with directional chevrons, and rotating North pip.

const SIZE := 176.0
const MIN_METERS := 240.0 # tight touge hairpins
const MAX_METERS := 800.0 # high-speed expressway

var world: NTWorld
var player: CarView
var markers: EventMarkers
var activities: Activities
var route_line := PackedVector2Array()

var _tex: ImageTexture
var _bounds: Rect2
var _shader_mat: ShaderMaterial
var _current_meters := 480.0
var _cached_roads := [] # Array of {points: PackedVector2Array, color: Color, width: float}

const MAP_SHADER := """
shader_type canvas_item;
uniform sampler2D map : filter_linear;
uniform vec2 center_uv;
uniform float span_uv;
uniform float heading;
void fragment() {
	vec2 p = UV - 0.5;
	if (length(p) > 0.5) discard;
	float c = cos(heading), s = sin(heading);
	vec2 r = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	vec2 uv = center_uv + r * span_uv;
	vec4 col = texture(map, uv);
	float edge = smoothstep(0.5, 0.46, length(p));
	COLOR = vec4(col.rgb * 1.3, 0.9 * edge);
}
"""

func setup(p_world: NTWorld, p_player: CarView) -> void:
	world = p_world
	player = p_player
	_bounds = world.bounds()
	_tex = ImageTexture.create_from_image(world.minimap(768))
	_shader_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = MAP_SHADER
	_shader_mat.shader = sh
	_shader_mat.set_shader_parameter("map", _tex)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var rect := TextureRect.new()
	rect.texture = _tex
	rect.material = _shader_mat
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.size = Vector2(SIZE, SIZE)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.show_behind_parent = true
	add_child(rect)
	size = Vector2(SIZE, SIZE)
	
	_cache_vector_roads()

func _cache_vector_roads() -> void:
	if world == null:
		return
	_cached_roads.clear()
	var names: Array = world.road_names()
	for name in names:
		var rs: Dictionary = world.road_samples(name)
		var c: PackedVector3Array = rs.get("centers", PackedVector3Array())
		if c.size() < 2:
			continue
		var poly := PackedVector2Array()
		poly.resize(c.size())
		for i in range(c.size()):
			poly[i] = Vector2(c[i].x, c[i].z)
		
		var kind: int = int(rs.get("kind", 0))
		var col := Color(0.65, 0.72, 0.85, 0.85)
		var width := 2.2
		match kind:
			1: # RK_EXPRESSWAY
				col = Color(1.0, 0.25, 0.6, 0.95)
				width = 3.6
			2: # RK_RAMP
				col = Color(0.85, 0.35, 0.95, 0.85)
				width = 2.4
			3: # RK_AVENUE
				col = Color(0.9, 0.94, 1.0, 0.9)
				width = 3.0
			4: # RK_TOUGE
				col = Color(1.0, 0.8, 0.2, 0.95)
				width = 3.2
			5: # RK_FARM
				col = Color(0.75, 0.58, 0.38, 0.8)
				width = 2.0
		
		_cached_roads.append({"points": poly, "color": col, "width": width})

func _world_span() -> float:
	return maxf(_bounds.size.x, _bounds.size.y)

func _process(delta: float) -> void:
	if player == null:
		return
	var s: float = Settings.get_value("gameplay", "hud_scale", 1.0)
	var vp := get_viewport_rect().size
	position = Vector2(24 * s, vp.y - (SIZE + 24) * s)
	scale = Vector2(s, s)
	
	# Dynamic speed-zoom: tight hairpins zoom in close, high-speed highway zooms out
	var spd_kmh: float = absf(float(player.telemetry.get("speed_kmh", 0.0)))
	var target_span: float = remap(clampf(spd_kmh, 25.0, 220.0), 25.0, 220.0, MIN_METERS, MAX_METERS)
	_current_meters = lerpf(_current_meters, target_span, clampf(delta * 4.0, 0.0, 1.0))

	var p := player.global_position
	var span := _world_span()
	var uv := Vector2((p.x - _bounds.position.x) / span, (p.z - _bounds.position.y) / span)
	var fwd := -player.global_basis.z
	var heading := atan2(fwd.x, -fwd.z)

	_shader_mat.set_shader_parameter("center_uv", uv)
	_shader_mat.set_shader_parameter("span_uv", _current_meters / span)
	_shader_mat.set_shader_parameter("heading", heading)
	queue_redraw()

func _to_local(world_pos: Vector3) -> Vector2:
	var p := player.global_position
	var fwd := -player.global_basis.z
	var heading := atan2(fwd.x, -fwd.z)
	var d := Vector2(world_pos.x - p.x, world_pos.z - p.z)
	var r := d.rotated(-heading)
	return Vector2(SIZE * 0.5, SIZE * 0.5) + r / _current_meters * SIZE

func _draw() -> void:
	if player == null:
		return
	var c := Vector2(SIZE * 0.5, SIZE * 0.5)
	var radius := SIZE * 0.5
	var inner_radius := radius - 3.0

	# 1. Bezel Ring (Frosted glass outer border with neon accent)
	draw_arc(c, radius, 0, TAU, 64, Color(0.04, 0.06, 0.1, 0.95), 5.0, true)
	draw_arc(c, radius - 1.5, 0, TAU, 64, Color(0.15, 0.85, 1.0, 0.8), 2.0, true)

	# 2. Rotating North (N) Pip
	var fwd := -player.global_basis.z
	var heading := atan2(fwd.x, -fwd.z)
	var north_dir := Vector2(0, -1).rotated(-heading)
	var north_pos := c + north_dir * (radius - 5.0)
	draw_circle(north_pos, 4.0, Color(1.0, 0.25, 0.35))
	draw_line(north_pos - north_dir * 3.0, north_pos + north_dir * 3.0, Color.WHITE, 1.5)

	# 3. Vector Road Overlay (Clip to minimap circle)
	var p_world := Vector2(player.global_position.x, player.global_position.z)
	var visible_dist := _current_meters * 0.65
	for road in _cached_roads:
		var pts: PackedVector2Array = road.points
		var local_pts := PackedVector2Array()
		for pt in pts:
			if pt.distance_to(p_world) < visible_dist:
				local_pts.append(_to_local(Vector3(pt.x, 0, pt.y)))
		if local_pts.size() > 1:
			var w: float = maxf(road.width * (SIZE / _current_meters) * 1.5, 1.5)
			draw_polyline(local_pts, road.color * Color(1, 1, 1, 0.65), w, true)

	# 4. GPS Route Line
	if route_line.size() > 1:
		var pts := PackedVector2Array()
		for q in route_line:
			var lp := _to_local(Vector3(q.x, 0, q.y))
			if lp.distance_to(c) < radius * 1.4:
				pts.append(lp)
		if pts.size() > 1:
			draw_polyline(pts, Color(0.0, 0.95, 1.0, 0.45), 6.0, true)
			draw_polyline(pts, Color(0.15, 1.0, 0.85, 0.95), 3.0, true)

	# 5. Event Beacons (In-circle or Clamped to Bezel)
	if markers:
		for m in markers.markers:
			var lp := _to_local(m.pos)
			var dist := lp.distance_to(c)
			var col: Color = EventMarkers._color_for(m.event.get("type", 0))
			if dist < inner_radius - 6.0:
				draw_circle(lp, 5.0, Color.BLACK)
				draw_circle(lp, 4.0, col)
			else:
				# Bezel Radar Clamping
				var dir := (lp - c).normalized()
				var bezel_pt := c + dir * (inner_radius - 6.0)
				draw_circle(bezel_pt, 4.0, col)
				draw_polyline(PackedVector2Array([bezel_pt - dir * 4.0, bezel_pt, bezel_pt - dir.orthogonal() * 2.0]), Color.WHITE, 1.2, true)

	# 6. Activities / PR Stunts (In-circle or Clamped to Bezel)
	if activities:
		for it in activities.items:
			var lp := _to_local(it.pos)
			var dist := lp.distance_to(c)
			var k_idx: int = int(it.get("kind", 0))
			var col: Color = Activities.KIND_COLORS[k_idx] if k_idx < Activities.KIND_COLORS.size() else Color.WHITE
			if dist < inner_radius - 6.0:
				draw_rect(Rect2(lp - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), Color.BLACK)
				draw_rect(Rect2(lp - Vector2(2.5, 2.5), Vector2(5.0, 5.0)), col)
			else:
				var dir := (lp - c).normalized()
				var bezel_pt := c + dir * (inner_radius - 6.0)
				draw_circle(bezel_pt, 3.5, col)

	# 7. Player Arrow (Center, always pointing North/Up)
	var arrow := PackedVector2Array([
		c + Vector2(0, -10),
		c + Vector2(7, 8),
		c + Vector2(0, 3.5),
		c + Vector2(-7, 8)
	])
	draw_colored_polygon(arrow, Color(1.0, 0.22, 0.55))
	draw_polyline(arrow, Color.WHITE, 1.5, true)
	draw_circle(c, 2.0, Color.WHITE)
