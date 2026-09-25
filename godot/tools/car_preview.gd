extends Node3D
## Bake check for tools/carbake output: renders each baked car GLB with its source materials from
## the 3/4 front, the right side and above. A red arrow marks the nose (-Z); yellow balls mark the
## wheel pivots and spin the wheels 45 degrees so detached wheels show up.
## Usage: godot --path . --resolution 1334x750 -- scene=car_preview out=D:/dir [cars=a,b]

var out_dir := "user://car_preview"
var tile_mode := false
var cars: PackedStringArray = []
var cam: Camera3D
var asset_root := "res://assets/cars"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "out":
			out_dir = kv[1]
		elif kv.size() == 2 and kv[0] == "cars":
			cars = kv[1].split(",")
		elif a == "tiles":
			tile_mode = true
			out_dir = "res://assets/ui/cars"
		elif a == "props":
			asset_root = "res://assets/props" # tools/carbake/props.mjs output; the arrow marks +Z
	if cars.is_empty():
		for d in DirAccess.get_directories_at(asset_root):
			cars.append(d)
	var absolute_out := ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("res://") else out_dir
	DirAccess.make_dir_recursive_absolute(absolute_out)
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.35, 0.36)
	floor_mi.material_override = fm
	add_child(floor_mi)
	cam = Camera3D.new()
	cam.current = true
	add_child(cam)
	for key in cars:
		var path := "%s/%s/%s.gltf" % [asset_root, key, key]
		if not ResourceLoader.exists(path):
			print("PREVIEW missing ", key)
			continue
		var car: Node3D = (load(path) as PackedScene).instantiate()
		add_child(car)
		var marks := Node3D.new()
		add_child(marks)
		for w in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
			var n := car.find_child(w, true, false) as Node3D
			if n == null:
				continue
			var spin := n.find_child(w + "_Spin", true, false) as Node3D
			if spin:
				spin.rotation.x = deg_to_rad(45.0)
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.06
			sm.height = 0.12
			s.mesh = sm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(1, 0.85, 0.0)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.no_depth_test = true
			s.material_override = m
			marks.add_child(s)
			s.global_position = n.global_position
		var arrow := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.18
		cm.height = 0.5
		arrow.mesh = cm
		var am := StandardMaterial3D.new()
		am.albedo_color = Color(1, 0.1, 0.1)
		am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		arrow.material_override = am
		arrow.rotation_degrees = Vector3(-90, 0, 0)
		marks.add_child(arrow)
		var bb := _aabb(car)
		arrow.position = Vector3(0, bb.end.y + 0.4, bb.position.z - 0.3)
		if asset_root.ends_with("props"):
			arrow.rotation_degrees = Vector3(90, 0, 0)
			arrow.position = Vector3(0, bb.end.y + 0.4, bb.end.z + 0.3)
		var shots: Array[Image] = []
		var views := [[Vector3(0.62, 0.32, -0.72), 1.0]] if tile_mode else [[Vector3(0.62, 0.32, -0.72), 1.0], [Vector3(1, 0.12, 0), 1.0], [Vector3(0.001, 1, 0.0), 1.0]]
		for v in views:
			var dir: Vector3 = (v[0] as Vector3).normalized()
			var c := bb.get_center()
			var dist := bb.size.length() * 1.15
			cam.fov = 35.0
			cam.look_at_from_position(c + dir * dist, c, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
			for f in range(3):
				await RenderingServer.frame_post_draw
			shots.append(get_viewport().get_texture().get_image())
		var w := shots[0].get_width()
		var h := shots[0].get_height()
		if tile_mode:
			shots[0].resize(640, 360, Image.INTERPOLATE_LANCZOS)
			shots[0].save_webp(absolute_out.path_join("%s.webp" % key), 0.86)
		else:
			var sheet := Image.create(w * 3, h, false, shots[0].get_format())
			for i in range(3):
				sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(w * i, 0))
			sheet.resize(w * 3 / 2, h / 2, Image.INTERPOLATE_LANCZOS)
			sheet.save_png(absolute_out.path_join("%s.png" % key))
		print("PREVIEW ", key, " aabb ", bb)
		car.queue_free()
		marks.queue_free()
		await RenderingServer.frame_post_draw
	get_tree().quit()

func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


