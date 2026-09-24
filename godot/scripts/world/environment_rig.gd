class_name EnvironmentRig
extends Node3D
## GT7/FH5-grade sun, sky, fog and post-processing for the Mobile renderer, tuned for Mali-G77:
## ACES filmic tonemap, volumetric-style height fog, dramatic glow bloom for neon nights,
## sky-driven ambient/reflections, and higher shadow quality.

var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ProceduralSkyMaterial

func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0
	sun.directional_shadow_split_1 = 0.2
	sun.shadow_blur = 1.0
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.1
	sun.rotation_degrees = Vector3(-38, 35, 0)
	# Sharper shadow edges for better contact shadow definition (GT7-style)
	sun.directional_shadow_pancake_size = 20.0
	add_child(sun)

	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.40, 0.72)
	sky_mat.sky_horizon_color = Color(0.70, 0.78, 0.88)
	sky_mat.ground_horizon_color = Color(0.48, 0.50, 0.55)
	sky_mat.ground_bottom_color = Color(0.18, 0.18, 0.22)
	sky_mat.sun_angle_max = 28.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# ACES filmic tonemap: richer colors, natural roll-off in highlights
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.08
	env.tonemap_white = 7.5
	# Glow: dramatic bloom for neon signs and tail lights at night
	env.glow_enabled = true
	env.glow_intensity = 0.52
	env.glow_bloom = 0.035
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_scale = 2.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# Fog: dense atmospheric haze for depth and mood
	env.fog_enabled = true
	env.fog_light_color = Color(0.60, 0.68, 0.80)
	env.fog_density = 0.0004
	env.fog_sky_affect = 0.18
	env.fog_height_density = 0.0
	# Color grading: slightly boosted saturation for vibrant Japanese night atmosphere
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08
	env.adjustment_brightness = 1.01
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

