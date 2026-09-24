class_name EventMarkers
extends Node3D
## Neon start beacons for every festival event. Reports the event the player is parked in.

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec3 color : source_color = vec3(1.0, 0.2, 0.55);
void fragment() {
	float edge = 1.0 - abs(UV.x - 0.5) * 2.0;
	edge = pow(edge, 1.4);  // Sharper neon core with softer glow falloff
	float pulse = 0.7 + 0.3 * sin(TIME * 1.8);  // Slow breathing pulse
	float scan = 0.45 + 0.55 * sin(TIME * 3.5 + UV.y * 25.0) * 0.35 + 0.35;  // Faster scan lines
	float fade = smoothstep(1.0, 0.0, UV.y) * scan * pulse;
	float hot_core = pow(edge, 3.0) * 0.4;  // White-hot center glow
	ALBEDO = color * edge * fade * 2.0 + vec3(1.0) * hot_core * fade;
	ALPHA = edge * fade;
}
"""

var markers := [] # {"event": dict, "pos": Vector3, "dir": Vector3}
var _shader: Shader

func build(world: NTWorld) -> void:
	_shader = Shader.new()
	_shader.code = BEAM_SHADER
	for ev in EventData.all():
		var route := Route.from_roads(world, ev.roads, ev.closed)
		if route.centers.size() < 20:
			continue
		var i := route.start_index(int(ev.rivals) + 1)
		var pos := route.centers[i]
		var dir := route.tangents[i]
		markers.append({"event": ev, "pos": pos, "dir": dir})
		_make_beacon(pos, ev)

func _make_beacon(pos: Vector3, ev: Dictionary) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var col := _color_for(ev.type)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.8
	cyl.height = 60.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	beam.position = Vector3(0, 30, 0)
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("color", col)
	beam.material_override = m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 5.5
	torus.outer_radius = 6.0
	ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = col
	rm.emission_enabled = true
	rm.emission = col
	rm.emission_energy_multiplier = 3.0
	ring.material_override = rm
	ring.position = Vector3(0, 0.15, 0)
	root.add_child(ring)
	var label := Label3D.new()
	label.text = "%s\n%s" % [ev.name.to_upper(), EventData.TYPE_NAMES[ev.type]]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.02
	label.modulate = col.lightened(0.3)
	label.outline_size = 12
	label.position = Vector3(0, 7.5, 0)
	label.no_depth_test = false
	root.add_child(label)

static func _color_for(type: int) -> Color:
	match type:
		EventData.Type.CIRCUIT: return Color(1.0, 0.2, 0.55)
		EventData.Type.SPRINT: return Color(0.15, 0.85, 1.0)
		EventData.Type.TOUGE_BATTLE: return Color(1.0, 0.6, 0.1)
		EventData.Type.WANGAN_DUEL: return Color(0.6, 0.3, 1.0)
		_: return Color(0.4, 1.0, 0.5)

## Event the player is parked in (within 12 m, slower than 15 km/h), or {}.
func event_at(pos: Vector3, speed: float) -> Dictionary:
	if speed > 4.2:
		return {}
	for m in markers:
		if pos.distance_to(m.pos) < 12.0:
			return m.event
	return {}

func set_markers_visible(v: bool) -> void:
	visible = v
