class_name UpgradeScreen
extends MenuScreen
## Upgrade shop for one garage car. Tabs: Engine / Drivetrain / Tyres / Chassis / Aero / Swap.
## ◀ ▶ previews a part level (stats card shows the PI and stat deltas, benchmarked in C++ on a
## worker thread), A buys and installs it. Returning a category to stock is free.

const GROUPS := ["Engine", "Drivetrain", "Tyres", "Chassis", "Aero", "Swap"]

var index := 0
var _tab := 0
var _tabs: HBoxContainer
var _list: VBoxContainer
var _stats: CarStatsPanel
var _preview := {} # cat -> level being previewed on the focused row
var _desc: Label

func _init(garage_index := 0) -> void:
	super._init()
	index = garage_index

func _entry() -> Dictionary:
	return Profile.data.garage[index]

func build() -> void:
	var e := _entry()
	var col := make_column(560)
	col.add_child(UIKit.header("Performance Upgrades", "", CarData.get_car(e.key).name))
	_tabs = make_tabs(col, GROUPS)
	_list = make_list(col, 440)
	_desc = UIKit.label("", 17, UIKit.DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(540, 0)
	col.add_child(_desc)
	_stats = CarStatsPanel.new()
	_stats.position = Vector2(870, 470)
	add_child(_stats)
	set_hints([["◀▶", "Preview"], ["A", "Buy / install"], ["L1", ""], ["R1", "Category"], ["B", "Back"]])
	stage.show_entry(e)

func refresh() -> void:
	highlight_tabs(_tabs, _tab)
	for c in _list.get_children():
		c.queue_free()
	_preview.clear()
	var e := _entry()
	var first: UIRow = null
	if GROUPS[_tab] == "Swap":
		first = _build_swaps(e)
	else:
		for cat in UpgradeData.CATEGORIES:
			if cat.group != GROUPS[_tab]:
				continue
			var row := UIRow.new(cat.name)
			_list.add_child(row)
			_update_row(row, cat)
			row.on_adjust = _adjust.bind(row, cat)
			row.on_accept = _buy.bind(cat)
			row.on_focus = func():
				_preview.clear()
				_update_row(row, cat)
				_update_stats()
			if first == null:
				first = row
	_update_stats()
	if first and is_inside_tree():
		first.call_deferred("grab_focus")

func _installed(cat_id: String) -> int:
	return int(_entry().upgrades.get(cat_id, 0))

func _update_row(row: UIRow, cat: Dictionary) -> void:
	var inst := _installed(cat.id)
	var lvl := int(_preview.get(cat.id, inst))
	row.set_value(cat.levels[lvl].name, UIKit.CYAN if lvl == inst else UIKit.AMBER)
	if lvl == inst:
		row.set_sub("INSTALLED" if lvl > 0 else "", UIKit.GREEN)
	elif lvl == 0:
		row.set_sub("FREE", UIKit.DIM)
	else:
		var price := UpgradeData.price_of(cat.id, lvl)
		row.set_sub(UIKit.money(price), UIKit.GREEN if int(Profile.data.credits) >= price else UIKit.RED)
	row.set_fraction(float(lvl) / float(cat.levels.size() - 1), float(inst) / float(cat.levels.size() - 1))
	_desc.text = _describe(cat, lvl)

func _describe(cat: Dictionary, lvl: int) -> String:
	var L: Dictionary = cat.levels[lvl]
	var parts := []
	for k in L.get("mul", {}):
		parts.append("%s %+d%%" % [_nice(k), roundi((float(L.mul[k]) - 1.0) * 100.0)])
	for k in L.get("add", {}):
		parts.append("%s %+.2f" % [_nice(k), float(L.add[k])])
	if L.get("turbo", false):
		parts.append("turbo conversion on NA engines")
	if L.has("set"):
		if L.set.has("tire_compound"):
			parts.append(["street", "sport", "semi-slick", "drift", "rally", "snow"][int(L.set.tire_compound)] + " compound")
		if L.set.has("layout"):
			parts.append("all-wheel drive, 35% front")
		if L.set.has("diff_rear"):
			parts.append("limited-slip rear differential")
	return "  ·  ".join(parts) if not parts.is_empty() else "Factory specification."

static func _nice(k: String) -> String:
	return k.replace("_", " ").replace("torque scale", "torque").replace("torque top end", "top-end torque")

func _adjust(dir: int, row: UIRow, cat: Dictionary) -> void:
	var lvl := int(_preview.get(cat.id, _installed(cat.id)))
	lvl = clampi(lvl + dir, 0, cat.levels.size() - 1)
	_preview.clear()
	if lvl != _installed(cat.id):
		_preview[cat.id] = lvl
	_update_row(row, cat)
	_update_stats()

func _preview_upgrades() -> Dictionary:
	var u: Dictionary = _entry().upgrades.duplicate()
	for k in _preview:
		u[k] = _preview[k]
	return u

func _update_stats() -> void:
	var e := _entry()
	var cur := Profile.overrides_for(e)
	if _preview.is_empty():
		_stats.show_build(e.key, cur)
	else:
		_stats.show_build(e.key, cur, UpgradeData.build_overrides(e.key, _preview_upgrades(), e.tune))

func _buy(cat: Dictionary) -> void:
	if not _preview.has(cat.id):
		festival.toast("USE ◀ ▶ TO PICK A PART")
		return
	var lvl := int(_preview[cat.id])
	var price := UpgradeData.price_of(cat.id, lvl) if lvl > 0 else 0
	var name: String = cat.levels[lvl].name
	if price > int(Profile.data.credits):
		festival.toast("NOT ENOUGH CREDITS — NEED %s" % UIKit.money(price))
		return
	var verb := "Install %s %s for %s?" % [name, cat.name, UIKit.money(price)] if lvl > 0 else "Return %s to stock?" % cat.name
	festival.choose(verb, "", [
		["INSTALL" if lvl > 0 else "REVERT TO STOCK", func(): _install(cat.id, lvl, price)],
		["CANCEL", Callable()],
	])

func _install(cat_id: String, lvl: int, price: int) -> void:
	if price > 0 and not Profile.spend(price):
		return
	var e := _entry()
	if lvl == 0:
		e.upgrades.erase(cat_id)
	else:
		e.upgrades[cat_id] = lvl
	const CAT_TUNE_KEYS := {
		"brakes": ["brake_torque", "brake_bias"],
		"springs": ["spring_front", "spring_rear", "mount_height", "bump_front", "bump_rear", "rebound_front", "rebound_rear"],
		"arb": ["arb_front", "arb_rear"],
		"gearbox": ["final_drive", "gear_1", "gear_2", "gear_3", "gear_4", "gear_5", "gear_6", "gear_7", "gear_8"],
		"diff": ["lsd_accel", "lsd_decel", "lsd_preload", "awd_front_split"],
		"aero": ["lift_front", "lift_rear"]
	}
	if CAT_TUNE_KEYS.has(cat_id) and e.has("tune") and typeof(e.tune) == TYPE_DICTIONARY:
		for tk in CAT_TUNE_KEYS[cat_id]:
			e.tune.erase(tk)
	e.spent = int(e.get("spent", 0)) + price
	e.pi = Profile.compute_pi(e)
	Profile.save()
	Haptics.impact(0.5, 60)
	festival.toast("INSTALLED  ·  %s" % CarData.class_label(int(e.pi)))
	stage.show_entry(e)
	var keep := _tab
	_tab = keep
	refresh()

# ---- Engine swaps -----------------------------------------------------------------------------

func _build_swaps(e: Dictionary) -> UIRow:
	var first: UIRow = null
	var donors: Array = UpgradeData.SWAPS.get(e.key, [])
	var inst := _installed("swap")
	for n in range(donors.size() + 1):
		var title := "Original engine" if n == 0 else "%s engine" % CarData.get_car(donors[n - 1]).name
		var row := UIRow.new(title)
		var spec := NTSim.car_params(e.key if n == 0 else donors[n - 1], {})
		var kind: String = ["NA", "Turbo", "Rotary", "Hybrid", "Diesel"][clampi(int(spec.get("engine_kind", 0)), 0, 4)]
		row.set_value("%d cyl %s" % [int(spec.cylinders), kind] if kind != "Rotary" else "Twin-rotor")
		if n == inst:
			row.set_sub("INSTALLED", UIKit.GREEN)
		else:
			var price: int = UpgradeData.SWAP_PRICE[n]
			row.set_sub(UIKit.money(price) if n > 0 else "FREE", UIKit.GREEN if int(Profile.data.credits) >= price else UIKit.RED)
		row.on_focus = func():
			_preview.clear()
			if n != inst:
				_preview["swap"] = n
			_desc.text = "Engine swaps transplant the donor's engine, redline and induction. Existing engine parts carry over."
			_update_stats()
			stage.show_entry(e)
		row.on_accept = func():
			if n == inst:
				festival.toast("ALREADY INSTALLED")
				return
			var price: int = UpgradeData.SWAP_PRICE[n]
			if price > int(Profile.data.credits):
				festival.toast("NOT ENOUGH CREDITS — NEED %s" % UIKit.money(price))
				return
			festival.choose("Swap to the %s?" % title, "Cost %s. You can swap back to the original engine for free." % UIKit.money(price), [
				["SWAP ENGINE", func(): _install("swap", n, price)],
				["CANCEL", Callable()],
			])
		_list.add_child(row)
		if first == null:
			first = row
	return first

func tab(dir: int) -> void:
	_tab = wrapi(_tab + dir, 0, GROUPS.size())
	refresh()
