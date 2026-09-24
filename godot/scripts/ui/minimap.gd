class_name Minimap
extends Control
## Rotating circular minimap (bottom-left): pre-rendered world map texture, heading-up, with
## event beacons, activities, collectibles and the race route.

const SIZE := 170.0
const METERS := 520.0 # map span across the circle

var world: NTWorld
var player: CarView
var markers: EventMarkers
var activities: Activities
var route_line := PackedVector2Array()
var _tex: ImageTexture
var _bounds: Rect2
var _shader_mat: ShaderMaterial

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
	float edge = smoothstep(0.5, 0.47, length(p));
	COLOR = vec4(col.rgb * 1.25, 0.85 * edge);
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

func _world_span() -> float:
	return maxf(_bounds.size.x, _bounds.size.y)

func _process(_d: float) -> void:
	if player == null:
		return
	var s: float = Settings.get_value("gameplay", "hud_scale", 1.0)
	var vp := get_viewport_rect().size
	position = Vector2(20 * s, vp.y - (SIZE + 20) * s)
	scale = Vector2(s, s)
	var p := player.global_position
	var span := _world_span()
	var uv := Vector2((p.x - _bounds.position.x) / span, (p.z - _bounds.position.y) / span)
	var fwd := -player.global_basis.z
	var heading := atan2(fwd.x, -fwd.z)
	_shader_mat.set_shader_parameter("center_uv", uv)
	_shader_mat.set_shader_parameter("span_uv", METERS / span)
	_shader_mat.set_shader_parameter("heading", heading)
	queue_redraw()

func _to_local(world_pos: Vector3) -> Vector2:
	var p := player.global_position
	var fwd := -player.global_basis.z
	var heading := atan2(fwd.x, -fwd.z)
	var d := Vector2(world_pos.x - p.x, world_pos.z - p.z)
	var r := d.rotated(-heading)
	return Vector2(SIZE * 0.5, SIZE * 0.5) + r / METERS * SIZE

func _draw() -> void:
	if player == null:
		return
	var c := Vector2(SIZE * 0.5, SIZE * 0.5)
	draw_arc(c, SIZE * 0.5, 0, TAU, 64, Color(1, 0.18, 0.53, 0.8), 2.0, true)
	# Race route.
	if route_line.size() > 1:
		var pts := PackedVector2Array()
		for q in route_line:
			pts.append(_to_local(Vector3(q.x, 0, q.y)))
		draw_polyline(pts, Color(0.15, 0.91, 1.0, 0.9), 2.5, true)
	if markers:
		for m in markers.markers:
			var lp := _to_local(m.pos)
			if lp.distance_to(c) < SIZE * 0.48:
				draw_circle(lp, 4.5, EventMarkers._color_for(m.event.type))
	if activities:
		for it in activities.items:
			var lp := _to_local(it.pos)
			if lp.distance_to(c) < SIZE * 0.48:
				draw_rect(Rect2(lp - Vector2(3, 3), Vector2(6, 6)), Activities.KIND_COLORS[it.kind])
	# Player arrow (always pointing up).
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(6, 7), c + Vector2(0, 3), c + Vector2(-6, 7)]), Color.WHITE)
