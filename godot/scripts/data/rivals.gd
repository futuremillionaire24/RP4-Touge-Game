class_name RivalData
extends RefCounted
## Named rivals for the story ladder: car, livery colour, driving personality, dialogue.

const RIVALS := {
	"takumi": {"name": "Marc D.", "title": "Master of the Corniche", "car": "bmw_m3_e30", "color": Color(0.95, 0.95, 0.93),
		"personality": {"skill": 0.99, "aggression": 0.35, "consistency": 0.97, "mistake_rate": 0.004, "patience": 0.9, "drift_style": true},
		"intro": "They say nobody carries more momentum down the Grande Corniche switchbacks. Let's see your line.",
		"win": "...You took that last hairpin like a seasoned rally ace.", "lose": "Too cautious on the descent. Come back when you can flow."},
	"keisuke": {"name": "Klaus W.", "title": "Alpine Apex", "car": "porsche_930", "color": Color(0.8, 0.05, 0.05),
		"personality": {"skill": 0.97, "aggression": 0.75, "consistency": 0.9, "mistake_rate": 0.01, "patience": 0.3, "drift_style": true},
		"intro": "The alpine climb demands precision and unyielding throttle. Do you have what it takes?", "win": "Superb balance. The mountain belongs to you today.", "lose": "Hesitation kills momentum on the incline."},
	"blackbird": {"name": "Laurent M.", "title": "Autoroute Ghost", "car": "bmw_m4", "color": Color(0.03, 0.03, 0.035),
		"personality": {"skill": 0.98, "aggression": 0.6, "consistency": 0.95, "mistake_rate": 0.005, "patience": 0.5, "drift_style": false},
		"intro": "The A8 autoroute doesn't care about excuses. Only who blinks first past 300 km/h.", "win": "You stayed flat through the viaducts. Total respect.", "lose": "Lifted before the tunnel. The autoroute showed no mercy."},
	"mika": {"name": "Camille R.", "title": "Monte-Carlo Queen", "car": "golf_gti", "color": Color(1.0, 0.85, 0.1),
		"personality": {"skill": 0.95, "aggression": 0.85, "consistency": 0.85, "mistake_rate": 0.015, "patience": 0.2, "drift_style": false},
		"intro": "These Monaco streets are mine after dark. Let's see if you can hold the racing line.", "win": "Impressive precision around the harbour chicane.", "lose": "Braked too early for Saint-Dévote. You weren't ready."},
	"goro": {"name": "Antoine V.", "title": "Port Hercule Boss", "car": "mb_g63", "color": Color(0.9, 0.9, 0.88),
		"personality": {"skill": 0.93, "aggression": 0.95, "consistency": 0.7, "mistake_rate": 0.03, "patience": 0.1, "drift_style": true},
		"intro": "Custom tuned chassis, stripped interior and no fear along the quayside.", "win": "Incredible car control around the tight marina corners.", "lose": "Left behind at the quay."},
	"yuna": {"name": "Elena V.", "title": "Riviera Rally Specialist", "car": "audi_quattro", "color": Color(0.1, 0.3, 0.7),
		"personality": {"skill": 0.96, "aggression": 0.5, "consistency": 0.92, "mistake_rate": 0.008, "patience": 0.6, "drift_style": false},
		"intro": "Cobbles, asphalt and mountain spray. The all-wheel drive eats it all up.", "win": "World-class car control. Pure European racing finesse.", "lose": "Four-wheel drive and four seconds clear."},
	"champion": {"name": "Sebastien R.", "title": "Festival Champion", "car": "ferrari_laferrari", "color": Color(0.92, 0.68, 0.12),
		"personality": {"skill": 0.99, "aggression": 0.8, "consistency": 0.98, "mistake_rate": 0.002, "patience": 0.7, "drift_style": false},
		"intro": "You have conquered every pass across the Riviera. Now face the pinnacle of the Euro GT Festival.",
		"win": "Magnificent! The Festival Crown is yours, along with the hypercar.", "lose": "A thousand horsepower demands absolute mastery."},
}

static func get_rival(id: String) -> Dictionary:
	return RIVALS.get(id, {})
