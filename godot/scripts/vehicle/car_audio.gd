class_name CarAudio
extends Node3D
## Procedural engine/tire/wind sound for one car. The player's car plays non-positional
## (it's always "here"); rivals are 3D sources with Doppler and distance attenuation. The
## tunnel send blends in when the car is inside a tunnel zone.

var view: CarView
var stream: NTEngineAudio
var player: Node # AudioStreamPlayer or AudioStreamPlayer3D
var interior := false
var _peak_torque := 300.0

func setup(p_view: CarView) -> void:
	view = p_view
	_peak_torque = maxf(1.0, float(view.sim.get_car_spec(view.car_id).get("max_torque", 300.0)))
	stream = NTEngineAudio.new()
	# Engine swaps sound like the donor engine.
	stream.configure(view.audio_key if view.audio_key != "" else view.key, view.is_player)
	# One player per stream: each playback advances the shared synth, so a second player
	# (e.g. for a reverb send) would double its clock. Tunnels use bus reverb instead.
	if view.is_player:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "Engine"
		p.volume_db = -2.0
		add_child(p)
		player = p
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.bus = "Engine"
		p3.unit_size = 8.0
		p3.max_distance = 260.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		p3.panning_strength = 1.0
		p3.volume_db = -3.0
		add_child(p3)
		player = p3
	player.play()

func _process(_delta: float) -> void:
	if view == null or view.telemetry.is_empty():
		return
	var t: Dictionary = view.telemetry
	var slip := 0.0
	var loose := 0.0
	var rough := 0.0
	for i in range(4):
		if view.wheel_value(i, 6) < 0.5:
			continue
		var slide := view.wheel_value(i, 7)
		slip = maxf(slip, clampf((slide - 2.5) / 9.0, 0.0, 1.0))
		var surf := int(view.wheel_value(i, 10))
		if surf in [TrackBuilder.Surf.GRAVEL, TrackBuilder.Surf.DIRT, TrackBuilder.Surf.GRASS, TrackBuilder.Surf.SAND, TrackBuilder.Surf.SNOW]:
			loose = maxf(loose, 1.0)
		elif surf in [TrackBuilder.Surf.CURB, TrackBuilder.Surf.COBBLE, TrackBuilder.Surf.ASPHALT_WORN]:
			rough = maxf(rough, 0.8 if surf == TrackBuilder.Surf.CURB else 0.4)
	stream.set_state({
		"rpm": t.rpm,
		"throttle": t.throttle,
		"load": clampf(float(t.engine_torque) / _peak_torque, 0.0, 1.0),
		"boost": t.boost,
		"speed": t.speed,
		"gear_ratio": absf(float(t.get("gear_ratio", 0.0))),
		"slip": slip,
		"slip_pitch": clampf(absf(float(t.drift_angle)) / 0.8, 0.0, 1.0),
		"loose": loose,
		"roughness": rough,
		"wet": view.sim.wetness if view.sim else 0.0,
		"limiter": t.limiter,
		"shifting": t.get("shifting", false),
		"interior": interior,
	})
