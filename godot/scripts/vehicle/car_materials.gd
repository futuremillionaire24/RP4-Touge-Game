class_name CarMaterials
extends RefCounted
## Car material library: paint (car_paint.gdshader) and the shared glass / tyre / rim / trim /
## chrome / light materials used by the body, wheel and detail builders.

const PAINT_SHADER := preload("res://shaders/car_paint.gdshader")
const ThinFilmLUT := preload("res://scripts/vehicle/thin_film_lut.gd")

static var _shared := {}

static func shared(name: String) -> Material:
	if _shared.has(name):
		return _shared[name]
	var m := StandardMaterial3D.new()
	match name:
		"glass":
			m.albedo_color = Color(0.015, 0.02, 0.028)
			m.metallic = 0.0
			m.roughness = 0.04
			m.metallic_specular = 0.9
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.02
		"tire":
			m.albedo_color = Color(0.035, 0.035, 0.037)
			m.roughness = 0.88
		"rim":
			m.albedo_color = Color(0.72, 0.73, 0.75)
			m.metallic = 0.95
			m.roughness = 0.22
		"rim_dark":
			m.albedo_color = Color(0.09, 0.09, 0.1)
			m.metallic = 0.9
			m.roughness = 0.3
		"trim":
			m.albedo_color = Color(0.04, 0.04, 0.045)
			m.roughness = 0.6
		"chrome":
			m.albedo_color = Color(0.85, 0.86, 0.88)
			m.metallic = 1.0
			m.roughness = 0.08
		"plate":
			m.albedo_color = Color(0.92, 0.92, 0.88)
			m.roughness = 0.5
		"caliper":
			m.albedo_color = Color(0.75, 0.08, 0.06)
			m.roughness = 0.4
		"disc":
			m.albedo_color = Color(0.35, 0.34, 0.33)
			m.metallic = 0.8
			m.roughness = 0.45
		"headlight":
			m.albedo_color = Color(0.9, 0.95, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.85, 0.92, 1.0)
			m.emission_energy_multiplier = 2.0
			m.roughness = 0.1
		"taillight":
			m.albedo_color = Color(0.5, 0.02, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.04, 0.02)
			m.emission_energy_multiplier = 1.2
			m.roughness = 0.15
		"indicator":
			m.albedo_color = Color(0.9, 0.5, 0.05)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.45, 0.02)
			m.emission_energy_multiplier = 0.3
		"underbody":
			m.albedo_color = Color(0.02, 0.02, 0.02)
			m.roughness = 1.0
		_:
			m.albedo_color = Color.MAGENTA
	_shared[name] = m
	return m

static var _thin_film_lut: ImageTexture = null

static func get_thin_film_lut() -> ImageTexture:
	if _thin_film_lut == null:
		_thin_film_lut = ThinFilmLUT.generate()
	return _thin_film_lut

static func paint_material(key: String, color_override = null, finish_override = "") -> ShaderMaterial:
	var car := CarData.get_car(key)
	var finish: String = finish_override if finish_override != "" else car.get("finish", "gloss")
	var f: Dictionary = CarData.FINISHES.get(finish, CarData.FINISHES["gloss"])
	var m := ShaderMaterial.new()
	m.shader = PAINT_SHADER
	m.set_shader_parameter("base_color", color_override if color_override != null else car.paint)
	m.set_shader_parameter("pearl_color", car.get("pearl", Color(0.3, 0.35, 0.9)))
	m.set_shader_parameter("metallic", f.metallic)
	m.set_shader_parameter("roughness", f.roughness)
	m.set_shader_parameter("flake_amount", f.flake)
	m.set_shader_parameter("pearl", f.pearl)
	m.set_shader_parameter("clearcoat_amount", f.coat)
	m.set_shader_parameter("clearcoat_gloss", f.gloss)
	m.set_shader_parameter("candy", f.candy)
	if f.pearl > 0.001:
		m.set_shader_parameter("thin_film_lut", get_thin_film_lut())
		m.set_shader_parameter("use_thin_film", true)
		var row: float = float(car.get("film_row", 2))
		m.set_shader_parameter("film_row", row)
	var dents := PackedVector4Array()
	dents.resize(8)
	m.set_shader_parameter("dents", dents)
	return m
