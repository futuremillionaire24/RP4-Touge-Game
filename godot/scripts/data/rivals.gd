class_name RivalData
extends RefCounted
## Named rivals for the story ladder: car, livery colour, driving personality, dialogue.

const RIVALS := {
	"takumi": {"name": "Takumi F.", "title": "Ghost of Akina", "car": "hachi_gt", "color": Color(0.95, 0.95, 0.93),
		"personality": {"skill": 0.99, "aggression": 0.35, "consistency": 0.97, "mistake_rate": 0.004, "patience": 0.9, "drift_style": true},
		"intro": "They say nobody's passed the white hatchback on the downhill in ten years. Tonight you find out why.",
		"win": "...You drove that last hairpin like you've known it forever.", "lose": "The tofu's still warm. Come back when you can keep up."},
	"keisuke": {"name": "Keisuke T.", "title": "Red Comet", "car": "rotora_fd", "color": Color(0.8, 0.05, 0.05),
		"personality": {"skill": 0.97, "aggression": 0.75, "consistency": 0.9, "mistake_rate": 0.01, "patience": 0.3, "drift_style": true},
		"intro": "Uphill is about power and patience. I have both. Do you?", "win": "Tch. Next time the rotary won't be so forgiving.", "lose": "Uphill belongs to the rotary."},
	"blackbird": {"name": "Tatsuya S.", "title": "Blackbird", "car": "titan_rz", "color": Color(0.03, 0.03, 0.035),
		"personality": {"skill": 0.98, "aggression": 0.6, "consistency": 0.95, "mistake_rate": 0.005, "patience": 0.5, "drift_style": false},
		"intro": "The Wangan doesn't care about lap times. Only who blinks first at 300.", "win": "You didn't lift. Respect.", "lose": "Too early on the brakes. The Wangan saw it."},
	"mika": {"name": "Mika R.", "title": "Queen of Shibuya", "car": "kyudo_type_s", "color": Color(1.0, 0.85, 0.1),
		"personality": {"skill": 0.95, "aggression": 0.85, "consistency": 0.85, "mistake_rate": 0.015, "patience": 0.2, "drift_style": false},
		"intro": "These streets are mine after midnight. Try to keep up through the scramble.", "win": "Okay. The city's big enough for two.", "lose": "Rain, neon and nine thousand rpm. You weren't ready."},
	"goro": {"name": "Goro K.", "title": "Dock Boss", "car": "kaido_van", "color": Color(0.9, 0.9, 0.88),
		"personality": {"skill": 0.93, "aggression": 0.95, "consistency": 0.7, "mistake_rate": 0.03, "patience": 0.1, "drift_style": true},
		"intro": "It's a delivery van. It also has a welded diff and no fear.", "win": "Hah! Nobody beats the van... except you, apparently.", "lose": "Delivered."},
	"yuna": {"name": "Yuna S.", "title": "Satoyama Rally", "car": "tatsu_ix", "color": Color(0.1, 0.3, 0.7),
		"personality": {"skill": 0.96, "aggression": 0.5, "consistency": 0.92, "mistake_rate": 0.008, "patience": 0.6, "drift_style": false},
		"intro": "Dirt, fog and paddy water. The Tatsu eats all of it.", "win": "Nice car control. Gravel respects that.", "lose": "Four-wheel drive, four seconds ahead."},
	"champion": {"name": "Akira K.", "title": "Touge King", "car": "kurogane_hyper", "color": Color(0.92, 0.68, 0.12),
		"personality": {"skill": 0.99, "aggression": 0.8, "consistency": 0.98, "mistake_rate": 0.002, "patience": 0.7, "drift_style": false},
		"intro": "You've beaten every legend in Japan. But the Kurogane is on another plane entirely.",
		"win": "Incredible. The crown is yours, and so is the hypercar.", "lose": "A thousand horsepower doesn't bend to anyone."},
}

static func get_rival(id: String) -> Dictionary:
	return RIVALS.get(id, {})
