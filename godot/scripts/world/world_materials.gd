class_name WorldMaterials
extends RefCounted
## Material per world mesh group (ids match MeshGroup / WorldGroup in the native code).

enum Group { ROAD, SHOULDER, CURB, RAIL, WALL, POST, TIREWALL, TERRAIN, JUNCTION, BUILDING, ROOF, NEON, TUNNEL, TUNNEL_LIGHT, WATER, DECK, SIDEWALK }

static var _cache := {}

## Poly Haven texture arrays (tools/carbake/envtex.mjs) bound to every shader that samples them.
const ENV_ARRAYS := {
	"ground_albedo": "res://assets/env/ground_albedo.webp", "ground_normal": "res://assets/env/ground_normal.webp",
	"road_albedo": "res://assets/env/road_albedo.webp", "road_normal": "res://assets/env/road_normal.webp",
	"facade_albedo": "res://assets/env/facade_albedo.webp", "facade_normal": "res://assets/env/facade_normal.webp",
}

static var _sea_depth: ImageTexture
static var _sea_rect := Rect2()

## Per-world data for the materials: the sea depth map (shallows, shore foam) for the water.
static func set_world(world: NTWorld) -> void:
	_sea_rect = world.bounds()
	_sea_depth = ImageTexture.create_from_image(world.sea_depth(8.0))
	if _cache.has(Group.WATER):
		_bind_sea(_cache[Group.WATER])

## Releases the world materials, their texture arrays and the sea depth map (free roam exit).
static func clear_cache() -> void:
	_cache.clear()
	_sea_depth = null

static func _bind_sea(m: ShaderMaterial) -> void:
	if _sea_depth == null:
		return
	m.set_shader_parameter("sea_depth", _sea_depth)
	m.set_shader_parameter("sea_rect", Vector4(_sea_rect.position.x, _sea_rect.position.y, _sea_rect.size.x, _sea_rect.size.y))

static func _shader(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for u in m.shader.get_shader_uniform_list():
		if ENV_ARRAYS.has(u.name) and ResourceLoader.exists(ENV_ARRAYS[u.name]):
			m.set_shader_parameter(u.name, load(ENV_ARRAYS[u.name]))
	return m

static func get_material(group: int) -> Material:
	if _cache.has(group):
		return _cache[group]
	var m: Material
	match group:
		Group.ROAD, Group.JUNCTION:
			m = _cache.get(Group.ROAD) if _cache.has(Group.ROAD) else _shader("res://shaders/road.gdshader")
		Group.SHOULDER, Group.SIDEWALK:
			m = _cache.get(Group.SHOULDER) if _cache.has(Group.SHOULDER) else _shader("res://shaders/verge.gdshader")
		Group.CURB:
			m = _shader("res://shaders/curb.gdshader")
		Group.RAIL:
			m = _shader("res://shaders/rail.gdshader")
		Group.WALL, Group.DECK:
			m = _cache.get(Group.WALL) if _cache.has(Group.WALL) else _shader("res://shaders/wall.gdshader")
		Group.POST:
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.55, 0.56, 0.58)
			s.metallic = 0.6
			s.roughness = 0.5
			m = s
		Group.TIREWALL:
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.05, 0.05, 0.055)
			s.roughness = 0.9
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = s
		Group.TERRAIN:
			m = _shader("res://shaders/terrain.gdshader")
		Group.BUILDING:
			m = _shader("res://shaders/facade.gdshader")
		Group.ROOF:
			m = _shader("res://shaders/roof.gdshader")
		Group.NEON:
			m = _shader("res://shaders/neon.gdshader")
		Group.TUNNEL:
			m = _shader("res://shaders/tunnel.gdshader")
		Group.TUNNEL_LIGHT:
			var s := StandardMaterial3D.new()
			s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			s.albedo_color = Color(1.0, 0.72, 0.35)
			s.emission_enabled = true
			s.emission = Color(1.0, 0.7, 0.3)
			s.emission_energy_multiplier = 4.0
			m = s
		Group.WATER:
			m = _shader("res://shaders/water.gdshader")
			_bind_sea(m)
		_:
			m = StandardMaterial3D.new()
	_cache[group] = m
	return m
