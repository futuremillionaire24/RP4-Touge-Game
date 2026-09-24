class_name CarData
extends RefCounted
## Display data, economy and body-shape parameters for every car. Physics lives in C++
## (native/src/sim/roster.cpp) under the same keys.

const CARS := {
	"mame_k": {
		"name": "Mame K", "maker": "Kotori", "year": 1992, "price": 9_000, "unlock": "starter",
		"blurb": "A 660 cc kei roadster that thinks it's a supercar. Light enough to carry into any hairpin flat out.",
		"paint": Color(0.95, 0.72, 0.1), "finish": "gloss",
		"body": {"style": "roadster", "roof_h": 1.18, "hood_h": 0.74, "nose_h": 0.55, "deck_h": 0.78, "tail_h": 0.68,
			"cowl": 0.36, "roof_front": 0.48, "roof_back": 0.64, "deck_start": 0.70, "roof_w": 0.78, "clear": 0.13, "open_top": true},
	},
	"hachi_gt": {
		"name": "Hachi GT", "maker": "Toyoda", "year": 1985, "price": 22_000, "unlock": "starter",
		"blurb": "The tofu-delivery legend. 128 hp, perfect balance, and a live axle that dances on mid-corner bumps.",
		"paint": Color(0.93, 0.93, 0.92), "paint2": Color(0.08, 0.08, 0.09), "finish": "gloss", "two_tone": true,
		"body": {"style": "hatch", "roof_h": 1.33, "hood_h": 0.86, "nose_h": 0.66, "deck_h": 0.98, "tail_h": 0.88,
			"cowl": 0.33, "roof_front": 0.45, "roof_back": 0.80, "deck_start": 0.93, "roof_w": 0.84, "clear": 0.14, "popups": true},
	},
	"kyudo_type_s": {
		"name": "Kyudo Type-S", "maker": "Hanada", "year": 1998, "price": 31_000, "unlock": "shop",
		"blurb": "Front-drive, 9,000 rpm, and a cam changeover you feel in your spine. Rotates on lift like a scalpel.",
		"paint": Color(0.93, 0.93, 0.95), "finish": "gloss",
		"body": {"style": "hatch", "roof_h": 1.36, "hood_h": 0.84, "nose_h": 0.62, "deck_h": 1.0, "tail_h": 0.92,
			"cowl": 0.30, "roof_front": 0.43, "roof_back": 0.82, "deck_start": 0.95, "roof_w": 0.86, "clear": 0.14},
	},
	"sylph_s2": {
		"name": "Sylph S2", "maker": "Nisei", "year": 1999, "price": 38_000, "unlock": "starter",
		"blurb": "The drift benchmark. Turbo four, clutch-kick friendly, and a chassis that begs to go sideways.",
		"paint": Color(0.12, 0.2, 0.55), "finish": "metallic",
		"body": {"style": "coupe", "roof_h": 1.29, "hood_h": 0.80, "nose_h": 0.58, "deck_h": 0.92, "tail_h": 0.86,
			"cowl": 0.34, "roof_front": 0.47, "roof_back": 0.68, "deck_start": 0.80, "roof_w": 0.8, "clear": 0.13},
	},
	"rotora_fd": {
		"name": "Rotora FD", "maker": "Matsuda", "year": 1997, "price": 56_000, "unlock": "shop",
		"blurb": "Twin rotors, sequential turbos, curves drawn by a sculptor. Keep it above 5,000 rpm.",
		"paint": Color(0.75, 0.04, 0.06), "finish": "gloss",
		"body": {"style": "wedge", "roof_h": 1.23, "hood_h": 0.74, "nose_h": 0.54, "deck_h": 0.90, "tail_h": 0.86,
			"cowl": 0.36, "roof_front": 0.49, "roof_back": 0.66, "deck_start": 0.80, "roof_w": 0.74, "clear": 0.12, "wing": true},
	},
	"tatsu_ix": {
		"name": "Tatsu IX", "maker": "Mitsuboshi", "year": 2006, "price": 62_000, "unlock": "shop",
		"blurb": "Four-door rally weapon. Active centre diff and boost everywhere; gravel is its home turf.",
		"paint": Color(0.82, 0.83, 0.85), "finish": "metallic",
		"body": {"style": "sedan", "roof_h": 1.45, "hood_h": 0.90, "nose_h": 0.66, "deck_h": 1.02, "tail_h": 0.98,
			"cowl": 0.30, "roof_front": 0.42, "roof_back": 0.70, "deck_start": 0.80, "roof_w": 0.84, "clear": 0.15, "wing": true},
	},
	"senko": {
		"name": "Senko", "maker": "Hanada", "year": 1995, "price": 88_000, "unlock": "shop",
		"blurb": "Aluminium mid-engine precision. Honest, fast and unforgiving if you lift mid-corner.",
		"paint": Color(0.08, 0.08, 0.09), "finish": "pearl", "pearl": Color(0.25, 0.2, 0.5),
		"body": {"style": "mid", "roof_h": 1.17, "hood_h": 0.72, "nose_h": 0.52, "deck_h": 0.94, "tail_h": 0.92,
			"cowl": 0.30, "roof_front": 0.43, "roof_back": 0.58, "deck_start": 0.70, "roof_w": 0.7, "clear": 0.12, "popups": true},
	},
	"titan_rz": {
		"name": "Titan RZ", "maker": "Toyoda", "year": 1998, "price": 92_000, "unlock": "shop",
		"blurb": "Straight-six, twin turbos, and a gearbox built for four-figure horsepower. The Wangan king.",
		"paint": Color(0.95, 0.42, 0.05), "finish": "gloss",
		"body": {"style": "gt", "roof_h": 1.27, "hood_h": 0.80, "nose_h": 0.58, "deck_h": 0.96, "tail_h": 0.93,
			"cowl": 0.36, "roof_front": 0.48, "roof_back": 0.70, "deck_start": 0.82, "roof_w": 0.76, "clear": 0.13, "wing": true},
	},
	"raijin_r": {
		"name": "Raijin R", "maker": "Nisei", "year": 2001, "price": 118_000, "unlock": "shop",
		"blurb": "Godzilla-style launch: twin turbos, torque-split AWD and a computer that knows where you want to go.",
		"paint": Color(0.18, 0.28, 0.62), "finish": "metallic",
		"body": {"style": "gt", "roof_h": 1.36, "hood_h": 0.88, "nose_h": 0.62, "deck_h": 1.02, "tail_h": 0.98,
			"cowl": 0.33, "roof_front": 0.45, "roof_back": 0.72, "deck_start": 0.82, "roof_w": 0.8, "clear": 0.13, "wing": true},
	},
	"kaido_van": {
		"name": "Kaido Van", "maker": "Toyoda", "year": 2004, "price": 18_000, "unlock": "barn",
		"blurb": "A turbo-diesel delivery van with a welded diff and no shame. The touge's favourite joke.",
		"paint": Color(0.9, 0.9, 0.88), "finish": "gloss",
		"body": {"style": "van", "roof_h": 1.98, "hood_h": 1.10, "nose_h": 0.86, "deck_h": 1.9, "tail_h": 1.9,
			"cowl": 0.10, "roof_front": 0.24, "roof_back": 0.97, "deck_start": 0.99, "roof_w": 0.94, "clear": 0.17},
	},
	"mugen_proto": {
		"name": "Mugen Proto", "maker": "Kotori", "year": 2021, "price": 165_000, "unlock": "barn",
		"blurb": "800 kg, a screaming four and aero that pins it to the road. A race car with number plates.",
		"paint": Color(0.1, 0.85, 0.55), "finish": "satin",
		"body": {"style": "proto", "roof_h": 1.10, "hood_h": 0.62, "nose_h": 0.36, "deck_h": 0.92, "tail_h": 0.95,
			"cowl": 0.30, "roof_front": 0.42, "roof_back": 0.58, "deck_start": 0.66, "roof_w": 0.64, "clear": 0.09, "wing": true},
	},
	"kurogane_hyper": {
		"name": "Kurogane Hyper", "maker": "Kurogane", "year": 2026, "price": 1_450_000, "unlock": "championship",
		"blurb": "Twin-turbo V8, electric front axle, 1,000+ hp. The crown of the Neon Touge Festival.",
		"paint": Color(0.05, 0.05, 0.06), "finish": "candy", "pearl": Color(0.6, 0.05, 0.2),
		"body": {"style": "hyper", "roof_h": 1.14, "hood_h": 0.66, "nose_h": 0.40, "deck_h": 0.94, "tail_h": 0.95,
			"cowl": 0.30, "roof_front": 0.44, "roof_back": 0.60, "deck_start": 0.72, "roof_w": 0.66, "clear": 0.10, "wing": true},
	},
}

const FINISHES := {
	"gloss": {"metallic": 0.0, "roughness": 0.25, "flake": 0.0, "pearl": 0.0, "coat": 1.0, "gloss": 0.92, "candy": 0.0},
	"metallic": {"metallic": 0.7, "roughness": 0.34, "flake": 0.8, "pearl": 0.0, "coat": 1.0, "gloss": 0.9, "candy": 0.0},
	"pearl": {"metallic": 0.45, "roughness": 0.3, "flake": 0.5, "pearl": 0.8, "coat": 1.0, "gloss": 0.92, "candy": 0.0},
	"matte": {"metallic": 0.0, "roughness": 0.75, "flake": 0.0, "pearl": 0.0, "coat": 0.0, "gloss": 0.2, "candy": 0.0},
	"satin": {"metallic": 0.2, "roughness": 0.5, "flake": 0.2, "pearl": 0.0, "coat": 0.4, "gloss": 0.55, "candy": 0.0},
	"chrome": {"metallic": 1.0, "roughness": 0.06, "flake": 0.0, "pearl": 0.0, "coat": 1.0, "gloss": 0.96, "candy": 0.0},
	"candy": {"metallic": 0.8, "roughness": 0.2, "flake": 0.6, "pearl": 0.4, "coat": 1.0, "gloss": 0.96, "candy": 0.9},
}

## Stock performance index (from tools/benchmark via NTSim.benchmark, rounded). Used to pick
## rivals for class-limited events without running the benchmark at race time.
const STOCK_PI := {
	"mame_k": 335, "hachi_gt": 376, "kyudo_type_s": 608, "sylph_s2": 545, "rotora_fd": 579, "tatsu_ix": 658,
	"senko": 601, "titan_rz": 617, "raijin_r": 690, "kaido_van": 206, "mugen_proto": 779, "kurogane_hyper": 897,
}

static func keys() -> Array:
	return CARS.keys()

static func pi_class(pi: int) -> int:
	if pi <= 400: return 0
	if pi <= 580: return 1
	if pi <= 640: return 2
	if pi <= 720: return 3
	if pi <= 820: return 4
	if pi <= 920: return 5
	return 6

const CLASS_NAMES := ["D", "C", "B", "A", "S1", "S2", "X"]
const CLASS_COLORS := [Color(0.35, 0.8, 1.0), Color(0.45, 1.0, 0.55), Color(1.0, 0.85, 0.2), Color(1.0, 0.45, 0.15),
	Color(0.95, 0.2, 0.35), Color(0.75, 0.3, 1.0), Color(0.3, 1.0, 0.9)]
const CLASS_MAX_PI := [400, 580, 640, 720, 820, 920, 999]

static func class_label(pi: int) -> String:
	return "%s %d" % [CLASS_NAMES[pi_class(pi)], pi]

## Cars eligible for a class limit (inclusive), strongest first.
static func cars_up_to_class(class_max: int) -> Array:
	var out := []
	for k in CARS.keys():
		if pi_class(STOCK_PI.get(k, 500)) <= class_max:
			out.append(k)
	out.sort_custom(func(a, b): return STOCK_PI[a] > STOCK_PI[b])
	return out

static func get_car(key: String) -> Dictionary:
	return CARS.get(key, CARS["sylph_s2"])
