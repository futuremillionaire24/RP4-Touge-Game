class_name RecordsScreen
extends MenuScreen
## Festival stats and per-event records, plus collection progress (Omamori, barns, rivals).

func build() -> void:
	var col := make_column(600)
	col.add_child(UIKit.header("Records", "記", "Festival level %d" % int(Profile.data.level)))
	var list := make_list(col, 540)
	var s: Dictionary = Profile.data.stats
	var km := float(s.get("distance_km", 0.0))
	var dist := "%.1f km" % km if bool(Settings.get_value("gameplay", "units_metric", true)) else "%.1f mi" % (km * 0.621371)
	var hours := float(s.get("play_seconds", 0.0)) / 3600.0
	_section(list, "Career")
	_stat(list, "Races / wins", "%d / %d" % [int(s.races), int(s.wins)])
	_stat(list, "Distance driven", dist)
	_stat(list, "Time played", "%.1f h" % hours)
	_stat(list, "Best drift score", str(int(s.get("drift_score", 0))))
	_stat(list, "Near misses", str(int(s.get("near_misses", 0))))
	_stat(list, "Cars owned", str(Profile.data.garage.size()))
	_stat(list, "Omamori found", "%d / 30" % Profile.data.omamori.size())
	_stat(list, "Rivals beaten", "%d / %d" % [Profile.data.rivals_beaten.size(), RivalData.RIVALS.size()])
	_section(list, "Event records")
	for ev in EventData.all():
		var rec: Dictionary = Profile.data.records.get(ev.id, {})
		var v := "—"
		if not rec.is_empty():
			v = "P%d  ·  %s" % [int(rec.best_pos), UIKit.time_str(float(rec.best_time))]
		_stat(list, ev.name, v, UIKit.AMBER if int(rec.get("best_pos", 99)) == 1 else UIKit.CYAN)
	set_hints([["B", "Back"]])
	stage.frame_offset = 2.2

func _section(list: VBoxContainer, title: String) -> void:
	var l := UIKit.label(title.to_upper(), 18, UIKit.NEON)
	l.custom_minimum_size = Vector2(0, 34)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	list.add_child(l)

func _stat(list: VBoxContainer, title: String, value: String, color := UIKit.CYAN) -> void:
	var r := UIRow.new(title)
	r.set_value(value, color)
	r.custom_minimum_size = Vector2(0, 40)
	list.add_child(r)

func leave() -> void:
	super.leave()
	stage.frame_offset = 1.3
