class_name MapData
extends RefCounted
## The real Riviera map baked by tools/mapbake: res://assets/map/riviera.bin (native world data)
## and riviera.json (route names, districts, credits). Map data (c) OpenStreetMap contributors.

const BIN_PATH := "res://assets/map/riviera.bin"
const JSON_PATH := "res://assets/map/riviera.json"

static var _info := {}

## Builds `world` from the baked map (call from a worker thread). Falls back to the procedural
## generator only if the bake is missing or unreadable.
static func build(world: NTWorld, fallback_seed := 1) -> void:
	var bytes := FileAccess.get_file_as_bytes(BIN_PATH)
	if not bytes.is_empty():
		var err: String = world.build_from_bake(bytes)
		if err == "":
			return
		push_error("MapData: %s (%s); using the generated map" % [BIN_PATH, err])
	world.build(fallback_seed)

## riviera.json: {credit, districts[], routes[{id, name, closed, length_m, roads[]}], counts}.
static func info() -> Dictionary:
	if _info.is_empty():
		var f := FileAccess.open(JSON_PATH, FileAccess.READ)
		if f:
			_info = JSON.parse_string(f.get_as_text())
	return _info

static func route(id: String) -> Dictionary:
	for r in info().get("routes", []):
		if r.id == id:
			return r
	return {}

static func credit() -> String:
	return info().get("credit", "Map data (c) OpenStreetMap contributors")
