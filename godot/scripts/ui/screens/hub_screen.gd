class_name HubScreen
extends MenuScreen
## Festival hub, Forza Horizon 4 layout: LB/RB page tabs across the top (Campaign, Cars, My
## Festival, Options), each page a grid of image tiles; the current car stands on the plaza to the
## right with its stats card.

const PAGES := ["Campaign", "Cars", "My Festival", "Options"]
const CELL := Vector2(196, 128)

var _tabs: FestivalTabs
var _grid: UITileGrid
var _stats: CarStatsPanel
var _page := 0
static var _last_page := 0

func build() -> void:
	if festival != null:
		festival.set_top_bar_visible(true)
	_tabs = FestivalTabs.new(PackedStringArray(PAGES))
	_tabs.position = Vector2(44, 14)
	add_child(_tabs)
	_grid = UITileGrid.new(CELL, 12.0)
	_grid.position = Vector2(44, 92)
	add_child(_grid)
	_stats = CarStatsPanel.new()
	_stats.position = Vector2(870, 470)
	add_child(_stats)
	set_hints([["A", "Select"], ["LB", ""], ["RB", "Page"], ["RS", "Look around"], ["B", "Title"]])
	_page = _last_page

func refresh() -> void:
	var e := Profile.current_car()
	if not e.is_empty():
		stage.show_entry(e)
		_stats.show_build(e.key, Profile.overrides_for(e))
	_tabs.current = _page
	_tabs.select(_page, false)
	_build_page()

func tab(dir: int) -> void:
	_tabs.step(dir)
	_page = _tabs.current
	_last_page = _page
	_build_page()
	UIKit.fade_in(_grid, 16.0)
	_focus_first()

func focus_default() -> void:
	_focus_first()

func _focus_first() -> void:
	await get_tree().process_frame
	if _grid.first() and is_inside_tree():
		_grid.first().grab_focus()

func back() -> void:
	festival.reset_to(TitleScreen.new())

func _tile(title: String, sub: String, art: String, tint: Color, col: int, row: int, cols: int, rows: int, accept: Callable) -> UITile:
	var t := UITile.new(title, sub, UIKit.art("tiles", art))
	t.set_tint(tint)
	t.on_accept = accept
	_grid.add_tile(t, col, row, cols, rows)
	return t

func _build_page() -> void:
	_grid.clear()
	match _page:
		0: _campaign()
		1: _cars()
		2: _my_festival()
		3: _options()
	_grid.link_focus()

# ---- Pages ------------------------------------------------------------------------------------

func _events_done(types: Array) -> Array:
	var done := 0
	var total := 0
	for ev in EventData.all():
		if not types.is_empty() and not types.has(ev.type):
			continue
		total += 1
		var rec: Dictionary = Profile.data.records.get(ev.id, {})
		if rec.has("best_pos") and int(rec.best_pos) == 1:
			done += 1
	return [done, total]

func _campaign() -> void:
	var fr := _tile("Free Roam", "Monaco · the Corniches · La Turbie", "free_roam", Color(0.1, 0.35, 0.55), 0, 0, 2, 2, func(): festival.drive())
	fr.add_tag("Riviera open world")
	var races := [EventData.Type.CIRCUIT, EventData.Type.SPRINT]
	var d := _events_done(races)
	_tile("Road Racing", "Circuits & coastal sprints", "road_racing", Color(0.55, 0.12, 0.2), 2, 0, 2, 1,
		func(): festival.push(EventsScreen.new(1))).set_info("%d / %d" % d).add_tag("Championship")
	d = _events_done([EventData.Type.TOUGE_BATTLE, EventData.Type.WANGAN_DUEL])
	_tile("Rival Duels", "Head to head", "rival_duels", Color(0.45, 0.25, 0.1), 2, 1, 1, 1,
		func(): festival.push(EventsScreen.new(2))).set_info("%d / %d" % d)
	d = _events_done([EventData.Type.TIME_ATTACK])
	_tile("Time Attack", "Mont Agel", "time_attack", Color(0.15, 0.4, 0.3), 3, 1, 1, 1,
		func(): festival.push(EventsScreen.new(3))).set_info("%d / %d" % d)
	var gp := EventData.get_event("festival_grand_prix")
	var gp_tile := _tile("Festival Grand Prix", "Monte-Carlo · finale", "grand_prix", Color(0.6, 0.45, 0.08), 0, 2, 2, 2,
		func(): festival.push(EventsScreen.new(0, "festival_grand_prix")))
	gp_tile.add_tag("Finale", UIKit.AMBER)
	if not gp.is_empty():
		gp_tile.set_info("PRIZE: %s" % CarData.get_car(String(gp.get("reward_car", ""))).get("name", "").to_upper())
		if int(gp.get("level", 0)) > int(Profile.data.level):
			gp_tile.set_locked(true, "Festival level %d" % int(gp.level))
	_tile("All Events", "%d on the Riviera" % EventData.all().size(), "all_events", Color(0.2, 0.2, 0.28), 2, 2, 1, 1,
		func(): festival.push(EventsScreen.new(0)))
	var pursuits := EventData.all().filter(func(ev): return ev.has("police_heat")).size()
	_tile("Pursuits", "Gendarmerie", "pursuits", Color(0.1, 0.18, 0.5), 3, 2, 1, 1,
		func(): festival.push(EventsScreen.new(4))).set_info("%d" % pursuits)
	var lv := int(Profile.data.level)
	var prog := _tile("Festival Level %d" % lv, "%d / %d XP" % [int(Profile.data.xp), Profile.xp_for_level(lv)], "progress", Color(0.35, 0.1, 0.4), 2, 3, 2, 1,
		func(): festival.push(RecordsScreen.new()))
	var all := _events_done([])
	prog.set_info("%d / %d WON" % all)

func _cars() -> void:
	var e := Profile.current_car()
	var key: String = e.get("key", CarData.DEFAULT_KEY)
	var car := CarData.get_car(key)
	var g := _tile("My Garage", String(car.get("name", "")), "", Color(0.18, 0.2, 0.26), 0, 0, 2, 2,
		func(): festival.push(GarageScreen.new()))
	g.set_image(UIKit.art("cars", key))
	g.set_badge(UIKit.class_badge(int(e.get("pi", 500)), 18))
	g.set_info("%d CARS" % Profile.data.garage.size())
	_tile("Autoshow", "%d European cars" % CarData.keys().size(), "autoshow", Color(0.5, 0.1, 0.12), 2, 0, 2, 1,
		func(): festival.push(DealerScreen.new())).add_tag("Buy")
	var idx := Profile.current_index()
	_tile("Upgrades", "Engine · chassis · tyres", "upgrades", Color(0.3, 0.3, 0.35), 2, 1, 1, 1,
		func(): festival.push(UpgradeScreen.new(idx)))
	_tile("Tuning", "Gearing · suspension · aero", "tuning", Color(0.18, 0.3, 0.38), 3, 1, 1, 1,
		func(): festival.push(TuningScreen.new(idx)))
	_tile("Paint & Livery", "Colour · finish", "paint", Color(0.55, 0.3, 0.08), 0, 2, 2, 1,
		func(): festival.push(PaintScreen.new(idx)))
	_tile("Test Drive", "Take it onto the Riviera", "free_roam", Color(0.1, 0.35, 0.55), 2, 2, 2, 1, func(): festival.drive())

func _my_festival() -> void:
	var spins := int(Profile.data.omikuji)
	var ws := _tile("Wheelspin", "Cars · credits · prizes", "wheelspin", Color(0.6, 0.08, 0.4), 0, 0, 2, 2,
		func(): festival.push(OmikujiScreen.new()))
	ws.set_info("%d SPIN%s" % [spins, "" if spins == 1 else "S"], UIKit.AMBER if spins > 0 else Color.WHITE)
	if spins > 0:
		ws.add_tag("Ready", UIKit.AMBER)
	_tile("Records & Stats", "Best results · distance · wins", "records", Color(0.15, 0.25, 0.35), 2, 0, 2, 1,
		func(): festival.push(RecordsScreen.new()))
	_tile("Credits", "Cars, maps & artists", "credits", Color(0.22, 0.22, 0.25), 2, 1, 1, 1,
		func(): festival.push(CreditsScreen.new()))
	_tile(UIKit.money(int(Profile.data.credits)), "Bank", "bank", Color(0.1, 0.35, 0.2), 3, 1, 1, 1, Callable())

func _options() -> void:
	_tile("Settings", "Graphics · audio · gameplay", "settings", Color(0.2, 0.22, 0.28), 0, 0, 2, 1,
		func(): festival.push(SettingsScreen.new()))
	_tile("Controls", "Gamepad & touch", "controls", Color(0.2, 0.25, 0.22), 2, 0, 2, 1,
		func(): festival.push(ControllerScreen.new()))
	_tile("Title Screen", "", "title", Color(0.15, 0.15, 0.18), 0, 1, 1, 1, func(): festival.reset_to(TitleScreen.new()))
	_tile("Quit", "Save and exit", "quit", Color(0.35, 0.1, 0.1), 1, 1, 1, 1, func():
		Profile.save()
		get_tree().quit())
