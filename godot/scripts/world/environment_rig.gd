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
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0
	sun.directional_shadow_split_1 = 0.2
	sun.shadow_blur = 1.0
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.1
	sun.rotation_degrees = Vector3(-28, 48, 0)
	# Sharper shadow edges for better contact shadow definition (GT7-style)
	sun.directional_shadow_pancake_size = 20.0
	add_child(sun)

	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.44, 0.80)
	sky_mat.sky_horizon_color = Color(0.85, 0.82, 0.74)
	sky_mat.ground_horizon_color = Color(0.55, 0.52, 0.48)
	sky_mat.ground_bottom_color = Color(0.18, 0.20, 0.16)
	sky_mat.sun_angle_max = 26.0
	sky_mat.sun_curve = 0.09
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128

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

