class_name StarterScreen
extends MenuScreen
## Choose the first festival car from a photo-led European starter grid.

var _stats: CarStatsPanel
var _blurb: Label
var _grid: UITileGrid

func build() -> void:
	var col := make_column(760)
	col.add_child(UIKit.header("Choose your first car", "", "Welcome to the Euro GT Festival. Your first ride is on us."))
	_grid = UITileGrid.new(Vector2(232, 210), 12)
	_grid.position = Vector2(44, 150)
	_grid.size = Vector2(720, 220)
	add_child(_grid)
	for i in range(Profile.STARTERS.size()):
		var key: String = Profile.STARTERS[i]
		var car := CarData.get_car(key)
		var tile := UITile.new(car.name, "%s  %d" % [car.maker, int(car.year)], UIKit.art("cars", key))
		tile.set_tint(Color.from_hsv(float(i) / 3.0, 0.55, 0.62))
		tile.set_badge(UIKit.class_badge(int(CarData.STOCK_PI[key]), 18))
		tile.on_focus = _preview.bind(key)
		tile.on_accept = _confirm.bind(key)
		_grid.add_tile(tile, i, 0)
	_grid.link_focus()
	_blurb = UIKit.label("", 19, UIKit.TEXT)
	_blurb.position = Vector2(52, 390)
	_blurb.size = Vector2(730, 110)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_blurb)
	_stats = CarStatsPanel.new()
	_stats.position = Vector2(870, 470)
	add_child(_stats)
	set_hints([["A", "Choose car"], ["RS", "Look around"]])

func _preview(key: String) -> void:
	stage.show_key(key)
	_stats.show_build(key, {})
	_blurb.text = CarData.get_car(key).blurb

func _confirm(key: String) -> void:
	var car := CarData.get_car(key)
	festival.choose("Take the %s?" % car.name, car.blurb, [
		["YES - LET'S DRIVE", func():
			Profile.choose_starter(key)
			festival.toast("%s ADDED TO YOUR GARAGE" % car.name.to_upper())
			festival.reset_to(HubScreen.new())],
		["KEEP LOOKING", Callable()],
	])

func back() -> void:
	festival.reset_to(TitleScreen.new())
