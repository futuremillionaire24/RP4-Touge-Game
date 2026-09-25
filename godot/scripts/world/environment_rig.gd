class_name EnvironmentRig
extends Node3D
## GT7/FH5-grade sun, sky, fog and post-processing for the Mobile renderer, tuned for Mali-G77:
## ACES filmic tonemap, volumetric-style height fog, dramatic glow bloom for neon nights,
## sky-driven ambient/reflections, and higher shadow quality.

var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
## Photographic day-cycle sky (sky_hdri.gdshader), driven by SkyWeather.
var sky_mat: ShaderMaterial
## The shadow setting wants sun shadows; SkyWeather still switches them off at night.
var shadows_wanted := true

func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.50
	sun.light_color = Color(1.0, 0.97, 0.90) # Warm Mediterranean sunlight
	apply_shadow_quality(int(Settings.get_value("graphics", "shadows", 1)))
	Settings.changed.connect(_on_settings_changed)
	sun.shadow_blur = 1.0
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.1
	sun.rotation_degrees = Vector3(-30, 48, 0)
	# Sharper shadow edges for better contact shadow definition (GT7-style)
	sun.directional_shadow_pancake_size = 20.0
	add_child(sun)

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky_hdri.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	# The sky changes slowly; incremental radiance updates keep the Mali GPU cost flat.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.90
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# ACES filmic tonemap: richer colors, natural roll-off in highlights
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.10
	env.tonemap_white = 7.5
	# Glow: natural bloom for car head/taillights and streetlights
	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_bloom = 0.025
	env.glow_hdr_threshold = 1.15
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# Fog: warm atmospheric haze for European scenic depth
	env.fog_enabled = true
	env.fog_light_color = Color(0.80, 0.82, 0.86)
	env.fog_density = 0.00035
	env.fog_sky_affect = 0.15
	env.fog_height_density = 0.0
	# Color grading: natural filmic tone with Forza Horizon warm richness
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.06
	env.adjustment_brightness = 1.01
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _on_settings_changed(section: String) -> void:
	if section == "graphics":
		apply_shadow_quality(int(Settings.get_value("graphics", "shadows", 1)))

## Graphics "shadows" setting: 0 off, 1 low (2 cascades to 160 m, the original mobile budget),
## 2 high (4 cascades to 220 m), 3 ultra (4 cascades to 280 m so far cliffs and skyline blocks keep
## their shadows). Each extra cascade re-renders its casters: profile on the RP4 before raising
## the default.
func apply_shadow_quality(q: int) -> void:
	if sun == null:
		return
	shadows_wanted = q > 0
	sun.shadow_enabled = q > 0
	if q <= 1:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 160.0
		sun.directional_shadow_split_1 = 0.2
		return
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 280.0 if q >= 3 else 220.0
	# Near cascade stays ~20 m for crisp car and kerb contact shadows at either range.
	sun.directional_shadow_split_1 = 0.08 if q >= 3 else 0.1
	sun.directional_shadow_split_2 = 0.22 if q >= 3 else 0.27
	sun.directional_shadow_split_3 = 0.5 if q >= 3 else 0.55
