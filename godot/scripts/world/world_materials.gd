class_name WorldMaterials
extends RefCounted
## Material per world mesh group (ids match MeshGroup / WorldGroup in the native code).

enum Group { ROAD, SHOULDER, CURB, RAIL, WALL, POST, TIREWALL, TERRAIN, JUNCTION, BUILDING, ROOF, NEON, TUNNEL, TUNNEL_LIGHT, WATER, DECK, SIDEWALK }

static var _cache := {}

static func _shader(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
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
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.72, 0.74, 0.76)
			s.metallic = 0.85
			s.roughness = 0.35
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = s
		Group.WALL, Group.DECK:
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.6, 0.59, 0.56)
			s.roughness = 0.88
			m = s
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
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.74, 0.35, 0.22)
			s.roughness = 0.82
			m = s
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
		_:
			m = StandardMaterial3D.new()
	_cache[group] = m
	return m
