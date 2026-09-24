class_name CarData
extends RefCounted
## Display data and economy for every car. Physics lives in C++ (native/src/sim/roster.cpp) under
## the same keys; the 3D models are baked by tools/carbake into res://assets/cars/<key>/.
## Real cars, real names: private build only (trademarks belong to their owners). Model credits
## (CC-BY 4.0) are in res://assets/cars/<key>/<key>.json and on the credits screen.
##   livery: "" = plain paint; "tint" = the model's paint texture is multiplied by the paint colour
##           (white-based artwork such as stripes); "fixed" = the texture is the colour (roundels).

const DEFAULT_KEY := "bmw_m3_e30"

const CARS := {
	"abarth_500": {
		"name": "Fiat Abarth 500", "maker": "Abarth", "country": "IT", "year": 2008, "price": 32_000, "unlock": "starter",
		"blurb": "The scorpion-badged city car: a 1.4 T-Jet turbo, a Sport button and a rasp that fills every tunnel on the Riviera. Tiny, light and happiest flat out through the hairpins.",
		"paint": Color(0.92, 0.92, 0.9), "finish": "gloss", "livery": "tint",
	},
	"golf_gti": {
		"name": "Volkswagen Golf GTI", "maker": "Volkswagen", "country": "DE", "year": 2005, "price": 38_000, "unlock": "starter",
		"blurb": "The Mk5 that brought the GTI back: 200 PS from a 2.0 TFSI, plaid seats and a chassis that shrugs off broken Alpine tarmac. The hot hatch benchmark.",
		"paint": Color(0.62, 0.03, 0.04), "finish": "gloss", "livery": "tint",
	},
	"bmw_m3_e30": {
		"name": "BMW M3 (E30)", "maker": "BMW", "country": "DE", "year": 1987, "price": 58_000, "unlock": "starter",
		"blurb": "Born to homologate a touring car: a 2.3-litre S14 four that loves 7,000 rpm, box arches, a dog-leg gearbox and perfect balance. The driver's M car.",
		"paint": Color(0.55, 0.02, 0.03), "finish": "gloss",
	},
	"porsche_930": {
		"name": "Porsche 911 Turbo (930)", "maker": "Porsche", "country": "DE", "year": 1975, "price": 125_000, "unlock": "shop",
		"blurb": "The Widowmaker. A 3.0 flat-six turbo that does nothing, nothing, then everything at once, a whale-tail spoiler and an engine hung out behind the rear axle.",
		"paint": Color(0.025, 0.025, 0.03), "finish": "metallic",
	},
	"jaguar_etype": {
		"name": "Jaguar E-Type Lightweight", "maker": "Jaguar", "country": "GB", "year": 1963, "price": 1_750_000, "unlock": "barn",
		"blurb": "One of twelve aluminium-bodied racers built to beat Ferrari at Le Mans. Enzo himself called the E-Type the most beautiful car ever made.",
		"paint": Color(0.06, 0.22, 0.14), "finish": "gloss", "livery": "fixed",
	},
	"mb_300sl": {
		"name": "Mercedes-Benz 300 SL Gullwing", "maker": "Mercedes-Benz", "country": "DE", "year": 1955, "price": 1_450_000, "unlock": "barn",
		"blurb": "The first fuel-injected road car and the fastest of its day. Its spaceframe was so tall the doors had to open upwards - and the Gullwing was born.",
		"paint": Color(0.7, 0.71, 0.72), "finish": "metallic",
	},
	"defender_90": {
		"name": "Land Rover Defender 90", "maker": "Land Rover", "country": "GB", "year": 1998, "price": 42_000, "unlock": "shop",
		"blurb": "Permanent four-wheel drive, a Td5 diesel and approach angles for days. It will climb anything on the map - just don't ask it to hurry.",
		"paint": Color(0.1, 0.2, 0.16), "finish": "gloss",
	},
	"audi_quattro": {
		"name": "Audi quattro", "maker": "Audi", "country": "DE", "year": 1983, "price": 82_000, "unlock": "shop",
		"blurb": "The car that changed rallying forever. Five cylinders, a big turbo and permanent all-wheel drive that made the Monte-Carlo Rally's snowy cols its playground.",
		"paint": Color(0.9, 0.9, 0.88), "finish": "gloss",
	},
	"jaguar_ftype": {
		"name": "Jaguar F-Type R Coupé", "maker": "Jaguar", "country": "GB", "year": 2017, "price": 115_000, "unlock": "shop",
		"blurb": "A supercharged 5.0 V8 with the most theatrical exhaust on sale: pops, bangs and crackles on every lift. All-wheel drive keeps the 550 PS pointing forwards.",
		"paint": Color(0.6, 0.05, 0.04), "finish": "metallic",
	},
	"mb_g63": {
		"name": "Mercedes-AMG G 63", "maker": "Mercedes-AMG", "country": "DE", "year": 2019, "price": 178_000, "unlock": "shop",
		"blurb": "A 2.6-tonne military-grade brick with a hand-built 4.0 biturbo V8 and three locking differentials. Absurd, unstoppable, and genuinely quick.",
		"paint": Color(0.55, 0.04, 0.03), "finish": "gloss",
	},
	"bmw_m4": {
		"name": "BMW M4 Coupé (F82)", "maker": "BMW", "country": "DE", "year": 2015, "price": 74_000, "unlock": "shop",
		"blurb": "Twin-turbo S55 straight-six, carbon roof, Active M Differential and 550 Nm from 1,850 rpm. Rear-drive, and it won't let you forget it.",
		"paint": Color(0.1, 0.42, 0.78), "finish": "metallic",
	},
	"audi_r8": {
		"name": "Audi R8 V10 performance", "maker": "Audi", "country": "DE", "year": 2019, "price": 188_000, "unlock": "shop",
		"blurb": "A 5.2-litre naturally aspirated V10 screaming to 8,700 rpm behind your head, with quattro all-wheel drive underneath. An everyday supercar.",
		"paint": Color(0.95, 0.7, 0.04), "finish": "gloss",
	},
	"porsche_992": {
		"name": "Porsche 911 Turbo S (992)", "maker": "Porsche", "country": "DE", "year": 2020, "price": 235_000, "unlock": "shop",
		"blurb": "650 PS, all-wheel drive and a PDK that fires shifts in milliseconds: 0-100 km/h in 2.7 seconds, in any weather, on any road. Relentless.",
		"paint": Color(0.7, 0.7, 0.65), "finish": "satin",
	},
	"ferrari_testarossa": {
		"name": "Ferrari Testarossa", "maker": "Ferrari", "country": "IT", "year": 1985, "price": 148_000, "unlock": "shop",
		"blurb": "Side strakes, a flat-twelve with red cam covers and a rear track wider than most cars. The poster on every bedroom wall in 1986.",
		"paint": Color(0.72, 0.02, 0.02), "finish": "gloss",
	},
	"ferrari_f40": {
		"name": "Ferrari F40", "maker": "Ferrari", "country": "IT", "year": 1987, "price": 1_350_000, "unlock": "shop",
		"blurb": "Enzo Ferrari's last car: a twin-turbo V8, a carbon-kevlar body you can see through the paint, no ABS, no traction control. A legend with a temper.",
		"paint": Color(0.72, 0.02, 0.02), "finish": "gloss",
	},
	"lambo_svj": {
		"name": "Lamborghini Aventador SVJ", "maker": "Lamborghini", "country": "IT", "year": 2019, "price": 520_000, "unlock": "shop",
		"blurb": "770 PS from a naturally aspirated V12 and active ALA aerodynamics that vector downforce corner by corner. It once owned the Nürburgring lap record.",
		"paint": Color(0.3, 0.08, 0.62), "finish": "pearl", "pearl": Color(0.12, 0.35, 0.9),
	},
	"jaguar_xj220": {
		"name": "Jaguar XJ220", "maker": "Jaguar", "country": "GB", "year": 1992, "price": 480_000, "unlock": "shop",
		"blurb": "Five metres of aluminium built by Jaguar's skunkworks, a twin-turbo V6 and 341 km/h: for a while the fastest production car in the world.",
		"paint": Color(0.1, 0.17, 0.33), "finish": "metallic",
	},
	"porsche_918": {
		"name": "Porsche 918 Spyder", "maker": "Porsche", "country": "DE", "year": 2015, "price": 1_600_000, "unlock": "shop",
		"blurb": "A 9,000 rpm racing V8 plus two electric motors: 887 PS, all-wheel drive and the first road car to lap the Nordschleife in under seven minutes.",
		"paint": Color(0.62, 0.04, 0.05), "finish": "metallic",
	},
	"ferrari_laferrari": {
		"name": "Ferrari LaFerrari", "maker": "Ferrari", "country": "IT", "year": 2014, "price": 1_500_000, "unlock": "championship",
		"blurb": "Ferrari's hybrid hypercar: a 6.3 V12 revving to 9,250 rpm, boosted by HY-KERS to 963 PS. Win the Riviera Grand Prix and it is yours.",
		"paint": Color(0.72, 0.02, 0.02), "finish": "gloss",
	},
}

## Old JDM roster keys (saves from before the European overhaul) -> nearest new car.
const LEGACY_KEYS := {
	"mame_k": "abarth_500", "hachi_gt": "bmw_m3_e30", "kyudo_type_s": "golf_gti", "sylph_s2": "bmw_m3_e30",
	"rotora_fd": "porsche_930", "tatsu_ix": "audi_quattro", "senko": "ferrari_testarossa", "titan_rz": "bmw_m4",
	"raijin_r": "porsche_992", "kaido_van": "defender_90", "mugen_proto": "porsche_918", "kurogane_hyper": "ferrari_laferrari",
}

const FINISHES := {
	"gloss": {"metallic": 0.0, "roughness": 0.18, "flake": 0.0, "pearl": 0.0, "coat": 1.0, "gloss": 0.95, "candy": 0.0},
	"metallic": {"metallic": 0.72, "roughness": 0.26, "flake": 0.35, "pearl": 0.0, "coat": 1.0, "gloss": 0.94, "candy": 0.0},
	"pearl": {"metallic": 0.40, "roughness": 0.24, "flake": 0.2, "pearl": 0.75, "coat": 1.0, "gloss": 0.94, "candy": 0.0},
	"matte": {"metallic": 0.0, "roughness": 0.80, "flake": 0.0, "pearl": 0.0, "coat": 0.0, "gloss": 0.15, "candy": 0.0},
	"satin": {"metallic": 0.25, "roughness": 0.44, "flake": 0.1, "pearl": 0.0, "coat": 0.35, "gloss": 0.50, "candy": 0.0},
	"chrome": {"metallic": 1.0, "roughness": 0.04, "flake": 0.0, "pearl": 0.0, "coat": 1.0, "gloss": 0.98, "candy": 0.0},
	"candy": {"metallic": 0.78, "roughness": 0.18, "flake": 0.25, "pearl": 0.20, "coat": 1.0, "gloss": 0.96, "candy": 0.85},
}

## Stock performance index (native test "benchmark PI table", rounded). Used to pick rivals for
## class-limited events without running the benchmark at race time.
const STOCK_PI := {
	"abarth_500": 593, "golf_gti": 633, "bmw_m3_e30": 533, "porsche_930": 561, "jaguar_etype": 551, "mb_300sl": 377,
	"defender_90": 224, "audi_quattro": 574, "jaguar_ftype": 792, "mb_g63": 663, "bmw_m4": 727, "audi_r8": 835,
	"porsche_992": 829, "ferrari_testarossa": 703, "ferrari_f40": 793, "lambo_svj": 853, "jaguar_xj220": 788,
	"porsche_918": 889, "ferrari_laferrari": 866,
}

static func keys() -> Array:
	return CARS.keys()

## Forza Horizon 4 performance bands.
static func pi_class(pi: int) -> int:
	if pi <= 500: return 0
	if pi <= 600: return 1
	if pi <= 700: return 2
	if pi <= 800: return 3
	if pi <= 900: return 4
	if pi <= 998: return 5
	return 6

const CLASS_NAMES := ["D", "C", "B", "A", "S1", "S2", "X"]
## Forza Horizon class badge colours.
const CLASS_COLORS := [Color("4bb6ef"), Color("ffd23f"), Color("ff8c2b"), Color("ff3b3b"), Color("b44bff"), Color("3a6cff"), Color("3de26b")]
const CLASS_MAX_PI := [500, 600, 700, 800, 900, 998, 999]

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

## Canonical key: maps legacy JDM keys from old saves onto the European roster.
static func resolve(key: String) -> String:
	if CARS.has(key):
		return key
	return LEGACY_KEYS.get(key, DEFAULT_KEY)

static func get_car(key: String) -> Dictionary:
	return CARS[resolve(key)]

static func model_path(key: String) -> String:
	var k := resolve(key)
	return "res://assets/cars/%s/%s.gltf" % [k, k]

static var _meta := {}

## Baked model metadata (wheels, lamps, exhausts, credit) from tools/carbake.
static func model_meta(key: String) -> Dictionary:
	var k := resolve(key)
	if not _meta.has(k):
		var f := FileAccess.open("res://assets/cars/%s/%s.json" % [k, k], FileAccess.READ)
		_meta[k] = JSON.parse_string(f.get_as_text()) if f else {}
	return _meta[k]
