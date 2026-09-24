extends RefCounted
## Rim design + finish catalogue for CarWheels (no class_name: preload it).
## Every design is a parameter set for the procedural rim builder in wheel_geo.gd. All lengths
## are metres and are scaled to the real rim size at build time only where noted.
##
## Families:
##   "spoke"  straight / twisted spokes (tapered, filleted into hub and outer ring)
##   "split"  twin spokes that converge at the hub (split-spoke, CE28-like)
##   "y"      spokes that fork into a Y towards the rim
##   "cross"  two crossing lattices (BBS RS / LM-like mesh)
##   "holes"  a solid disc with oval / round windows (steel wheels, 5-hole kei alloys)

const BASE := {
	"name": "", "blurb": "", "family": "spoke", "n": 5,
	"w_in": 0.04, "w_out": 0.035,        # spoke width at hub / at outer ring (m)
	"fil_in": 0.014, "fil_out": 0.014,   # extra fillet width where spokes meet hub / ring (m)
	"fil_len": 0.25,                     # fillet length as a fraction of spoke length
	"thick": 0.03,                       # axial depth of the spoke side walls (m)
	"concave": 0.02, "k": 1.5,           # hub depth below the face ring + bowl exponent
	"twist": 0.0,                        # angular sweep hub->rim (rad)
	"crown": 0.0015, "cham": 0.003,      # top rounding / edge chamfer (m)
	"lip_w": 0.012, "dish": 0.004,       # lip floor radial width, lip step depth (m)
	"ring_w": 0.008,                     # face ring width inside the lip (m)
	"polished_lip": false,
	"hub_r": 0.078, "cap": "flat",       # hub pad radius; cap: flat/dome/bore/lock/hubcap
	"bolts": 0,                          # assembly bolts on the face ring (multi-piece look)
	"split": 0.0, "t_split": 0.45,       # split / Y gap at the rim (m) and Y fork point
	"hole_rc": 0.0, "hole_hl": 0.0, "hole_hw": 0.0, # "holes": window centre radius, half length, half width
	"steps": 8,
}

const DESIGNS := {
	"forged6": {"name": "Forged 6", "blurb": "Six straight forged spokes, deep concave. The drift-scene icon.",
		"n": 6, "w_in": 0.024, "w_out": 0.03, "fil_in": 0.016, "fil_out": 0.012, "thick": 0.036,
		"concave": 0.042, "k": 1.8, "crown": 0.0008, "cham": 0.0035, "lip_w": 0.011, "dish": 0.005, "cap": "flat"},
	"spoke5": {"name": "Classic 5", "blurb": "Wide tapered five-spoke with soft fillets.",
		"n": 5, "w_in": 0.052, "w_out": 0.032, "fil_in": 0.02, "fil_out": 0.022, "thick": 0.03,
		"concave": 0.026, "k": 1.4, "crown": 0.004, "cham": 0.004, "cap": "dome"},
	"sport5": {"name": "Sport 5", "blurb": "Slim five-spoke, light and straight. Hot-hatch favourite.",
		"n": 5, "w_in": 0.034, "w_out": 0.027, "fil_in": 0.016, "fil_out": 0.016, "thick": 0.03,
		"concave": 0.022, "k": 1.5, "crown": 0.0015, "cham": 0.003, "cap": "flat"},
	"curve5": {"name": "Swept 5", "blurb": "Five curved spokes with a directional sweep.",
		"n": 5, "w_in": 0.05, "w_out": 0.03, "fil_in": 0.02, "fil_out": 0.02, "thick": 0.03,
		"concave": 0.024, "k": 1.4, "twist": 0.32, "crown": 0.005, "cham": 0.003, "cap": "dome"},
	"oem5": {"name": "OEM Star 5", "blurb": "Factory five-spoke star: flat face, flared spokes.",
		"n": 5, "w_in": 0.046, "w_out": 0.058, "fil_in": 0.018, "fil_out": 0.03, "thick": 0.026,
		"concave": 0.012, "k": 1.2, "crown": 0.006, "cham": 0.004, "ring_w": 0.012, "cap": "dome"},
	"split5": {"name": "Split 5", "blurb": "Five twin spokes that split towards the lip.",
		"family": "split", "n": 5, "w_in": 0.017, "w_out": 0.016, "split": 0.022, "fil_in": 0.01, "fil_out": 0.01,
		"thick": 0.03, "concave": 0.03, "k": 1.6, "crown": 0.001, "cham": 0.0025, "cap": "flat"},
	"spoke7": {"name": "Seven", "blurb": "Seven straight spokes; the one-piece cast race look.",
		"n": 7, "w_in": 0.022, "w_out": 0.024, "fil_in": 0.013, "fil_out": 0.012, "thick": 0.032,
		"concave": 0.03, "k": 1.7, "crown": 0.001, "cham": 0.003, "cap": "flat"},
	"rally8": {"name": "Rally 8", "blurb": "Eight thin gravel-proof spokes. Gold or white, obviously.",
		"n": 8, "w_in": 0.019, "w_out": 0.022, "fil_in": 0.012, "fil_out": 0.012, "thick": 0.03,
		"concave": 0.026, "k": 1.6, "crown": 0.0012, "cham": 0.0025, "lip_w": 0.013, "cap": "flat"},
	"watanabe8": {"name": "Old-School 8", "blurb": "Eight stubby spokes and tear-drop windows. Eighties touge.",
		"n": 8, "w_in": 0.03, "w_out": 0.024, "fil_in": 0.022, "fil_out": 0.034, "fil_len": 0.4, "thick": 0.026,
		"concave": 0.008, "k": 1.2, "crown": 0.004, "cham": 0.004, "lip_w": 0.02, "dish": 0.016,
		"polished_lip": true, "hub_r": 0.07, "cap": "bore"},
	"mesh_rs": {"name": "Mesh RS", "blurb": "Cross-laced mesh, stepped polished lip and assembly bolts.",
		"family": "cross", "n": 15, "w_in": 0.0085, "w_out": 0.009, "fil_in": 0.004, "fil_out": 0.006, "thick": 0.028,
		"concave": 0.004, "k": 1.0, "twist": 0.2, "crown": 0.0022, "cham": 0.0015, "lip_w": 0.03, "dish": 0.03,
		"ring_w": 0.016, "polished_lip": true, "bolts": 30, "hub_r": 0.074, "cap": "dome", "steps": 7},
	"mesh_lm": {"name": "Mesh LM", "blurb": "Concave cross-spoke mesh with a polished lip. Grand-touring royalty.",
		"family": "cross", "n": 10, "w_in": 0.011, "w_out": 0.011, "fil_in": 0.006, "fil_out": 0.008, "thick": 0.032,
		"concave": 0.03, "k": 1.5, "twist": 0.24, "crown": 0.002, "cham": 0.002, "lip_w": 0.022, "dish": 0.014,
		"ring_w": 0.014, "polished_lip": true, "bolts": 20, "hub_r": 0.076, "cap": "dome", "steps": 8},
	"deep3": {"name": "Deep Dish 3P", "blurb": "Three-piece, flat five-spoke centre sunk behind a huge polished lip.",
		"n": 5, "w_in": 0.044, "w_out": 0.036, "fil_in": 0.02, "fil_out": 0.02, "thick": 0.024,
		"concave": 0.0, "k": 1.0, "crown": 0.0015, "cham": 0.003, "lip_w": 0.05, "dish": 0.058,
		"ring_w": 0.014, "polished_lip": true, "bolts": 36, "cap": "flat"},
	"turbofan": {"name": "Turbofan", "blurb": "Forged aero disc: swept blades pull air across the brakes.",
		"n": 18, "w_in": 0.0095, "w_out": 0.03, "fil_in": 0.003, "fil_out": 0.006, "thick": 0.022,
		"concave": 0.018, "k": 1.3, "twist": 0.62, "crown": 0.003, "cham": 0.0018, "ring_w": 0.012,
		"hub_r": 0.085, "cap": "dome", "steps": 9},
	"centerlock": {"name": "Centre-Lock", "blurb": "Motorsport twin seven-spoke with a single centre-lock nut.",
		"family": "split", "n": 7, "w_in": 0.012, "w_out": 0.012, "split": 0.016, "fil_in": 0.008, "fil_out": 0.008,
		"thick": 0.032, "concave": 0.036, "k": 1.7, "crown": 0.001, "cham": 0.0022, "hub_r": 0.072, "cap": "lock"},
	"steel": {"name": "Steel + Cap", "blurb": "Pressed steel with vent windows and a plastic hub cap. Honest work.",
		"family": "holes", "n": 8, "hole_rc": 0.132, "hole_hl": 0.017, "hole_hw": 0.012, "thick": 0.004,
		"concave": 0.018, "k": 1.0, "crown": 0.0, "cham": 0.0008, "lip_w": 0.012, "dish": 0.008,
		"hub_r": 0.1, "cap": "hubcap", "steps": 8},
	"hole5": {"name": "Five-Hole", "blurb": "Cast disc with five round windows; tiny, light, eighties kei.",
		"family": "holes", "n": 5, "hole_rc": 0.108, "hole_hl": 0.027, "hole_hw": 0.027, "thick": 0.018,
		"concave": 0.004, "k": 1.0, "crown": 0.0, "cham": 0.003, "lip_w": 0.012, "dish": 0.006,
		"hub_r": 0.06, "cap": "dome", "steps": 10},
}

## Paint finish presets for the rim face. lip: finish of the outer lip when the design has a
## polished lip ("polish") or always the face finish ("match").
const FINISHES := {
	"silver": {"name": "Silver", "color": Color(0.62, 0.63, 0.65), "metal": 0.9, "rough": 0.28, "coat": 0.6, "flake": 0.7},
	"hyper_silver": {"name": "Hyper Silver", "color": Color(0.46, 0.47, 0.49), "metal": 1.0, "rough": 0.16, "coat": 0.8, "flake": 0.9},
	"gunmetal": {"name": "Gunmetal", "color": Color(0.16, 0.165, 0.18), "metal": 0.9, "rough": 0.3, "coat": 0.6, "flake": 0.6},
	"bronze": {"name": "Bronze", "color": Color(0.36, 0.25, 0.13), "metal": 0.95, "rough": 0.3, "coat": 0.6, "flake": 0.5},
	"gold": {"name": "Gold", "color": Color(0.72, 0.55, 0.22), "metal": 0.95, "rough": 0.26, "coat": 0.6, "flake": 0.6},
	"white": {"name": "White", "color": Color(0.84, 0.84, 0.82), "metal": 0.0, "rough": 0.32, "coat": 0.8, "flake": 0.0},
	"black": {"name": "Gloss Black", "color": Color(0.018, 0.018, 0.02), "metal": 0.0, "rough": 0.22, "coat": 1.0, "flake": 0.0},
	"matte_black": {"name": "Matte Black", "color": Color(0.03, 0.03, 0.032), "metal": 0.0, "rough": 0.62, "coat": 0.0, "flake": 0.0},
	"polished": {"name": "Polished", "color": Color(0.9, 0.9, 0.91), "metal": 1.0, "rough": 0.07, "coat": 0.0, "flake": 0.0},
	"machined": {"name": "Black Machined", "color": Color(0.02, 0.02, 0.022), "metal": 0.0, "rough": 0.24, "coat": 1.0, "flake": 0.0, "machined": true},
	"chrome": {"name": "Chrome", "color": Color(0.96, 0.96, 0.97), "metal": 1.0, "rough": 0.03, "coat": 0.0, "flake": 0.0},
}

const CALIPER_COLORS := {
	"red": Color(0.62, 0.035, 0.03), "gold": Color(0.78, 0.55, 0.12), "yellow": Color(0.9, 0.68, 0.04),
	"black": Color(0.025, 0.025, 0.027), "silver": Color(0.55, 0.56, 0.58), "blue": Color(0.06, 0.16, 0.55),
	"orange": Color(0.9, 0.3, 0.03), "raw": Color(0.3, 0.29, 0.28),
}

## Disc styles: 0 plain vented, 1 cross-drilled, 2 slotted, 3 carbon-ceramic (drilled), 4 drum.
const DISC_STYLES := ["plain", "drilled", "slotted", "ceramic", "drum"]

static func design(id: String) -> Dictionary:
	var d: Dictionary = BASE.duplicate()
	d.merge(DESIGNS.get(id, DESIGNS["spoke5"]), true)
	d["id"] = id if DESIGNS.has(id) else "spoke5"
	return d

static func finish(id: String) -> Dictionary:
	var f: Dictionary = {"machined": false}
	f.merge(FINISHES.get(id, FINISHES["silver"]), true)
	f["id"] = id if FINISHES.has(id) else "silver"
	return f
