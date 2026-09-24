class_name GarageScreen
extends MenuScreen
## Your garage: every owned car with class/PI; A opens the car menu (drive, set current,
## upgrades, tuning, paint, sell). The focused car is shown on the stage with its stats.

var _list: VBoxContainer
var _stats: CarStatsPanel
var _info: Label
var _focus_index := -1

func build() -> void:
	var col := make_column(540)
	col.add_child(UIKit.header("My Garage", "", "%d vehicles" % Profile.data.garage.size()))
	_list = make_list(col, 520)
	_stats = CarStatsPanel.new()
	_stats.position = Vector2(870, 470)
	add_child(_stats)
	_info = UIKit.label("", 17, UIKit.DIM)
	_info.position = Vector2(870, 440)
	add_child(_info)
	set_hints([["A", "Car menu"], ["X", "Set current"], ["RS", "Look around"], ["B", "Back"]])

func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var cur := Profile.current_index()
	var focus_row: UIRow = null
	for i in range(Profile.data.garage.size()):
		var e: Dictionary = Profile.data.garage[i]
		var car := CarData.get_car(e.key)
		var row := UIRow.new(car.name, CarData.class_label(int(e.get("pi", 0))))
		row.set_value(CarData.class_label(int(e.get("pi", 0))), CarData.CLASS_COLORS[CarData.pi_class(int(e.get("pi", 0)))])
		var tags := []
		if i == cur:
			tags.append("★ DRIVING")
		if not (e.get("upgrades", {}) as Dictionary).is_empty():
			tags.append("TUNED")
		row.set_sub("  ".join(tags), UIKit.AMBER if i == cur else UIKit.DIM)
		row.on_focus = _on_focus.bind(i)
		row.on_accept = _car_menu.bind(i)
		_list.add_child(row)
		if (_focus_index < 0 and i == cur) or i == _focus_index:
			focus_row = row
	if focus_row and is_inside_tree():
		focus_row.call_deferred("grab_focus")

func _on_focus(i: int) -> void:
	_focus_index = i
	var e: Dictionary = Profile.data.garage[i]
	stage.show_entry(e)
	_stats.show_build(e.key, Profile.overrides_for(e))
	var swap := UpgradeData.swap_donor_key(e.key, int(e.upgrades.get("swap", 0)))
	_info.text = "Odometer %.0f km%s" % [float(e.get("km", 0.0)), ("  ·  %s engine" % CarData.get_car(swap).name) if swap != "" else ""]

func action_x() -> void:
	if _focus_index >= 0:
		Profile.set_current(_focus_index)
		festival.toast("NOW DRIVING: %s" % CarData.get_car(Profile.current_car().key).name.to_upper())
		refresh()

func _car_menu(i: int) -> void:
	var e: Dictionary = Profile.data.garage[i]
	var car := CarData.get_car(e.key)
	var opts := [
		["DRIVE THIS CAR", func():
			Profile.set_current(i)
			festival.drive()],
		["UPGRADES & ENGINE SWAPS", func(): festival.push(UpgradeScreen.new(i))],
		["TUNING", func(): festival.push(TuningScreen.new(i))],
		["PAINT", func(): festival.push(PaintScreen.new(i))],
	]
	if i != Profile.current_index():
		opts.insert(1, ["SET AS CURRENT CAR", func():
			Profile.set_current(i)
			refresh()])
	if Profile.data.garage.size() > 1:
		opts.append(["SELL  (%s)" % UIKit.money(Profile.sell_value(e)), _sell.bind(i)])
	opts.append(["BACK", Callable()])
	festival.choose(car.name, "%s  ·  %s" % [CarData.class_label(int(e.pi)), car.blurb], opts)

func _sell(i: int) -> void:
	var e: Dictionary = Profile.data.garage[i]
	var car := CarData.get_car(e.key)
	festival.choose("Sell the %s?" % car.name, "You'll receive %s. Upgrades and paint are sold with the car." % UIKit.money(Profile.sell_value(e)), [
		["SELL", func():
			var got := Profile.sell(i)
			if got >= 0:
				festival.toast("SOLD  +%s" % UIKit.money(got))
				_focus_index = mini(i, Profile.data.garage.size() - 1)
				refresh()],
		["KEEP IT", Callable()],
	])
