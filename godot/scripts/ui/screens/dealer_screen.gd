class_name DealerScreen
extends MenuScreen
## Dealership: the full roster sorted by PI. Shop cars can be bought; barn finds and the
## championship car show how to earn them. Buying offers to switch to the new car.

var _list: VBoxContainer
var _stats: CarStatsPanel
var _blurb: Label

func build() -> void:
	var col := make_column(560)
	col.add_child(UIKit.header("Dealership", "販", "Japanese performance, new and used"))
	_list = make_list(col, 440)
	_blurb = UIKit.label("", 17, UIKit.DIM)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(540, 0)
	col.add_child(_blurb)
	_stats = CarStatsPanel.new()
	_stats.position = Vector2(870, 470)
	add_child(_stats)
	set_hints([["A", "Buy"], ["RS", "Look around"], ["B", "Back"]])

func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var keys := CarData.keys()
	keys.sort_custom(func(a, b): return CarData.STOCK_PI[a] < CarData.STOCK_PI[b])
	var first: UIRow = null
	for key in keys:
		var car := CarData.get_car(key)
		var pi := int(CarData.STOCK_PI[key])
		var row := UIRow.new(car.name)
		row.set_value(CarData.class_label(pi), CarData.CLASS_COLORS[CarData.pi_class(pi)])
		var unlock: String = car.unlock
		var owned := Profile.owns(key)
		match unlock:
			"barn":
				row.set_sub("BARN FIND" if not owned else "OWNED", UIKit.DIM if not owned else UIKit.GREEN)
			"championship":
				row.set_sub("CROWN PRIZE" if not owned else "OWNED", UIKit.NEON if not owned else UIKit.GREEN)
			_:
				var price := int(car.price)
				row.set_sub(("OWNED · " if owned else "") + UIKit.money(price), UIKit.GREEN if int(Profile.data.credits) >= price else UIKit.RED)
		row.on_focus = _preview.bind(key)
		row.on_accept = _buy.bind(key)
		_list.add_child(row)
		if first == null:
			first = row
	if first and is_inside_tree():
		first.call_deferred("grab_focus")

func _preview(key: String) -> void:
	var car := CarData.get_car(key)
	stage.show_key(key)
	_stats.show_build(key, {})
	var how := ""
	match car.unlock:
		"barn": how = "  Find it in one of the barns hidden around the map."
		"championship": how = "  Win the Neon Touge Crown championship to earn it."
	_blurb.text = car.blurb + how

func _buy(key: String) -> void:
	var car := CarData.get_car(key)
	if car.unlock in ["barn", "championship"]:
		festival.toast("NOT FOR SALE — %s" % ("FIND IT IN A BARN" if car.unlock == "barn" else "WIN THE CROWN"))
		return
	var price := int(car.price)
	if price > int(Profile.data.credits):
		festival.toast("NOT ENOUGH CREDITS — NEED %s" % UIKit.money(price))
		return
	festival.choose("Buy the %s?" % car.name, "%s  ·  %s" % [UIKit.money(price), CarData.class_label(int(CarData.STOCK_PI[key]))], [
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
