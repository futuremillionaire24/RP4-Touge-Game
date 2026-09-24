class_name StarterScreen
extends MenuScreen
## Onboarding: pick one of three starter cars (free). Each row previews the car on the stage
## with its stats card and blurb.

var _stats: CarStatsPanel
var _blurb: Label

func build() -> void:
	var col := make_column(520)
	col.add_child(UIKit.header("Choose your first car", "始", "Welcome to the Neon Touge Festival. Your first ride is on us."))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	col.add_child(spacer)
	for key in Profile.STARTERS:
		var car := CarData.get_car(key)
		var row := UIRow.new(car.name, CarData.class_label(int(CarData.STOCK_PI[key])))
		row.set_sub("%s %d" % [car.maker, int(car.year)])
		row.on_focus = _preview.bind(key)
		row.on_accept = _confirm.bind(key)
		col.add_child(row)
	_blurb = UIKit.label("", 19, UIKit.TEXT)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(500, 0)
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 16)
	col.add_child(sp2)
	col.add_child(_blurb)
	_stats = CarStatsPanel.new()
	_stats.position = Vector2(870, 470)
	add_child(_stats)
	set_hints([["A", "Choose"], ["RS", "Look around"]])

func _preview(key: String) -> void:
	stage.show_key(key)
	_stats.show_build(key, {})
	_blurb.text = CarData.get_car(key).blurb

func _confirm(key: String) -> void:
	var car := CarData.get_car(key)
	festival.choose("Take the %s?" % car.name, car.blurb, [
		["YES — LET'S DRIVE", func():
			Profile.choose_starter(key)
			festival.toast("%s ADDED TO YOUR GARAGE" % car.name.to_upper())
			festival.reset_to(HubScreen.new())],
		["KEEP LOOKING", Callable()],
	])

func back() -> void:
	festival.reset_to(TitleScreen.new())
