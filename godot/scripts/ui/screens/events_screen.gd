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

func build() -> void:
	var col := make_column(560)
	col.add_child(UIKit.header("Events", "競", "Race the festival. Win to earn credits, XP and rival respect."))
	_tabs = make_tabs(col, TABS.map(func(t): return t[0]))
	_list = make_list(col, 470)
	_detail = PanelContainer.new()
	_detail.position = Vector2(700, 90)
	_detail.custom_minimum_size = Vector2(590, 0)
	add_child(_detail)
	_detail_box = VBoxContainer.new()
	_detail.add_child(_detail_box)
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
	_detail_box.add_child(UIKit.label(ev.name.to_upper(), 26, Color.WHITE))
	_detail_box.add_child(UIKit.label("%s  ·  %s" % [EventData.TYPE_NAMES[ev.type], ev.district], 18, UIKit.CYAN))
	var hh := int(ev.time)
	var cond := "%02d:%02d  ·  %s" % [hh, int((float(ev.time) - hh) * 60.0), SkyWeather.W_NAMES[int(ev.weather)]]
	_detail_box.add_child(UIKit.label(cond, 18, UIKit.DIM))
	var laps := int(ev.get("laps", 1))
	var length_m := _route_length(ev)
	var info := "%s  ·  %.1f km%s" % ["%d rivals" % int(ev.rivals) if int(ev.rivals) > 0 else "Solo vs clock",
		length_m / 1000.0, ("  ·  %d laps" % laps) if bool(ev.closed) else ""]
	_detail_box.add_child(UIKit.label(info, 18, UIKit.TEXT))
	var cls := UIKit.label("Class limit: %s (PI ≤ %d)" % [CarData.CLASS_NAMES[int(ev.class_max)], CarData.CLASS_MAX_PI[int(ev.class_max)]], 18, UIKit.TEXT)
	_detail_box.add_child(cls)
	_detail_box.add_child(UIKit.label("Reward: %s  ·  %d XP" % [UIKit.money(int(ev.credits)), int(ev.xp)], 18, UIKit.GREEN))
	if ev.has("rival"):
		var r := RivalData.get_rival(ev.rival)
		if not r.is_empty():
			_detail_box.add_child(UIKit.label("Rival: %s \"%s\" — %s" % [r.name, r.title, CarData.get_car(r.car).name], 18, UIKit.NEON))
			var intro := UIKit.label("“%s”" % r.intro, 17, UIKit.DIM)
			intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			intro.custom_minimum_size = Vector2(556, 0)
			_detail_box.add_child(intro)
	var rec: Dictionary = Profile.data.records.get(ev.id, {})
	if not rec.is_empty():
		_detail_box.add_child(UIKit.label("Best: P%d  ·  %s  ·  %d win%s" % [int(rec.best_pos), UIKit.time_str(float(rec.best_time)), int(rec.wins), "" if int(rec.wins) == 1 else "s"], 18, UIKit.AMBER))
	var pi := int(Profile.current_car().get("pi", 500))
	if CarData.pi_class(pi) > int(ev.class_max):
		var warn := UIKit.label("Your car is %s — choose a car in class %s or lower in the Garage." % [CarData.class_label(pi), CarData.CLASS_NAMES[int(ev.class_max)]], 18, UIKit.RED)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size = Vector2(556, 0)
		_detail_box.add_child(warn)

func _route_length(ev: Dictionary) -> float:
	# Measured from the generated world by tools/event_lengths.gd (world seed 1).
	return float(EventData.LENGTHS.get(ev.id, 0.0)) * (int(ev.get("laps", 1)) if bool(ev.closed) else 1)

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

