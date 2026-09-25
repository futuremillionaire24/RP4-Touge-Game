class_name EventsScreen
extends MenuScreen
## Event browser (FH4 style): filter tabs across the top, a scrolling grid of event tiles on the
## left, the focused event's card on the right (conditions, class limit, rewards, rival, record,
## route map). A launches the event in the open world (the grid forms at the route start).
## Locked events show the festival level they need; over-class cars can't enter.

const FILTERS := ["All", "Road Racing", "Duels", "Time Attack", "Pursuits"]
const TYPE_TINT := {
	EventData.Type.CIRCUIT: Color(0.55, 0.12, 0.2), EventData.Type.SPRINT: Color(0.5, 0.2, 0.1),
	EventData.Type.TOUGE_BATTLE: Color(0.45, 0.25, 0.1), EventData.Type.WANGAN_DUEL: Color(0.12, 0.2, 0.45),
	EventData.Type.TIME_ATTACK: Color(0.15, 0.4, 0.3), EventData.Type.SHOWCASE: Color(0.6, 0.45, 0.08),
}

var _filter := 0
var _focus_id := ""
var _tabs: FestivalTabs
var _scroll: ScrollContainer
var _grid: UITileGrid
var _detail: VBoxContainer
var _route_card: RaceRouteCard

func _init(filter := 0, focus_id := "") -> void:
	super()
	_filter = filter
	_focus_id = focus_id

func build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_tabs = FestivalTabs.new(PackedStringArray(FILTERS))
	_tabs.position = Vector2(44, 14)
	_tabs.current = _filter
	add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(34, 84)
	_scroll.size = Vector2(690, 612)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.follow_focus = true
	add_child(_scroll)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 16)
	_scroll.add_child(pad)
	_grid = UITileGrid.new(Vector2(322, 150), 12.0)
	pad.add_child(_grid)
	var panel := PanelContainer.new()
	panel.position = Vector2(748, 84)
	panel.size = Vector2(546, 612)
	panel.custom_minimum_size = Vector2(546, 612)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 4)
	v.add_child(_detail)
	_route_card = RaceRouteCard.new()
	_route_card.custom_minimum_size = Vector2(514, 250)
	_route_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_route_card)
	set_hints([["A", "Start event"], ["LB", ""], ["RB", "Filter"], ["B", "Back"]])

func _matches(ev: Dictionary) -> bool:
	match _filter:
		1: return ev.type in [EventData.Type.CIRCUIT, EventData.Type.SPRINT] and not ev.has("police_heat")
		2: return ev.type in [EventData.Type.TOUGE_BATTLE, EventData.Type.WANGAN_DUEL]
		3: return ev.type == EventData.Type.TIME_ATTACK
		4: return ev.has("police_heat")
	return true

func refresh() -> void:
	_tabs.select(_filter, false)
	_grid.clear()
	var pi := int(Profile.current_car().get("pi", 500))
	var i := 0
	var focus_tile: UITile = null
	for ev in EventData.all():
		if not _matches(ev):
			continue
		var t := UITile.new(ev.name, "%s · %s" % [EventData.TYPE_NAMES[ev.type], ev.district], UIKit.art("events", ev.id))
		t.set_tint(TYPE_TINT.get(ev.type, Color(0.2, 0.22, 0.3)))
		var cm := int(ev.class_max)
		t.add_tag("%s class" % CarData.CLASS_NAMES[cm], CarData.CLASS_COLORS[cm])
		if ev.has("police_heat"):
			t.add_tag("Pursuit", Color(0.15, 0.3, 0.8))
		var rec: Dictionary = Profile.data.records.get(ev.id, {})
		var locked := int(ev.get("level", 0)) > int(Profile.data.level)
		if locked:
			t.set_locked(true, "Festival level %d" % int(ev.level))
		elif rec.has("best_pos") and int(rec.best_pos) == 1:
			t.set_info("WON ★", UIKit.AMBER)
		elif rec.has("best_pos"):
			t.set_info("BEST P%d" % int(rec.best_pos))
		else:
			t.add_tag("New", Color.WHITE)
		if CarData.pi_class(pi) > cm and not locked:
			t.set_info("CAR OVER CLASS", UIKit.RED)
		t.on_focus = _show_detail.bind(ev)
		t.on_accept = _start.bind(ev, locked, CarData.pi_class(pi) > cm)
		_grid.add_tile(t, i % 2, i / 2)
		if ev.id == _focus_id:
			focus_tile = t
		i += 1
	_grid.link_focus()
	var target: UITile = focus_tile if focus_tile else _grid.first()
	if target and is_inside_tree():
		target.call_deferred("grab_focus")
	_focus_id = ""

func focus_default() -> void:
	if _grid.first():
		_grid.first().grab_focus()

func tab(dir: int) -> void:
	_tabs.step(dir)
	_filter = _tabs.current
	refresh()

func _show_detail(ev: Dictionary) -> void:
	for c in _detail.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	head.add_child(UIKit.tag(EventData.TYPE_NAMES[ev.type], TYPE_TINT.get(ev.type, UIKit.ACCENT).lightened(0.15)))
	head.add_child(UIKit.tag("%s class · PI %d" % [CarData.CLASS_NAMES[int(ev.class_max)], CarData.CLASS_MAX_PI[int(ev.class_max)]], CarData.CLASS_COLORS[int(ev.class_max)]))
	_detail.add_child(head)
	var title := UIKit.label(ev.name.to_upper(), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, "heavy")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(514, 0)
	_detail.add_child(title)
	_detail.add_child(UIKit.label(String(ev.district).to_upper(), 19, UIKit.DIM))
	var hh := int(ev.time)
	var laps := int(ev.get("laps", 1))
	var km := EventData.length_of(ev.id) * (laps if bool(ev.closed) else 1) / 1000.0
	var facts := [
		["TIME", "%02d:%02d" % [hh, int((float(ev.time) - hh) * 60.0)]],
		["WEATHER", SkyWeather.W_NAMES[int(ev.weather)]],
		["DISTANCE", "%.1f KM%s" % [km, ("  ·  %d LAPS" % laps) if bool(ev.closed) else ""]],
		["FIELD", ("%d RIVALS" % int(ev.rivals)) if int(ev.rivals) > 0 else "SOLO"],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 0)
	for f in facts:
		grid.add_child(UIKit.label(f[0], 17, UIKit.DIM))
		grid.add_child(UIKit.label(String(f[1]).to_upper(), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	_detail.add_child(grid)
	var reward := HBoxContainer.new()
	reward.add_child(UIKit.label(UIKit.money(int(ev.credits)), 24, UIKit.GREEN, HORIZONTAL_ALIGNMENT_LEFT, "heavy"))
	reward.add_child(UIKit.label("+%d XP" % int(ev.xp), 24, UIKit.AMBER, HORIZONTAL_ALIGNMENT_LEFT, "heavy"))
	if ev.has("reward_car"):
		reward.add_child(UIKit.label("+ " + String(CarData.get_car(ev.reward_car).get("name", "")).to_upper(), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	_detail.add_child(reward)
	var rec: Dictionary = Profile.data.records.get(ev.id, {})
	if not rec.is_empty():
		_detail.add_child(UIKit.label("BEST  P%d  ·  %s" % [int(rec.best_pos), UIKit.time_str(float(rec.best_time))], 18, UIKit.CYAN))
	if ev.has("rival"):
		var r := RivalData.get_rival(ev.rival)
		if not r.is_empty():
			_detail.add_child(UIKit.label("RIVAL  %s \"%s\"  ·  %s" % [String(r.name).to_upper(), String(r.title).to_upper(), String(CarData.get_car(r.car).name).to_upper()], 18, UIKit.ACCENT.lightened(0.3)))
	var pi := int(Profile.current_car().get("pi", 500))
	if CarData.pi_class(pi) > int(ev.class_max):
		_detail.add_child(UIKit.label("YOUR CAR IS %s — CHOOSE CLASS %s OR LOWER" % [CarData.class_label(pi), CarData.CLASS_NAMES[int(ev.class_max)]], 17, UIKit.RED))
	if _route_card:
		_route_card.set_event_id(ev.id)

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
