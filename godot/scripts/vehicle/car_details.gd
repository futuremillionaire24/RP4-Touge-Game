class_name CarDetails
extends RefCounted
## Car details meeting Gran Turismo / Forza Horizon standards:
## - Multi-element headlights (lens, chrome projector bowl, DRL, popup lids)
## - Sculpted multi-segment taillights (brake, reverse, indicator)
## - Front chin splitter and aerodynamic grille slats
## - Rear aero diffuser with vertical fins
## - Aerodynamic teardrop side mirrors with chrome glass face
## - Interior cockpit silhouette (dashboard cowl, sport steering wheel, twin bucket seats)
## - Twin beveled polished exhaust tips
## Preserves root metadata `exhaust_local` and `brake_lights`.

static var last_build_us := 0

static func _box(parent: Node3D, name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _cyl(parent: Node3D, name: String, top_r: float, bot_r: float, height: float, segs: int, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = height
	cm.radial_segments = segs
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func add(root: Node3D, b: Dictionary, dims: Dictionary, paint: Material, car: Dictionary) -> void:
	var hx: float = dims.hx
	var hz: float = dims.hz
	var cg: float = dims.cg
	var front := CarBody.profile(b, 0.03)
	var rear := CarBody.profile(b, 0.985)
	var lights := Node3D.new()
	lights.name = "Lights"
	root.add_child(lights)

	# =========================================================================
	# 1. HEADLIGHTS & FRONT LIGHTING (Projector lenses + Reflector housings)
	# =========================================================================
	var hl_y: float = front.top - 0.075 - cg
	var popups: bool = b.get("popups", false)

	for side in [-1.0, 1.0]:
		var x: float = side * hx * 0.62
		if popups:
			# Popup lid on hood with subtle panel outline
			_box(lights, "PopupLid", Vector3(0.35, 0.025, 0.22), Vector3(x, front.top - cg + 0.006, -hz + 0.28), paint)
			# Front light housing beneath
			_box(lights, "HeadlightHousing", Vector3(0.31, 0.075, 0.06), Vector3(x, hl_y + 0.02, -hz + 0.05), CarMaterials.shared("trim"))
			_box(lights, "Headlight", Vector3(0.27, 0.06, 0.02), Vector3(x, hl_y + 0.02, -hz + 0.025), CarMaterials.shared("headlight"))
		else:
			# Aerodynamic contoured headlight bucket
			_box(lights, "HeadlightBezel", Vector3(0.36, 0.10, 0.07), Vector3(x, hl_y, -hz + 0.06), CarMaterials.shared("trim"))
			# Chrome inner reflector bowl
			_box(lights, "HeadlightReflector", Vector3(0.32, 0.08, 0.03), Vector3(x, hl_y, -hz + 0.04), CarMaterials.shared("chrome"))
			# Emissive projector lens / LED cluster
			_box(lights, "Headlight", Vector3(0.28, 0.065, 0.015), Vector3(x, hl_y, -hz + 0.025), CarMaterials.shared("headlight"))
			# DRL / Accent line (Daytime Running Light)
			_box(lights, "DRL_Accent", Vector3(0.32, 0.015, 0.012), Vector3(x, hl_y - 0.035, -hz + 0.024), CarMaterials.shared("headlight"))

		# Turn indicator on bumper corners
		_box(lights, "Indicator", Vector3(0.09, 0.05, 0.045), Vector3(side * hx * 0.85, hl_y - 0.025, -hz + 0.09), CarMaterials.shared("indicator"))

	# =========================================================================
	# 2. TAILLIGHTS (Multi-element GT style: Brake, Amber, Reverse)
	# =========================================================================
	var tl_y: float = rear.top - 0.115 - cg
	for side in [-1.0, 1.0]:
		var tx: float = side * hx * 0.62
		# Dark taillight housing
		_box(lights, "TaillightBezel", Vector3(0.44, 0.12, 0.06), Vector3(tx, tl_y, hz - 0.03), CarMaterials.shared("trim"))
		# Primary red brake lamp (outer section)
		_box(lights, "Taillight", Vector3(0.26, 0.09, 0.02), Vector3(tx + side * 0.07, tl_y, hz - 0.005), CarMaterials.shared("taillight"))
		# Amber turn indicator section (outer edge)
		_box(lights, "RearIndicator", Vector3(0.07, 0.08, 0.02), Vector3(tx + side * 0.16, tl_y, hz - 0.005), CarMaterials.shared("indicator"))
		# White reverse lamp (inner edge)
		_box(lights, "ReverseLight", Vector3(0.07, 0.07, 0.02), Vector3(tx - side * 0.09, tl_y, hz - 0.005), CarMaterials.shared("headlight"))

	# Center high-mount third brake light (CHMSL)
	_box(lights, "Taillight_CHMSL", Vector3(0.24, 0.025, 0.03), Vector3(0, rear.top + 0.01 - cg, hz - 0.12), CarMaterials.shared("taillight"))

	# =========================================================================
	# 3. GRILLE, FRONT SPLITTER & LOWER AERODYNAMICS
	# =========================================================================
	var grille_y: float = front.bottom + 0.12 - cg
	# Recessed dark radiator intake opening
	_box(root, "GrilleRecess", Vector3(hx * 1.15, 0.14, 0.08), Vector3(0, grille_y, -hz + 0.05), CarMaterials.shared("trim"))
	# Horizontal grille slat detail
	_box(root, "GrilleSlat", Vector3(hx * 1.1, 0.015, 0.03), Vector3(0, grille_y, -hz + 0.02), CarMaterials.shared("trim"))
	# Front chin aerodynamic splitter
	_box(root, "FrontSplitter", Vector3(hx * 1.5, 0.03, 0.18), Vector3(0, front.bottom + 0.03 - cg, -hz + 0.07), CarMaterials.shared("trim"))

	# Rear bumper aerodynamic diffuser fins
	var diff_y: float = rear.bottom + 0.06 - cg
	_box(root, "RearDiffuserTray", Vector3(hx * 1.3, 0.025, 0.35), Vector3(0, diff_y, hz - 0.18), CarMaterials.shared("trim"))
	for fin_x in [-hx * 0.38, -hx * 0.14, hx * 0.14, hx * 0.38]:
		_box(root, "DiffuserFin", Vector3(0.018, 0.065, 0.32), Vector3(fin_x, diff_y - 0.025, hz - 0.18), CarMaterials.shared("trim"))

	# =========================================================================
	# 4. NUMBER PLATES
	# =========================================================================
	_box(root, "PlateFront", Vector3(0.33, 0.14, 0.015), Vector3(0, front.bottom + 0.21 - cg, -hz - 0.005), CarMaterials.shared("plate"))
	_box(root, "PlateRear", Vector3(0.33, 0.16, 0.015), Vector3(0, rear.bottom + 0.28 - cg, hz + 0.008), CarMaterials.shared("plate"))

	# =========================================================================
	# 5. AERODYNAMIC SIDE MIRRORS (Sculpted housing + chrome mirror glass)
	# =========================================================================
	var mirror_t := float(b.cowl) + 0.035
	var cowl_p := CarBody.profile(b, mirror_t)
	for side in [-1.0, 1.0]:
		var mx: float = side * (hx * cowl_p.w * 0.96 + 0.055)
		var my: float = cowl_p.top + 0.045 - cg
		var mz: float = lerpf(-hz, hz, mirror_t)
		# Aerodynamic mounting stalk
		_box(root, "MirrorStalk", Vector3(0.035, 0.025, 0.035), Vector3(mx - side * 0.022, my - 0.015, mz), CarMaterials.shared("trim"))
		# Sculpted aerodynamic teardrop shell
		var shell_mi := MeshInstance3D.new()
		shell_mi.name = "MirrorShell"
		var sm := SphereMesh.new()
		sm.radius = 0.048
		sm.height = 0.11
		sm.radial_segments = 12
		sm.rings = 6
		shell_mi.mesh = sm
		shell_mi.position = Vector3(mx, my, mz)
		shell_mi.rotation = Vector3(0, side * -0.15, 0)
		shell_mi.scale = Vector3(1.0, 0.72, 1.3)
		shell_mi.material_override = paint
		root.add_child(shell_mi)
		# Tilted chrome mirror glass
		var glass_inst := _box(root, "MirrorGlass", Vector3(0.085, 0.058, 0.01), Vector3(mx, my, mz + 0.055), CarMaterials.shared("chrome"))
		# Slight angle towards driver
		glass_inst.rotation = Vector3(0, side * -0.18, 0)

	# =========================================================================
	# 6. INTERIOR COCKPIT SILHOUETTE (Visible through windshield & windows)
	# =========================================================================
	# Adds solid presence to prevent "empty transparent bubble" look
	var roof_front: float = b.get("roof_front", 0.45)
	var roof_back: float = b.get("roof_back", 0.70)
	var cowl_pos_z: float = lerpf(-hz, hz, float(b.cowl))
	var cabin_mid_z: float = lerpf(-hz, hz, (roof_front + roof_back) * 0.5)

	# Dark dashboard top cowl under windshield
	_box(root, "Interior_Dash", Vector3(hx * 1.35, 0.09, 0.36), Vector3(0, cowl_p.top - 0.05 - cg, cowl_pos_z + 0.22), CarMaterials.shared("trim"))
	# Instrument binnacle hump (driver side on right for JDM RHD cars)
	_box(root, "Interior_Binnacle", Vector3(0.22, 0.055, 0.16), Vector3(hx * 0.42, cowl_p.top - 0.005 - cg, cowl_pos_z + 0.24), CarMaterials.shared("trim"))

	# Sport 3-spoke steering wheel
	var sw_z: float = cowl_pos_z + 0.36
	var sw_y: float = cowl_p.top - 0.04 - cg
	_cyl(root, "Interior_SteeringRim", 0.15, 0.15, 0.022, 16, Vector3(hx * 0.42, sw_y, sw_z), Vector3(PI * 0.38, 0, 0), CarMaterials.shared("trim"))
	_cyl(root, "Interior_SteeringHub", 0.045, 0.045, 0.03, 10, Vector3(hx * 0.42, sw_y, sw_z - 0.01), Vector3(PI * 0.38, 0, 0), CarMaterials.shared("rim_dark"))

	# Twin sculpted sports bucket seats (proportioned cleanly for coupes & open roadsters)
	var is_open: bool = b.get("open_top", false)
	var seat_z: float = cabin_mid_z - 0.05
	var seat_y: float = cowl_p.top - (0.24 if is_open else 0.14) - cg
	var seat_h: float = 0.28 if is_open else 0.40
	var seat_w: float = 0.32 if is_open else 0.36
	var hr_h: float = 0.09 if is_open else 0.12
	var hr_w: float = 0.16 if is_open else 0.19
	for side in [-1.0, 1.0]:
		var sx: float = side * hx * 0.45
		# Contoured seat bottom cushion
		_box(root, "Interior_SeatBottom", Vector3(seat_w, 0.08, 0.32), Vector3(sx, seat_y - 0.04, seat_z - 0.12), CarMaterials.shared("trim"))
		# Bolstered main seatback
		_box(root, "Interior_SeatBack", Vector3(seat_w, seat_h, 0.11), Vector3(sx, seat_y + seat_h * 0.5, seat_z), CarMaterials.shared("trim"))
		# Sculpted shoulder bolsters
		_box(root, "Interior_BolsterL", Vector3(0.04, seat_h * 0.65, 0.08), Vector3(sx - seat_w * 0.48, seat_y + seat_h * 0.45, seat_z - 0.02), CarMaterials.shared("trim"))
		_box(root, "Interior_BolsterR", Vector3(0.04, seat_h * 0.65, 0.08), Vector3(sx + seat_w * 0.48, seat_y + seat_h * 0.45, seat_z - 0.02), CarMaterials.shared("trim"))
		# Tapered contoured headrest
		_box(root, "Interior_Headrest", Vector3(hr_w, hr_h, 0.08), Vector3(sx, seat_y + seat_h + hr_h * 0.45, seat_z + 0.01), CarMaterials.shared("trim"))

	# Interior rearview mirror on windshield
	if not is_open:
		_box(root, "Interior_RearviewMirror", Vector3(0.14, 0.04, 0.02), Vector3(0, cowl_p.top + 0.28 - cg, cowl_pos_z + 0.35), CarMaterials.shared("chrome"))

	# =========================================================================
	# 7. REAR SPOILER / WING (If car has wing spec)
	# =========================================================================
	if b.get("wing", false):
		var ws: float = 0.97
		var wy: float = rear.top + 0.22 - cg
		var wz: float = lerpf(-hz, hz, ws) - 0.15
		# Aerofoil main plane
		_box(root, "Wing", Vector3(hx * 1.8, 0.035, 0.28), Vector3(0, wy, wz), paint)
		for side in [-1.0, 1.0]:
			# Upright mounting stanchions (carbon/dark trim)
			_box(root, "WingPost", Vector3(0.04, 0.22, 0.12), Vector3(side * hx * 0.55, wy - 0.11, wz), CarMaterials.shared("trim"))
			# Side aerodynamic endplates
			_box(root, "Endplate", Vector3(0.02, 0.16, 0.32), Vector3(side * hx * 0.89, wy + 0.03, wz), paint)

	# =========================================================================
	# 8. EXHAUST SYSTEM (Twin polished beveled tips)
	# =========================================================================
	var ex_y: float = rear.bottom + 0.09 - cg
	var ex_z: float = hz + 0.02
	var ex_x_base: float = hx * 0.45
	for offset_x in [0.0, 0.11]:
		var tip_pos := Vector3(ex_x_base + offset_x, ex_y, ex_z)
		# Polished outer chrome barrel
		_cyl(root, "ExhaustOuter", 0.046, 0.046, 0.18, 16, tip_pos, Vector3(PI * 0.5, 0, 0), CarMaterials.shared("chrome"))
		# Dark hollow interior bore
		_cyl(root, "ExhaustBore", 0.038, 0.038, 0.02, 14, tip_pos + Vector3(0, 0, 0.085), Vector3(PI * 0.5, 0, 0), CarMaterials.shared("trim"))

	root.set_meta("exhaust_local", Vector3(ex_x_base + 0.055, ex_y, ex_z + 0.10))
	root.set_meta("brake_lights", lights.get_children().filter(func(n): return n.name.begins_with("Taillight")))

## Called by CarView every physics tick: brake lights and headlight emissive.
static func set_light_state(root: Node3D, braking: bool, lights_on: bool) -> void:
	for m in root.get_meta("brake_lights", []):
		var mat: StandardMaterial3D = m.material_override
		if mat != null:
			mat.emission_energy_multiplier = 4.8 if braking else (1.4 if lights_on else 0.5)
