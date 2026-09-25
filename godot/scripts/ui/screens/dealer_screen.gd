class_name DealerScreen
extends MenuScreen
## European Auto Show: browse the full roster as car tiles, preview models and buy eligible cars.

var _scroll: ScrollContainer
var _list: UITileGrid
var _stats: CarStatsPanel
var _blurb: Label

func build() -> void:
	var col := make_column(560)
	col.add_child(UIKit.header("European Auto Show", "", "A curated collection of grand tourers and road legends"))
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(44, 142)
	_scroll.size = Vector2(760, 500)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	_list = UITileGrid.new(Vector2(228, 112), 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_stats = CarStatsPanel.new()
	_stats.position = Vector2(870, 440)
	add_child(_stats)
	_blurb = UIKit.label("", 17, UIKit.DIM)
	_blurb.position = Vector2(870, 610)
	_blurb.size = Vector2(410, 92)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_blurb)
	set_hints([["A", "Buy / unlock"], ["RS", "Look around"], ["B", "Back"]])

func refresh() -> void:
	_list.clear()
	var keys := CarData.keys()
	keys.sort_custom(func(a, b): return CarData.STOCK_PI[a] < CarData.STOCK_PI[b])
	var first: UITile = null
	for index in range(keys.size()):
		var key: String = keys[index]
		var car := CarData.get_car(key)
		var pi := int(CarData.STOCK_PI[key])
		var owned := Profile.owns(key)
		var tile := UITile.new(car.name, car.maker)
		tile.set_image(UIKit.art("cars", key))
		tile.set_tint(Color.from_hsv(float(index) / maxf(1.0, float(keys.size())), 0.58, 0.58))
		tile.set_badge(UIKit.class_badge(pi, 18))
		if owned:
			tile.add_tag("OWNED", UIKit.GREEN)
		elif car.unlock == "barn":
			tile.add_tag("BARN FIND", UIKit.AMBER)
		elif car.unlock == "championship":
			tile.add_tag("CHAMPIONSHIP", UIKit.NEON)
		else:
			tile.set_info(UIKit.money(int(car.price)), UIKit.GREEN if int(Profile.data.credits) >= int(car.price) else UIKit.RED)
		tile.on_focus = _preview.bind(key)
		tile.on_accept = _buy.bind(key)
		_list.add_tile(tile, index % 3, int(index / 3))
		if first == null:
			first = tile
	_list.link_focus()
	if first and is_inside_tree():
		first.call_deferred("grab_focus")

func _preview(key: String) -> void:
	var car := CarData.get_car(key)
	stage.show_key(key)
	_stats.show_build(key, {})
	var how := ""
	match car.unlock:
		"barn": how = " Find this car in a barn hidden across the Riviera."
		"championship": how = " Win the Euro GT Festival Grand Finale to earn it."
	_blurb.text = car.blurb + how

func _buy(key: String) -> void:
	var car := CarData.get_car(key)
	if car.unlock in ["barn", "championship"]:
		festival.toast("NOT FOR SALE - %s" % ("FIND IT IN A BARN" if car.unlock == "barn" else "WIN THE CROWN"))
		return
	if Profile.owns(key):
		festival.toast("ALREADY IN YOUR GARAGE")
		return
	var price := int(car.price)
	if price > int(Profile.data.credits):
		festival.toast("NOT ENOUGH CREDITS - NEED %s" % UIKit.money(price))
		return
	festival.choose("Buy the %s?" % car.name, "%s / %s" % [UIKit.money(price), CarData.class_label(int(CarData.STOCK_PI[key]))], [
		["BUY", func():
			if not Profile.spend(price):
				return
			var i := Profile.add_car(key, "dealer")
			Haptics.impact(0.6, 90)
			festival.choose("%s added to your garage" % car.name, "", [
				["DRIVE IT NOW", func():
					Profile.set_current(i)
					festival.drive()],
				["SET AS CURRENT CAR", func():
					Profile.set_current(i)
					refresh()],
				["KEEP SHOPPING", func(): refresh()],
			])],
		["CANCEL", Callable()],
	])

