class_name EventsScreen
extends MenuScreen
## Event browser: every festival event with type, district, class limit, rewards and your
## record. Tabs filter by type group. A launches the event in the open world (the grid forms at
## the route start). Locked events show the festival level they need; over-class cars can't enter.

const TABS := [["All", []], ["Races", [EventData.Type.CIRCUIT, EventData.Type.SPRINT]],
	["Touge", [EventData.Type.TOUGE_BATTLE, EventData.Type.TIME_ATTACK]], ["Duels", [EventData.Type.WANGAN_DUEL]]]

var _tab := 0
var _tabs: HBoxContainer
var _list: VBoxContainer
var _detail: PanelContainer
var _detail_box: VBoxContainer
var _route_card: RaceRouteCard

func build() -> void:
	var col := make_column(560)
	col.add_child(UIKit.header("Festival Events", "", "Compete across Europe. Win to earn credits, XP, and trophies."))
	_tabs = make_tabs(col, TABS.map(func(t): return t[0]))
	_list = make_list(col, 470)
	
	_detail = PanelContainer.new()
	_detail.position = Vector2(620, 80)
	_detail.custom_minimum_size = Vector2(670, 620)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.88)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.91, 0.64, 0.09, 0.5)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 18
	sb.content_margin_top = 14
	sb.content_margin_right = 18
	sb.content_margin_bottom = 14
	_detail.add_theme_stylebox_override("panel", sb)
	add_child(_detail)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_detail.add_child(vb)

	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 4)
	vb.add_child(_detail_box)

	_route_card = RaceRouteCard.new()
	_route_card.custom_minimum_size = Vector2(634, 250)
	vb.add_child(_route_card)

	set_hints([["A", "Start event"], ["L1", ""], ["R1", "Filter"], ["B", "Back"]])

func refresh() -> void:
	highlight_tabs(_tabs, _tab)
	for c in _list.get_children():
		c.queue_free()
	var e := Profile.current_car()
	var pi := int(e.get("pi", 500))
	var first: UIRow = null
	for ev in EventData.all():
		var types: Array = TABS[_tab][1]
		if not types.is_empty() and not types.has(ev.type):
			continue
		var row := UIRow.new(ev.name)
		var rec: Dictionary = Profile.data.records.get(ev.id, {})
		var locked := int(ev.get("level", 0)) > int(Profile.data.level)
		var over := CarData.pi_class(pi) > int(ev.class_max)
		if locked:
			row.set_value("LV %d" % int(ev.level), UIKit.DIM)
		elif rec.has("best_pos") and int(rec.best_pos) == 1:
			row.set_value("WON ★", UIKit.AMBER)
		elif rec.has("best_pos"):
			row.set_value("P%d" % int(rec.best_pos), UIKit.CYAN)
		else:
			row.set_value("NEW", UIKit.GREEN)
		row.set_sub(("%s ≤%s" % [EventData.TYPE_NAMES[ev.type], CarData.CLASS_NAMES[int(ev.class_max)]]), UIKit.RED if over else UIKit.DIM)
		row.on_focus = _show_detail.bind(ev)
		row.on_accept = _start.bind(ev, locked, over)
		_list.add_child(row)
		if first == null:
			first = row
	if first and is_inside_tree():
		first.call_deferred("grab_focus")

func tab(dir: int) -> void:
	_tab = wrapi(_tab + dir, 0, TABS.size())
	refresh()

func _show_detail(ev: Dictionary) -> void:
	for c in _detail_box.get_children():
		c.queue_free()
	_detail_box.add_child(UIKit.label(ev.name.to_upper(), 24, Color.WHITE))
	_detail_box.add_child(UIKit.label("%s  ·  %s" % [EventData.TYPE_NAMES[ev.type], ev.district], 16, UIKit.CYAN))
	
	var hh := int(ev.time)
	var cond := "%02d:%02d  ·  %s" % [hh, int((float(ev.time) - hh) * 60.0), SkyWeather.W_NAMES[int(ev.weather)]]
	var laps := int(ev.get("laps", 1))
	var length_m := _route_length(ev)
	var rivals_str := "%d rivals" % int(ev.rivals) if int(ev.rivals) > 0 else "Solo vs clock"
	var laps_str := ("  ·  %d laps" % laps) if bool(ev.closed) else ""
	var class_str := "%s (PI ≤ %d)" % [CarData.CLASS_NAMES[int(ev.class_max)], CarData.CLASS_MAX_PI[int(ev.class_max)]]
	
	var sub_info := "%s  ·  %s%s  ·  Class %s" % [cond, rivals_str, laps_str, class_str]
	_detail_box.add_child(UIKit.label(sub_info, 15, UIKit.TEXT))
	
	var rec: Dictionary = Profile.data.records.get(ev.id, {})
	var rec_str := ""
	if not rec.is_empty():
		rec_str = "   ·   Best: P%d (%s)" % [int(rec.best_pos), UIKit.time_str(float(rec.best_time))]
	_detail_box.add_child(UIKit.label("Reward: %s  ·  %d XP%s" % [UIKit.money(int(ev.credits)), int(ev.xp), rec_str], 15, UIKit.GREEN))

	if ev.has("rival"):
		var r := RivalData.get_rival(ev.rival)
		if not r.is_empty():
			_detail_box.add_child(UIKit.label("Rival: %s \"%s\" — %s" % [r.name, r.title, CarData.get_car(r.car).name], 15, UIKit.NEON))

	var pi := int(Profile.current_car().get("pi", 500))
	if CarData.pi_class(pi) > int(ev.class_max):
		var warn := UIKit.label("⚠ Your car is %s — select class %s or lower." % [CarData.class_label(pi), CarData.CLASS_NAMES[int(ev.class_max)]], 15, UIKit.RED)
		_detail_box.add_child(warn)

	if _route_card:
		_route_card.set_event_id(ev.id)

func _route_length(ev: Dictionary) -> float:
	# Measured from the generated world by tools/event_lengths.gd (world seed 1).
	return EventData.length_of(ev.id) * (int(ev.get("laps", 1)) if bool(ev.closed) else 1)

func _start(ev: Dictionary, locked: bool, over: bool) -> void:
	if locked:
		festival.toast("REACH FESTIVAL LEVEL %d TO UNLOCK" % int(ev.level))
		return
	if over:
		festival.choose("Car over class limit", "This event is class %s or lower. Pick another car or remove upgrades in the Garage." % CarData.CLASS_NAMES[int(ev.class_max)], [
			["OPEN GARAGE", func(): festival.push(GarageScreen.new())],
			["BACK", Callable()],
		])
		return
	festival.drive({"event": ev.id})

