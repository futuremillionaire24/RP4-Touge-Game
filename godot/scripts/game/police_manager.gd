extends Node
## 4-Tier Police Pursuit System: dynamic AI cruisers, heat escalation, sight-line evasion,
## PIT maneuvers, roadblocks, busted arrest sequence, and escape bounties.

signal heat_changed(tier: int)
signal pursuit_started(tier: int)
signal pursuit_evaded(bounty: int, xp: int)
signal busted(fine: int)

enum HeatTier { NONE = 0, PATROL = 1, INTERCEPTOR = 2, ROADBLOCK = 3, HYPER_PURSUIT = 4 }

var sim: NTSim
var world: NTWorld
var player: CarView
var hud: DriveHUD
var freeroam_host: Node
var enabled := true

var heat_tier := HeatTier.NONE
var heat_progress := 0.0 # 0..1 towards next tier
var escape_timer := 0.0 # counts up to 15.0 when out of sight
const ESCAPE_TIME := 15.0
var busted_timer := 0.0 # counts up to 3.0 when boxed in
const BUSTED_TIME := 3.0

var cruisers: Array[Dictionary] = [] # {"id": car_id, "view": CarView, "lightbar": Node3D, "tier": int}
var _spawn_cooldown := 0.0
var _bounty_bank := 0

# UI Overlay Nodes
var _overlay_layer: CanvasLayer
var _heat_badge: Label
var _cooldown_bar: ProgressBar
var _busted_banner: ColorRect
var _flash_timer := 0.0

func setup(p_sim: NTSim, p_world: NTWorld, p_player: CarView, p_hud: DriveHUD, p_host: Node = null) -> void:
	sim = p_sim
	world = p_world
	player = p_player
	hud = p_hud
	freeroam_host = p_host
	_create_ui_overlay()

func _create_ui_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 5
	add_child(_overlay_layer)

	_heat_badge = Label.new()
	_heat_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_heat_badge.offset_left = 24.0
	_heat_badge.offset_top = 24.0
	_heat_badge.offset_right = 260.0
	_heat_badge.offset_bottom = 60.0
	_heat_badge.add_theme_font_size_override("font_size", 18)
	_heat_badge.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	_heat_badge.add_theme_constant_override("outline_size", 6)
	_heat_badge.add_theme_color_override("font_outline_color", Color.BLACK)
	_heat_badge.visible = false
	_overlay_layer.add_child(_heat_badge)

	_cooldown_bar = ProgressBar.new()
	_cooldown_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cooldown_bar.offset_left = 24.0
	_cooldown_bar.offset_top = 64.0
	_cooldown_bar.offset_right = 220.0
	_cooldown_bar.offset_bottom = 74.0
	_cooldown_bar.show_percentage = false
	_cooldown_bar.max_value = ESCAPE_TIME
	_cooldown_bar.value = 0.0
	_cooldown_bar.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.8, 1.0, 0.85)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	_cooldown_bar.add_theme_stylebox_override("fill", sb)
	_overlay_layer.add_child(_cooldown_bar)

	_busted_banner = ColorRect.new()
	_busted_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_busted_banner.color = Color(0.8, 0.05, 0.05, 0.0)
	_busted_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busted_banner.visible = false
	_overlay_layer.add_child(_busted_banner)

	var busted_lbl := Label.new()
	busted_lbl.set_anchors_preset(Control.PRESET_CENTER)
	busted_lbl.text = "BUSTED"
	busted_lbl.name = "BustedLabel"
	busted_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	busted_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	busted_lbl.add_theme_font_size_override("font_size", 72)
	busted_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	busted_lbl.add_theme_constant_override("outline_size", 16)
	busted_lbl.add_theme_color_override("font_outline_color", Color(0.5, 0.0, 0.0))
	_busted_banner.add_child(busted_lbl)

func add_heat(amount: float) -> void:
	if not enabled or player == null:
		return
	if heat_tier == HeatTier.NONE:
		heat_tier = HeatTier.PATROL
		_bounty_bank = 2500
		heat_changed.emit(heat_tier)
		pursuit_started.emit(heat_tier)
		if hud:
			hud.toast("POLICE PURSUIT INITIATED — HEAT 1", 3.5)
	heat_progress += amount
	if heat_progress >= 1.0 and heat_tier < HeatTier.HYPER_PURSUIT:
		heat_progress = 0.0
		heat_tier += 1
		_bounty_bank += int(heat_tier) * 3500
		heat_changed.emit(heat_tier)
		if hud:
			hud.toast("HEAT LEVEL ESCALATED — HEAT %d" % int(heat_tier), 3.5)
	escape_timer = 0.0

func _physics_process(delta: float) -> void:
	if not enabled or sim == null or player == null or player.car_id < 0:
		return
	if heat_tier == HeatTier.NONE:
		_check_infractions(delta)
		return

	_update_pursuit_hud(delta)
	_manage_cruiser_spawns(delta)
	_update_cruiser_ai(delta)
	_check_arrest_and_escape(delta)

func _check_infractions(delta: float) -> void:
	var t := player.telemetry
	if t.is_empty():
		return
	var spd: float = absf(float(t.get("speed_kmh", 0.0)))
	# Excessive reckless speeding in the city or near traffic
	if spd > 195.0 and sim.traffic_active_count() > 3:
		add_heat(delta * 0.15)

func _update_pursuit_hud(delta: float) -> void:
	_flash_timer += delta * 4.0
	var flash: bool = fmod(_flash_timer, 1.0) < 0.5
	_heat_badge.visible = true
	_heat_badge.text = "HEAT %d %s  ·  BOUNTY: ¥%s" % [int(heat_tier), "★".repeat(int(heat_tier)), RaceHUD._group(_bounty_bank)]
	_heat_badge.modulate = Color(1.0, 0.4, 0.4) if flash else Color(1.0, 1.0, 1.0)

	_cooldown_bar.visible = escape_timer > 0.5
	_cooldown_bar.value = escape_timer

func _manage_cruiser_spawns(delta: float) -> void:
	_spawn_cooldown -= delta
	var max_cruisers := int(heat_tier)
	# Prune lost or despawned cruisers
	var player_pos := player.global_position
	var active_cruisers: Array[Dictionary] = []
	for c in cruisers:
		var c_pos: Vector3 = sim.get_transform(c.id).origin
		if c_pos.distance_to(player_pos) < 650.0:
			active_cruisers.append(c)
		else:
			_despawn_cruiser(c)
	cruisers = active_cruisers

	if cruisers.size() < max_cruisers and _spawn_cooldown <= 0.0:
		_spawn_cruiser()
		_spawn_cooldown = 4.0

func _spawn_cruiser() -> void:
	var player_pos := player.global_position
	var fwd := -player.global_basis.z
	# Spawn 140m ahead or behind along the road network
	var spawn_pos := player_pos + fwd * 140.0 + Vector3(randf_range(-6.0, 6.0), 0, randf_range(-6.0, 6.0))
	var road := world.nearest_road(spawn_pos, 250.0)
	if road.is_empty():
		return
	var road_pos: Vector3 = road.position + Vector3(0, 1.0, 0)
	var dir: Vector3 = road.tangent

	var car_key := "tatsu_ix"
	var overrides := {"paint": [0.08, 0.08, 0.09], "finish": "gloss", "two_tone": true, "paint2": [0.95, 0.95, 0.95]}
	if heat_tier >= HeatTier.HYPER_PURSUIT:
		car_key = "kurogane_hyper"
		overrides = {"paint": [0.02, 0.02, 0.03], "finish": "matte"}
	elif heat_tier >= HeatTier.INTERCEPTOR and randf() > 0.5:
		car_key = "raijin_r"
		overrides = {"paint": [0.95, 0.95, 0.95], "finish": "gloss", "two_tone": true, "paint2": [0.05, 0.05, 0.06]}

	var cop_id := sim.add_car(car_key, overrides, true, randi())
	sim.reset_car(cop_id, Transform3D(Basis.looking_at(dir, Vector3.UP), road_pos), 40.0)
	sim.set_ai(cop_id, true)
	sim.set_ai_difficulty(cop_id, mini(6, 3 + int(heat_tier)))

	var view := CarView.new()
	add_child(view)
	view.setup(sim, cop_id, car_key, false)

	# Mount Flashing Police Lightbar
	var lb := _create_lightbar()
	view.add_child(lb)

	cruisers.append({"id": cop_id, "view": view, "lightbar": lb, "tier": int(heat_tier)})

func _create_lightbar() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, 1.35, -0.1) # roof mount

	# ---- Lightbar housing (wider, lower-profile for modern look) ----
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.15, 0.09, 0.22)
	box.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.06, 0.06, 0.06)
	sm.metallic = 0.9
	sm.roughness = 0.2
	box.material_override = sm
	root.add_child(box)

	# ---- Double-row LED array: red left, blue right, white center ----
	var red_light := OmniLight3D.new()
	red_light.name = "RedStrobe"
	red_light.light_color = Color(1.0, 0.03, 0.03)
	red_light.light_energy = 5.5
	red_light.omni_range = 18.0
	red_light.omni_attenuation = 1.2
	red_light.position = Vector3(-0.38, 0.08, 0)
	root.add_child(red_light)

	var red_outer := OmniLight3D.new()
	red_outer.name = "RedOuter"
	red_outer.light_color = Color(1.0, 0.05, 0.05)
	red_outer.light_energy = 3.0
	red_outer.omni_range = 10.0
	red_outer.position = Vector3(-0.52, 0.08, 0)
	root.add_child(red_outer)

	var blue_light := OmniLight3D.new()
	blue_light.name = "BlueStrobe"
	blue_light.light_color = Color(0.03, 0.2, 1.0)
	blue_light.light_energy = 5.5
	blue_light.omni_range = 18.0
	blue_light.omni_attenuation = 1.2
	blue_light.position = Vector3(0.38, 0.08, 0)
	root.add_child(blue_light)

	var blue_outer := OmniLight3D.new()
	blue_outer.name = "BlueOuter"
	blue_outer.light_color = Color(0.05, 0.25, 1.0)
	blue_outer.light_energy = 3.0
	blue_outer.omni_range = 10.0
	blue_outer.position = Vector3(0.52, 0.08, 0)
	root.add_child(blue_outer)

	# Center take-down white strobe
	var white_light := OmniLight3D.new()
	white_light.name = "WhiteStrobe"
	white_light.light_color = Color(0.95, 0.97, 1.0)
	white_light.light_energy = 2.5
	white_light.omni_range = 12.0
	white_light.position = Vector3(0, 0.08, 0)
	root.add_child(white_light)

	return root

func _update_cruiser_ai(delta: float) -> void:
	var player_pos := player.global_position
	var t := Time.get_ticks_msec() / 1000.0

	for c in cruisers:
		# Strobe lights animation: rapid alternating pattern (NFS-style)
		var lb: Node3D = c.lightbar
		if lb:
			var phase := fmod(t * 10.0, 1.0)  # Faster flash rate
			var r_light: OmniLight3D = lb.get_node_or_null("RedStrobe")
			var r_outer: OmniLight3D = lb.get_node_or_null("RedOuter")
			var b_light: OmniLight3D = lb.get_node_or_null("BlueStrobe")
			var b_outer: OmniLight3D = lb.get_node_or_null("BlueOuter")
			var w_light: OmniLight3D = lb.get_node_or_null("WhiteStrobe")
			# Alternating chase pattern: red → blue with double-flash
			var red_on: bool = phase < 0.25 or (phase > 0.3 and phase < 0.45)
			var blue_on: bool = phase > 0.5 and phase < 0.75 or (phase > 0.8 and phase < 0.95)
			if r_light: r_light.visible = red_on
			if r_outer: r_outer.visible = red_on
			if b_light: b_light.visible = blue_on
			if b_outer: b_outer.visible = blue_on
			if w_light: w_light.visible = fmod(t * 6.0, 1.0) < 0.3

		# Interceptor PIT maneuver: target rear quarter panel (realistic technique)
		var cop_pos: Vector3 = sim.get_transform(c.id).origin
		var dist := cop_pos.distance_to(player_pos)
		if dist < 45.0 and heat_tier >= HeatTier.INTERCEPTOR:
			# Target the rear quarter panel, not center of mass
			var player_fwd := -sim.get_transform(player.car_id).basis.z
			var rear_quarter := player_pos - player_fwd * 2.0
			var to_target := (rear_quarter - cop_pos).normalized()
			var cop_fwd := -sim.get_transform(c.id).basis.z
			var side := cop_fwd.cross(Vector3.UP).dot(to_target)
			sim.set_input(c.id, clampf(side * 2.0, -1.0, 1.0), 1.0, 0.0, 0.0, 0.0)

func _check_arrest_and_escape(delta: float) -> void:
	var player_pos := player.global_position
	var spd: float = absf(float(player.telemetry.get("speed", 0.0)))
	var min_cop_dist := 9999.0

	for c in cruisers:
		var cop_pos: Vector3 = sim.get_transform(c.id).origin
		min_cop_dist = minf(min_cop_dist, cop_pos.distance_to(player_pos))

	# Busted condition: car stopped (< 6 km/h) near an active police cruiser
	if min_cop_dist < 9.5 and spd < 1.6:
		busted_timer += delta
		_busted_banner.visible = true
		_busted_banner.color.a = clampf(busted_timer / BUSTED_TIME * 0.9, 0.0, 0.9)
		if busted_timer >= BUSTED_TIME:
			_trigger_busted()
			return
	else:
		busted_timer = maxf(0.0, busted_timer - delta * 2.0)
		if busted_timer <= 0.0 and _busted_banner.visible:
			_busted_banner.visible = false

	# Escape condition: out of cruiser proximity (> 160 m)
	if min_cop_dist > 150.0:
		escape_timer += delta
		if escape_timer >= ESCAPE_TIME:
			_trigger_evaded()
	else:
		escape_timer = maxf(0.0, escape_timer - delta * 1.5)

func _trigger_busted() -> void:
	var fine := mini(int(heat_tier) * 2000, Profile.data.credits)
	Profile.spend(fine)
	Profile.save()
	busted.emit(fine)
	if hud:
		hud.toast("BUSTED! FINED ¥%s" % RaceHUD._group(fine), 5.0)
	_reset_pursuit()
	# Recover player car to nearest safe road
	if freeroam_host and freeroam_host.has_method("_recover"):
		freeroam_host.call("_recover")

func _trigger_evaded() -> void:
	var xp_reward := int(heat_tier) * 450
	Profile.add_credits(_bounty_bank)
	Profile.add_xp(xp_reward)
	Profile.save()
	pursuit_evaded.emit(_bounty_bank, xp_reward)
	if hud:
		hud.toast("PURSUIT EVADED! +¥%s  +%d XP" % [RaceHUD._group(_bounty_bank), xp_reward], 4.5)
	_reset_pursuit()

func _reset_pursuit() -> void:
	heat_tier = HeatTier.NONE
	heat_progress = 0.0
	escape_timer = 0.0
	busted_timer = 0.0
	_bounty_bank = 0
	_heat_badge.visible = false
	_cooldown_bar.visible = false
	_busted_banner.visible = false
	for c in cruisers:
		_despawn_cruiser(c)
	cruisers.clear()
	heat_changed.emit(0)

func _despawn_cruiser(c: Dictionary) -> void:
	if c.has("view") and is_instance_valid(c.view):
		c.view.queue_free()
	if c.has("id"):
		sim.set_frozen(c.id, true)
