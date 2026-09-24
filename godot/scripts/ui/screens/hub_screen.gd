class_name HubScreen
extends MenuScreen
## Festival hub (Daikoku PA): drive, events, garage, dealership, Omikuji, records, settings.
## The current car sits on the stage with its stats card.

var _stats: CarStatsPanel
var _car_row: UIRow
var _omikuji_row: UIRow
var _events_row: UIRow

func build() -> void:
	if festival != null:
		festival.set_top_bar_visible(true)
	var col := make_column(520)
	col.add_child(UIKit.header("Festival", "祭", "Daikoku Parking Area  ·  festival hub"))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 10)
	col.add_child(sp)
	var drive := UIRow.new("FREE ROAM", "JAPAN ▶")
	drive.on_accept = func(): festival.drive()
	col.add_child(drive)
	_events_row = UIRow.new("EVENTS")
	_events_row.on_accept = func(): festival.push(EventsScreen.new())
	col.add_child(_events_row)
	_car_row = UIRow.new("GARAGE")
	_car_row.on_accept = func(): festival.push(GarageScreen.new())
	col.add_child(_car_row)
	var dealer := UIRow.new("DEALERSHIP", "%d cars" % CarData.keys().size())
	dealer.on_accept = func(): festival.push(DealerScreen.new())
	col.add_child(dealer)
	_omikuji_row = UIRow.new("OMIKUJI  御神籤")
	_omikuji_row.on_accept = func(): festival.push(OmikujiScreen.new())
	col.add_child(_omikuji_row)
	var rec := UIRow.new("RECORDS & STATS")
	rec.on_accept = func(): festival.push(RecordsScreen.new())
	col.add_child(rec)
	var set_row := UIRow.new("SETTINGS")
	set_row.on_accept = func(): festival.push(SettingsScreen.new())
	col.add_child(set_row)
	var title := UIRow.new("TITLE SCREEN")
	title.on_accept = func(): festival.reset_to(TitleScreen.new())
	col.add_child(title)
	_stats = CarStatsPanel.new()
	_stats.position = Vector2(870, 470)
	add_child(_stats)
	set_hints([["A", "Select"], ["RS", "Look around"]])

func refresh() -> void:
	var e := Profile.current_car()
	if e.is_empty():
		return
	stage.show_entry(e)
	_stats.show_build(e.key, Profile.overrides_for(e))
	_car_row.set_value("%s  %s" % [CarData.get_car(e.key).name, CarData.class_label(int(e.get("pi", 0)))])
	var draws := int(Profile.data.omikuji)
	_omikuji_row.set_value("%d draw%s" % [draws, "" if draws == 1 else "s"], UIKit.AMBER if draws > 0 else UIKit.DIM)
	var done := 0
	var all := EventData.all()
	for ev in all:
		if Profile.data.records.has(ev.id):
			done += 1
	_events_row.set_value("%d / %d" % [done, all.size()])

func back() -> void:
	festival.reset_to(TitleScreen.new())
