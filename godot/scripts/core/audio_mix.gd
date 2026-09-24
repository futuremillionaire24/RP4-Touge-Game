extends Node
## Audio bus layout built at startup: Engine / Effects / Music / Ambience under Master, and a
## Tunnel bus (reverb) that environment zones blend into. Volumes follow Settings; menus duck the
## game buses.

const BUSES := ["Engine", "Effects", "Music", "Ambience"]
const REVERB_BUSES := ["Engine", "Effects"]

var _duck := 0.0
var _duck_target := 0.0
var tunnel_amount := 0.0
var _reverbs := {} # bus index -> AudioEffectReverb

func _ready() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	# Tunnel / underpass reverb lives on the game buses; its wet level follows tunnel_amount and the
	# effect is bypassed entirely in the open to save audio-thread time.
	for b in REVERB_BUSES:
		var idx := AudioServer.get_bus_index(b)
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.75
		rev.damping = 0.35
		rev.spread = 0.8
		rev.wet = 0.0
		rev.dry = 1.0
		rev.predelay_msec = 35.0
		AudioServer.add_bus_effect(idx, rev)
		AudioServer.set_bus_effect_enabled(idx, 0, false)
		_reverbs[idx] = rev
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, lim)
	Settings.changed.connect(func(sec): if sec == "audio": apply_volumes())
	apply_volumes()

func apply_volumes() -> void:
	var a: Dictionary = Settings.section("audio")
	_set_bus("Master", a.master)
	_set_bus("Engine", a.engine * (1.0 - _duck * 0.7))
	_set_bus("Effects", a.effects * (1.0 - _duck * 0.7))
	_set_bus("Music", a.music)
	_set_bus("Ambience", a.ambience * (1.0 - _duck * 0.5))

## 0 = open air, 1 = deep inside a tunnel.
func set_tunnel(amount: float) -> void:
	tunnel_amount = clampf(amount, 0.0, 1.0)
	for idx in _reverbs.keys():
		var rev: AudioEffectReverb = _reverbs[idx]
		rev.wet = tunnel_amount * 0.45
		AudioServer.set_bus_effect_enabled(idx, 0, tunnel_amount > 0.01)

func _set_bus(name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))

## Menus call duck(true) to pull game audio down under the UI.
func duck(on: bool) -> void:
	_duck_target = 1.0 if on else 0.0

func _process(delta: float) -> void:
	if absf(_duck - _duck_target) > 0.001:
		_duck = move_toward(_duck, _duck_target, delta * 3.0)
		apply_volumes()
