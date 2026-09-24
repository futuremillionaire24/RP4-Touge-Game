extends Node
## QA driver for the festival front end. Persists under the root across scene changes, sets up
## the profile for a scenario, loads the festival and drives it with injected pad events,
## screenshotting and logging focus/stack state after every step.

const SHOT_DIR := "D:/Android_RP4_Game/build/qa/menus/shots"
const A := JOY_BUTTON_A
const B := JOY_BUTTON_B
const X := JOY_BUTTON_X
const Y := JOY_BUTTON_Y
const L1 := JOY_BUTTON_LEFT_SHOULDER
const R1 := JOY_BUTTON_RIGHT_SHOULDER
const UP := JOY_BUTTON_DPAD_UP
const DOWN := JOY_BUTTON_DPAD_DOWN
const LEFT := JOY_BUTTON_DPAD_LEFT
const RIGHT := JOY_BUTTON_DPAD_RIGHT
const START := JOY_BUTTON_START

var fest: Festival
var scen := "fresh"
var n := 0
var args := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	scen = args.get("scenario", "fresh")
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	await get_tree().process_frame
	Settings.data = Settings._defaults()
	Settings.save_settings()
	match scen:
		"fresh": await sc_fresh()
		"erase": await sc_erase()
		"events": await sc_events()
		"garage": await sc_garage()
		"upgrades": await sc_upgrades()
		"tuning": await sc_tuning()
		"paint": await sc_paint()
		"dealer": await sc_dealer()
		"omikuji": await sc_omikuji()
		"records": await sc_records()
		"settings": await sc_settings()
		"stress": await sc_stress()
		"devtools": await sc_devtools()
		"modal": await sc_modal()
		"layout": await sc_layout()
		"padcheck": await sc_padcheck()
		"tuning2": await sc_tuning2()
		"modal2": await sc_modal2()
		"erase2": await sc_erase2()
		"perf": await sc_perf()
	log_line("DONE " + scen)
	get_tree().quit()

# ---- helpers ------------------------------------------------------------------------------

func log_line(s: String) -> void:
	print("QA| ", s)

func frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame

func secs(t: float) -> void:
	await get_tree().create_timer(t).timeout

func load_festival(start := "title") -> void:
	if start == "hub":
		get_tree().root.set_meta("festival_screen", "hub")
	get_tree().change_scene_to_file("res://scenes/festival.tscn")
	await frames(4)
	fest = get_tree().current_scene as Festival
	await frames(60)

func profile_fresh() -> void:
	for suf in ["", ".bak1", ".bak2", ".bak3", ".tmp"]:
		var p := ProjectSettings.globalize_path(Profile.PATH + suf)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	Profile.load_profile()

func profile_career(cars := ["sylph_s2"], credits := 50000, level := 1, draws := 0) -> void:
	profile_fresh()
	if Profile.STARTERS.has(cars[0]):
		Profile.choose_starter(cars[0])
	else:
		Profile.add_car(cars[0], "test", false)
	for i in range(1, cars.size()):
		Profile.add_car(cars[i], "test", false)
	Profile.data.onboarded = true
	Profile.data.credits = credits
	Profile.data.level = level
	Profile.data.omikuji = draws
	Profile.save()

func press(b: JoyButton, wait := 10, hold := 2) -> void:
	# The project has no joypad A/B in ui_accept/ui_cancel (see report), so unless raw_pad=1 is
	# passed, A/B are injected as the ui_accept / ui_cancel actions the screens expect.
	if not args.has("raw_pad") and (b == A or b == B):
		var ae := InputEventAction.new()
		ae.action = "ui_accept" if b == A else "ui_cancel"
		ae.pressed = true
		Input.parse_input_event(ae)
		await frames(hold)
		var ar := InputEventAction.new()
		ar.action = ae.action
		ar.pressed = false
		Input.parse_input_event(ar)
		await frames(wait)
		return
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = true
	e.pressure = 1.0
	Input.parse_input_event(e)
	await frames(hold)
	var r := InputEventJoypadButton.new()
	r.device = 0
	r.button_index = b
	r.pressed = false
	Input.parse_input_event(r)
	await frames(wait)

func press_n(b: JoyButton, k: int, wait := 6) -> void:
	for i in range(k):
		await press(b, wait)

## Press without waiting between press/release for rapid-fire tests.
func tap_raw(b: JoyButton, pressed: bool) -> void:
	if not args.has("raw_pad") and (b == A or b == B):
		var ae := InputEventAction.new()
		ae.action = "ui_accept" if b == A else "ui_cancel"
		ae.pressed = pressed
		Input.parse_input_event(ae)
		return
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = pressed
	e.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(e)

func key(k: Key, wait := 10) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	var r := InputEventKey.new()
	r.keycode = k
	r.physical_keycode = k
	r.pressed = false
	Input.parse_input_event(r)
	await frames(wait)

func focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner()

func focus_desc() -> String:
	var f := focus_owner()
	if f == null:
		return "<NONE>"
	var t := ""
	if f is UIRow:
		t = (f as UIRow)._title.text
	elif f is Button:
		t = (f as Button).text
	else:
		t = f.get_class()
	var tags := []
	if fest and is_instance_valid(fest) and fest.modal_open() and fest._modal.is_ancestor_of(f):
		tags.append("modal")
	if fest and is_instance_valid(fest) and fest.top() and not fest.top().is_ancestor_of(f) and not tags.has("modal"):
		tags.append("NOT-IN-TOP-SCREEN")
	if not f.is_visible_in_tree():
		tags.append("HIDDEN")
	var sc := _scroll_of(f)
	if sc:
		var r := f.get_global_rect()
		var sr := sc.get_global_rect()
		if r.position.y < sr.position.y - 1 or r.end.y > sr.end.y + 1:
			tags.append("OFFSCREEN-IN-SCROLL(%d..%d vs %d..%d)" % [r.position.y, r.end.y, sr.position.y, sr.end.y])
	return "'%s'%s" % [t, (" [" + ",".join(tags) + "]") if not tags.is_empty() else ""]

func _scroll_of(c: Node) -> ScrollContainer:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null

func top_name() -> String:
	if fest == null or not is_instance_valid(fest):
		var cs := get_tree().current_scene
		return "scene:" + (cs.name if cs else "null")
	var t := fest.top()
	return t.get_script().get_global_name() if t else "none"

func state() -> String:
	if fest == null or not is_instance_valid(fest):
		return "scene=%s focus=%s" % [top_name(), focus_desc()]
	var stack := []
	for s in fest._stack:
		stack.append(s.get_script().get_global_name())
	var toast := (fest._toast.text + "@%.2f/a%.2f" % [fest._toast_time, fest._toast.modulate.a]) if fest._toast.modulate.a > 0.05 else ""
	return "top=%s stack=%s modal=%s focus=%s toast='%s' credits=%d cars=%d" % [top_name(), "/".join(stack), fest.modal_open(), focus_desc(), toast, int(Profile.data.credits), Profile.data.garage.size()]

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	var p := "%s/%s_%02d_%s.png" % [SHOT_DIR, scen, n, name]
	get_viewport().get_texture().get_image().save_png(p)
	log_line("SHOT %s_%02d_%s | %s" % [scen, n, name, state()])

func step(b: JoyButton, name: String, wait := 12) -> void:
	await press(b, wait)
	await shot(name)

## Press DOWN until the focused row title matches (max tries).
func goto_row(title: String, dir := DOWN, tries := 20) -> bool:
	var flipped := false
	for i in range(tries * 2):
		var f := focus_owner()
		if f is UIRow and (f as UIRow)._title.text.begins_with(title):
			return true
		await press(dir, 6)
		if focus_owner() == f and not flipped:
			flipped = true
			dir = UP if dir == DOWN else DOWN
	log_line("GOTO FAILED '%s' focus=%s" % [title, focus_desc()])
	return false

## Work around the modal focus-escape bug: focus a dialog row by title, then press A.
func modal_pick(title: String, shot_name := "") -> void:
	await frames(3)
	if not fest.modal_open():
		log_line("MODAL_PICK '%s': no modal open" % title)
		return
	var found: UIRow = null
	for r in fest._modal.find_children("*", "UIRow", true, false):
		if (r as UIRow)._title.text.begins_with(title):
			found = r
	if found == null:
		log_line("MODAL_PICK '%s': not found" % title)
		return
	found.grab_focus()
	await frames(2)
	if shot_name != "":
		await step(A, shot_name, 25)
	else:
		await press(A, 25)

func modal_titles() -> String:
	if not fest.modal_open():
		return "<no modal>"
	var t := []
	for r in fest._modal.find_children("*", "UIRow", true, false):
		t.append((r as UIRow)._title.text)
	return " | ".join(t)

## Layout audit: controls leaving the viewport, clipped row titles, labels wider than their box.
func audit(tag: String) -> void:
	if fest == null or not is_instance_valid(fest):
		return
	var vp := Rect2(Vector2.ZERO, Vector2(1334, 750))
	var issues := []
	_audit_node(fest.root_control(), vp, issues)
	for s in issues:
		log_line("AUDIT[%s] %s" % [tag, s])
	if issues.is_empty():
		log_line("AUDIT[%s] clean" % tag)

func _audit_node(n0: Node, vp: Rect2, issues: Array) -> void:
	for c in n0.get_children():
		if not (c is Control) or not (c as Control).is_visible_in_tree():
			continue
		var ctl := c as Control
		var r := ctl.get_global_rect()
		if r.size.x > 1 and r.size.y > 1 and not vp.grow(1).encloses(r) and not (ctl is ScrollContainer) and not _in_scroll(ctl):
			issues.append("OUT-OF-VIEWPORT %s '%s' rect=%s" % [ctl.get_class(), _txt(ctl), r])
		if ctl is Label:
			var l := ctl as Label
			if l.text != "" and l.autowrap_mode == TextServer.AUTOWRAP_OFF:
				var font := l.get_theme_font("font")
				var fs := l.get_theme_font_size("font_size")
				var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				if w > l.size.x + 2 and (not _in_scroll(l) or _visible_in_scroll(l)):
					issues.append("TEXT-OVERFLOW '%s' text_w=%d box_w=%d clip=%s at %s" % [l.text, w, l.size.x, l.clip_text, r.position])
		if ctl is UIRow:
			var row := ctl as UIRow
			var ms: Vector2 = (row.get_child(0) as Control).get_combined_minimum_size()
			if ms.x > row.size.x - 32 + 2:
				issues.append("ROW-CONTENT-WIDER '%s' min=%d row=%d" % [row._title.text, ms.x, row.size.x])
		_audit_node(c, vp, issues)

func _in_scroll(c: Node) -> bool:
	return _scroll_of(c) != null

func _visible_in_scroll(c: Control) -> bool:
	var sc := _scroll_of(c)
	return sc == null or sc.get_global_rect().intersects(c.get_global_rect())

func _txt(c: Control) -> String:
	if c is Label:
		return (c as Label).text.left(40)
	if c is UIRow:
		return (c as UIRow)._title.text
	return c.name

# ---- scenarios --------------------------------------------------------------------------------

func sc_fresh() -> void:
	profile_fresh()
	await load_festival()
	await shot("title")
	audit("title")
	await step(B, "title_press_B")           # any pad button opens the menu, even B
	await step(B, "title_B_hides_menu")
	await step(A, "title_A_menu")
	await step(DOWN, "down1")
	await step(DOWN, "down2")
	await step(DOWN, "down3_past_end")
	await step(UP, "up1")
	await step(UP, "up2")
	await step(UP, "up3_past_top")
	await goto_row("NEW FESTIVAL", UP)
	await step(A, "starter", 60)
	audit("starter")
	await step(DOWN, "starter_car2", 50)
	await step(DOWN, "starter_car3", 50)
	await step(DOWN, "starter_past_end", 20)
	await step(L1, "starter_L1")
	await step(X, "starter_X")
	await step(B, "starter_B_title", 40)
	await press(A)
	await goto_row("NEW FESTIVAL")
	await step(A, "starter_again", 40)
	await step(A, "starter_confirm_dialog", 20)
	audit("starter_dialog")
	await step(B, "starter_dialog_B")
	await step(A, "starter_dialog2", 20)
	await step(DOWN, "dialog_down")
	await step(DOWN, "dialog_down_again")
	await step(DOWN, "dialog_down_3")
	await step(UP, "dialog_up")
	await step(A, "hub_first", 10)
	await shot("hub_first_toast")
	await frames(60)
	await shot("hub_settled")
	audit("hub")
	log_line("profile garage=%s onboarded=%s credits=%d" % [str(Profile.data.garage.map(func(e): return e.key)), Profile.data.onboarded, int(Profile.data.credits)])
	for i in range(9):
		await step(DOWN, "hub_down%d" % i, 8)
	await step(B, "hub_B", 40)
	await step(A, "title_menu_after_hub", 10)
	await step(A, "continue", 50)

func sc_erase() -> void:
	profile_career(["hachi_gt"], 30000, 2)
	await load_festival()
	await step(A, "menu")
	await goto_row("NEW FESTIVAL")
	await step(A, "erase_dialog", 20)
	audit("erase_dialog")
	await step(DOWN, "erase_dialog_down")
	await step(DOWN, "erase_dialog_down2")
	await step(DOWN, "erase_dialog_down3")
	await step(B, "erase_dialog_B")
	log_line("after B: modal=%s menu_visible=%s" % [fest.modal_open(), fest.top()._menu.visible])
	await step(B, "erase_dialog_B2")
	log_line("after B2: modal=%s menu_visible=%s" % [fest.modal_open(), fest.top()._menu.visible])
	await step(A, "erase_dialog_A_after_B")
	await frames(40)
	await shot("erase_after_A_settled")
	# Restart the festival and actually erase.
	await load_festival()
	await step(A, "menu2")
	await goto_row("NEW FESTIVAL")
	await step(A, "erase_dialog_again", 20)
	await goto_row("ERASE", UP, 4)
	await step(A, "erased_starter", 40)
	log_line("after erase: garage=%d credits=%d onboarded=%s level=%d" % [Profile.data.garage.size(), int(Profile.data.credits), Profile.data.onboarded, int(Profile.data.level)])
	await step(B, "erased_starter_B_title", 30)
	await step(A, "erased_title_menu")

func sc_events() -> void:
	profile_career(["sylph_s2", "raijin_r"], 40000, 1)
	Profile.set_current(0)
	await load_festival("hub")
	await shot("hub")
	await goto_row("EVENTS")
	await step(A, "events", 40)
	audit("events")
	for i in range(12):
		await step(DOWN, "events_down%d" % i, 8)
	await step(R1, "tab_races", 20)
	audit("tab_races")
	await step(R1, "tab_touge", 20)
	await step(R1, "tab_duels", 20)
	await step(A, "duel_locked_A", 6)
	await step(R1, "tab_wrap_all", 20)
	await step(L1, "tab_L1_duels", 20)
	await key(KEY_Q)
	await shot("tab_Q_key")
	await key(KEY_E)
	await key(KEY_E)
	await shot("tab_E_E")
	await step(L1, "tab_back", 20)
	# locked event (Shuto C1 = level 3) on All tab
	await goto_row("Shuto C1", DOWN, 3)
	await goto_row("Shuto C1", UP, 12)
	await step(A, "locked_A", 6)
	await step(X, "events_X")
	await step(Y, "events_Y")
	await step(B, "events_B_hub", 40)
	# over-class: switch to the Raijin via garage X then back to events
	await goto_row("GARAGE", UP)
	await step(A, "garage", 40)
	await goto_row("Raijin")
	await step(X, "garage_X_raijin", 30)
	await step(B, "hub_after_raijin", 40)
	await goto_row("EVENTS", UP)
	await step(A, "events_raijin", 40)
	await goto_row("Container")
	await step(A, "overclass_dialog", 20)
	audit("overclass")
	await step(A, "overclass_open_garage", 40)
	await step(B, "overclass_back_events", 40)
	await step(DOWN, "overclass_back_events_down", 10)
	await goto_row("Akina Time Attack")
	await step(A, "start_event", 90)
	await frames(200)
	await shot("after_start_event")

func sc_garage() -> void:
	profile_career(["sylph_s2", "rotora_fd", "raijin_r"], 40000, 1)
	Profile.set_current(0)
	await load_festival("hub")
	await goto_row("GARAGE")
	await step(A, "garage", 40)
	audit("garage")
	await step(DOWN, "garage_rotora", 3)
	await shot("garage_rotora_loading_early")
	await frames(40)
	await shot("garage_rotora_loaded")
	await step(X, "garage_X_set_current", 20)
	await step(DOWN, "garage_raijin", 40)
	await step(A, "car_menu", 20)
	audit("car_menu")
	await step(B, "car_menu_B")
	await step(A, "car_menu2", 20)
	log_line("car menu rows: " + modal_titles())
	await modal_pick("SELL", "sell_confirm")
	log_line("sell rows: " + modal_titles())
	await step(B, "sell_confirm_B_keep", 10)
	await step(UP, "after_keep_up")
	await step(DOWN, "after_keep_down")
	await step(A, "car_menu3", 20)
	await modal_pick("SELL", "sell_confirm2")
	await modal_pick("SELL", "sold")
	audit("after_sell")
	await step(UP, "after_sold_up", 20)
	await step(A, "car_menu_x", 20)
	log_line("car menu rows: " + modal_titles())
	await modal_pick("SET AS CURRENT", "set_current_from_menu")
	await step(A, "car_menu_y", 20)
	await modal_pick("SELL", "sell_confirm3")
	await modal_pick("SELL", "sold2")
	await step(A, "car_menu_last", 20)
	log_line("last car menu rows: " + modal_titles())
	audit("car_menu_last")
	await step(B, "car_menu_last_B")
	await step(L1, "garage_L1")
	await step(Y, "garage_Y")
	await step(A, "car_menu_last2", 20)
	await modal_pick("UPGRADES", "to_upgrades")
	await frames(30)
	await step(B, "upgrades_back", 40)
	await step(A, "car_menu_again", 20)
	await modal_pick("PAINT", "to_paint")
	await frames(30)
	await step(B, "paint_back", 40)
	await step(B, "hub", 40)
	log_line("garage entries=%d current=%d" % [Profile.data.garage.size(), Profile.current_index()])

func sc_upgrades() -> void:
	profile_career(["sylph_s2"], 30000, 1)
	await load_festival("hub")
	await goto_row("GARAGE")
	await press(A, 30)
	await press(A, 20)
	await goto_row("UPGRADES")
	await step(A, "upgrades", 60)
	audit("upgrades")
	await step(A, "buy_without_preview", 6)
	await step(RIGHT, "intake_preview_street", 2)
	await shot("intake_preview_benchmarking")
	await frames(60)
	await shot("intake_preview_done")
	await step(RIGHT, "intake_sport", 40)
	await step(RIGHT, "intake_race", 40)
	await step(RIGHT, "intake_past_max", 20)
	await step(A, "buy_dialog", 20)
	await step(A, "bought", 40)
	audit("bought")
	await step(DOWN, "exhaust_row", 20)
	await step(UP, "back_to_intake", 20)
	await step(LEFT, "intake_to_sport_preview", 30)
	await press(LEFT, 6)
	await press(LEFT, 6)
	await step(LEFT, "intake_stock_preview", 30)
	await step(A, "revert_dialog", 20)
	await step(A, "reverted", 40)
	# expensive part
	await goto_row("Forced")
	await press_n(RIGHT, 3)
	await step(RIGHT, "turbo_race_preview", 40)
	await step(A, "turbo_not_enough", 6)
	for i in range(8):
		await step(DOWN, "engine_down%d" % i, 8)
	for t in range(6):
		await step(R1, "tab%d" % (t + 1), 40)
		audit("tab%d" % (t + 1))
	await step(L1, "tab_L1_swap", 40)
	for i in range(4):
		await step(DOWN, "swap_row%d" % i, 50)
	await step(UP, "swap_up", 50)
	await step(A, "swap_accept", 20)
	await step(B, "swap_dialog_B", 20)
	await step(B, "upgrades_B", 40)

func sc_tuning() -> void:
	profile_career(["sylph_s2"], 30000, 1)
	await load_festival("hub")
	await goto_row("GARAGE")
	await press(A, 30)
	await press(A, 20)
	await goto_row("TUNING")
	await step(A, "tuning", 50)
	audit("tuning")
	await step(RIGHT, "tyres_press_right", 10)
	await press_n(RIGHT, 5)
	await shot("tyres_right6")
	await step(DOWN, "tyres_rear", 10)
	await step(X, "tyres_X_reset", 10)
	for p in range(10):
		await step(R1, "page%d" % (p + 2), 20)
		audit("page%d" % (p + 2))
		if p == 1:
			await step(A, "locked_row_A", 6)
			await step(RIGHT, "locked_row_right", 6)
			await step(LEFT, "locked_row_left", 6)
	# Presets page (index 0)
	await goto_row("GRIP", UP, 3)
	await step(A, "preset_grip", 6)
	await step(X, "presets_X", 6)
	await goto_row("RESET ALL")
	await step(A, "reset_all", 6)
	await step(B, "tuning_B", 40)
	# Now with parts installed: gearing graph etc.
	var e: Dictionary = Profile.data.garage[0]
	e.upgrades = {"gearbox": 3, "springs": 3, "arb": 2, "diff": 3, "aero": 2}
	e.pi = Profile.compute_pi(e)
	Profile.save()
	await press(A, 20)
	await goto_row("TUNING")
	await step(A, "tuning_parts", 50)
	for p in range(10):
		await step(R1, "parts_page%d" % (p + 2), 20)
		audit("parts_page%d" % (p + 2))
		if PAGES_T[(p + 2) % 10] == "Gearing":
			await press_n(RIGHT, 20, 3)
			await shot("gearing_fd_up")
			await press_n(DOWN, 9, 5)
			await shot("gearing_bottom_scrolled")
	await step(B, "tuning_parts_B", 40)

func sc_tuning2() -> void:
	profile_career(["sylph_s2"], 30000, 1)
	await load_festival("hub")
	await goto_row("GARAGE")
	await press(A, 30)
	await press(A, 20)
	await modal_pick("TUNING")
	await frames(40)
	await step(L1, "presets", 20)
	await step(A, "grip_applied", 6)
	log_line("tune after grip: %s" % str(Profile.data.garage[0].tune))
	await step(RIGHT, "presets_right", 6)
	await step(X, "presets_X", 6)
	log_line("tune after X on presets: %d keys" % Profile.data.garage[0].tune.size())
	await step(R1, "tyres_after_grip", 20)
	await step(R1, "alignment_after_grip", 20)
	await step(L1, "", 5)
	await step(L1, "presets2", 20)
	await goto_row("RESET ALL")
	await step(A, "reset_all", 6)
	log_line("tune after reset all: %d keys" % Profile.data.garage[0].tune.size())
	await step(R1, "tyres_after_reset", 20)
	await step(B, "saved", 30)

const PAGES_T :=["Presets", "Tyres", "Alignment", "Springs", "Damping", "Anti-roll", "Gearing", "Differential", "Brakes", "Aero"]

func sc_paint() -> void:
	profile_career(["sylph_s2"], 30000, 1)
	var orig: Array = Profile.data.garage[0].paint.duplicate()
	await load_festival("hub")
	await goto_row("GARAGE")
	await press(A, 30)
	await press(A, 20)
	await goto_row("PAINT")
	await step(A, "paint", 50)
	audit("paint")
	await step(RIGHT, "palette1", 10)
	await press_n(RIGHT, 4)
	await shot("palette5")
	await step(DOWN, "hue", 6)
	await press_n(RIGHT, 20, 3)
	await shot("hue_plus20")
	await step(A, "hue_A_nothing", 6)
	await step(DOWN, "sat", 6)
	await press_n(LEFT, 30, 3)
	await shot("sat_minus30")
	await step(DOWN, "bright", 6)
	await step(DOWN, "finish", 6)
	for i in range(7):
		await step(RIGHT, "finish%d" % i, 20)
	await step(DOWN, "factory", 6)
	await step(DOWN, "apply", 6)
	await step(DOWN, "past_apply", 6)
	await step(B, "discard_B", 40)
	log_line("paint after discard same=%s" % str(Profile.data.garage[0].paint == orig))
	await step(B, "hub_after_discard", 60)
	await press(A, 30)
	await press(A, 20)
	await goto_row("PAINT")
	await step(A, "paint2", 50)
	await press_n(RIGHT, 3)
	await goto_row("APPLY")
	await step(A, "applied", 40)
	log_line("paint after apply changed=%s" % str(Profile.data.garage[0].paint != orig))

func sc_dealer() -> void:
	profile_career(["sylph_s2"], 60000, 1)
	await load_festival("hub")
	await goto_row("DEALERSHIP")
	await step(A, "dealer", 40)
	audit("dealer")
	for i in range(12):
		await step(DOWN, "dealer_down%d" % i, 25)
	await step(A, "dealer_bottom_A", 6)
	await goto_row("Kaido", UP, 12)
	await step(A, "barn_A", 6)
	await goto_row("Raijin", DOWN, 12)
	await goto_row("Raijin", UP, 12)
	await step(A, "expensive_A", 6)
	await goto_row("Rotora", UP, 12)
	await step(A, "buy_dialog", 20)
	await step(A, "bought_dialog", 20)
	audit("bought_dialog")
	await step(B, "bought_dialog_B", 20)
	await goto_row("Sylph", UP, 12)
	await step(A, "buy_owned_again_dialog", 20)
	await step(B, "cancel", 20)
	await step(L1, "dealer_L1")
	await step(X, "dealer_X")
	await step(B, "dealer_B", 40)

func sc_omikuji() -> void:
	profile_career(["sylph_s2"], 30000, 3, 2)
	await load_festival("hub")
	await goto_row("OMIKUJI")
	await step(A, "omikuji", 30)
	audit("omikuji")
	await step(A, "draw_start", 2)
	await secs(0.5)
	await shot("shaking")
	await secs(0.8)
	await shot("stick_out")
	await secs(0.6)
	await shot("reveal")
	audit("reveal")
	await secs(1.0)
	await shot("reveal_settled")
	await step(A, "draw2_start", 20)
	await secs(0.4)
	await step(A, "spam_A_mid_draw", 2)
	await secs(2.0)
	await shot("reveal2")
	await step(A, "no_draws", 6)
	await step(DOWN, "down", 6)
	Profile.data.omikuji = 1
	Profile.changed.emit()
	await secs(0.3)
	await step(A, "draw3_start", 20)
	log_line("draws after draw3 start=%d credits=%d" % [int(Profile.data.omikuji), int(Profile.data.credits)])
	await step(B, "B_mid_draw", 40)
	await secs(2.0)
	await shot("hub_after_B_mid_draw")
	log_line("draws left=%d" % int(Profile.data.omikuji))

func sc_records() -> void:
	profile_career(["sylph_s2"], 30000, 1)
	Profile.data.records["docks_circuit"] = {"best_time": 245.3, "best_pos": 1, "wins": 2}
	Profile.data.records["shibuya_gp"] = {"best_time": 301.9, "best_pos": 3, "wins": 0}
	Profile.save()
	await load_festival("hub")
	await goto_row("RECORDS")
	await step(A, "records", 40)
	audit("records")
	for i in range(22):
		await step(DOWN, "rec_down%d" % i, 6)
	await step(A, "rec_A", 6)
	await step(R1, "rec_R1", 6)
	await step(B, "rec_B", 40)
	await shot("hub_after_records")

func sc_settings() -> void:
	profile_career(["sylph_s2"], 30000, 1)
	await load_festival("hub")
	await goto_row("SETTINGS")
	await step(A, "settings", 40)
	for p in range(5):
		audit("page%d" % p)
		for i in range(10):
			await step(DOWN, "p%d_down%d" % [p, i], 5)
		await step(R1, "page%d" % (p + 1), 20)
	# Assists: difficulty enum, bool toggle via A and via right
	await step(RIGHT, "difficulty_right", 6)
	await step(A, "difficulty_A", 6)
	await step(DOWN, "abs", 6)
	await step(A, "abs_A", 6)
	await step(LEFT, "abs_left", 6)
	await goto_row("Countersteer")
	await press_n(RIGHT, 12, 3)
	await shot("countersteer_max")
	await step(X, "assists_X", 10)
	# graphics tier
	await press(R1, 10)
	await press(R1, 10)
	await press(R1, 10)
	await shot("graphics")
	await step(RIGHT, "tier_ultra", 10)
	await step(RIGHT, "tier_custom", 10)
	await step(RIGHT, "tier_wrap_low", 10)
	await goto_row("Draw distance")
	await step(RIGHT, "draw_dist_up", 10)
	await goto_row("Quality", UP)
	await shot("tier_after_manual_change")
	await goto_row("Frame rate")
	await step(RIGHT, "fps", 10)
	await press(R1, 10)
	await step(RIGHT, "units_imperial", 10)
	await goto_row("Reduced motion")
	await step(A, "reduced_motion_on", 10)
	await step(L1, "graphics_back", 10)
	await press(R1, 10)
	await step(R1, "wrap_to_assists", 10)
	await step(B, "settings_B", 40)
	log_line("units_metric=%s" % str(Settings.get_value("gameplay", "units_metric")))

func sc_stress() -> void:
	profile_career(["sylph_s2", "rotora_fd"], 60000, 1)
	await load_festival("hub")
	# rapid A on EVENTS: several presses in consecutive frames
	await goto_row("EVENTS")
	for i in range(3):
		tap_raw(A, true)
		await frames(1)
		tap_raw(A, false)
		await frames(1)
	await frames(30)
	await shot("rapid_A_events")
	# rapid B
	for i in range(4):
		tap_raw(B, true)
		await frames(1)
		tap_raw(B, false)
		await frames(1)
	await frames(40)
	await shot("rapid_B")
	await load_festival("hub")
	# A during screen transition: press A then immediately DOWN + A
	await goto_row("GARAGE")
	tap_raw(A, true); await frames(1); tap_raw(A, false)
	tap_raw(A, true); await frames(1); tap_raw(A, false)
	await frames(30)
	await shot("A_A_garage")
	await load_festival("hub")
	# L1/R1/X/Y on hub
	await step(L1, "hub_L1")
	await step(R1, "hub_R1")
	await step(X, "hub_X")
	await step(Y, "hub_Y")
	await step(START, "hub_START")
	# focus lost test: hide + retry nav
	await goto_row("DEALERSHIP")
	await press(A, 40)
	for i in range(20):
		tap_raw(DOWN, true); await frames(1); tap_raw(DOWN, false); await frames(1)
	await frames(20)
	await shot("dealer_rapid_down")
	await load_festival("hub")
	await goto_row("GARAGE")
	await press(A, 40)
	await press(A, 20)
	await press(B, 20)
	await press(B, 20)
	await shot("after_double_B")
	# Hub → Title → rapid A
	await load_festival("hub")
	await press(B, 40)
	await shot("title_from_hub")
	# Screen fade-in slide: B then immediately A on the hub (re-entry during the slide)
	await load_festival("hub")
	await goto_row("SETTINGS")
	for i in range(6):
		tap_raw(A, true); await frames(1); tap_raw(A, false); await frames(1)
		tap_raw(B, true); await frames(1); tap_raw(B, false); await frames(1)
	await frames(60)
	await shot("A_B_spam_settings")
	var t := fest.top()
	if t:
		log_line("top screen position after spam: %s" % str(t.position))
	# Double A in the garage car menu (second A lands on the dialog's first row = DRIVE THIS CAR)
	await load_festival("hub")
	await goto_row("GARAGE")
	await press(A, 40)
	tap_raw(A, true); await frames(1); tap_raw(A, false); await frames(1)
	tap_raw(A, true); await frames(1); tap_raw(A, false)
	await frames(30)
	await shot("car_menu_double_A")

func sc_devtools() -> void:
	profile_career(["sylph_s2"], 30000, 1)
	await load_festival()
	await press(A)
	await goto_row("DEVELOPER")
	await step(A, "launcher", 40)
	await step(B, "launcher_B", 20)
	await key(KEY_ESCAPE)
	await shot("launcher_esc")
	await step(START, "launcher_start", 20)

## Modal focus trap: can focus leave a dialog and reach rows behind it?
func sc_modal() -> void:
	if args.has("part2"):
		await sc_modal2()
		return
	profile_career(["sylph_s2", "rotora_fd"], 60000, 1)
	await load_festival("hub")
	await goto_row("GARAGE")
	await press(A, 40)
	await press(A, 20)
	await shot("car_menu")
	for d in [LEFT, RIGHT, UP, UP, UP, UP, UP, UP, UP, UP]:
		await press(d, 6)
		log_line("modal nav %d -> %s" % [d, focus_desc()])
	await shot("car_menu_after_nav")
	for d in [DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, LEFT, LEFT]:
		await press(d, 6)
		log_line("modal nav %d -> %s" % [d, focus_desc()])
	await shot("car_menu_after_nav2")
	await press(A, 30)
	await shot("A_after_nav")
	# Starter dialog trap
	await load_festival("hub")
	await goto_row("DEALERSHIP")
	await press(A, 40)
	await goto_row("Rotora")
	await press(A, 20)
	for d in [LEFT, LEFT, UP, UP, UP]:
		await press(d, 6)
		log_line("dealer modal nav %d -> %s" % [d, focus_desc()])
	await shot("dealer_modal_nav")

## Realistic double-tap (150 ms apart) on NEW FESTIVAL with a save present.
func sc_erase2() -> void:
	profile_career(["sylph_s2", "rotora_fd"], 99000, 4)
	await load_festival()
	await press(A)
	await goto_row("NEW FESTIVAL")
	await shot("before_double_tap")
	tap_raw(A, true); await secs(0.05); tap_raw(A, false)
	await secs(0.10)
	tap_raw(A, true); await secs(0.05); tap_raw(A, false)
	await secs(0.5)
	await shot("after_double_tap_150ms")
	log_line("after 150ms double tap: garage=%d credits=%d level=%d top=%s" % [Profile.data.garage.size(), int(Profile.data.credits), int(Profile.data.level), top_name()])
	# Android back / WM_GO_BACK while the erase dialog is open on the title
	profile_career(["sylph_s2"], 50000, 2)
	await load_festival()
	await press(A)
	await goto_row("NEW FESTIVAL")
	await press(A, 20)
	fest.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(20)
	await shot("android_back_in_title_dialog")
	log_line("after android back: modal=%s menu_visible=%s focus=%s" % [fest.modal_open(), fest.top()._menu.visible, focus_desc()])

var _max_dt := 0.0
var _hitches := 0
func _process(delta: float) -> void:
	_max_dt = maxf(_max_dt, delta)
	if delta > 0.05:
		_hitches += 1

## Frame hitches while scrolling the dealer (each focus rebuilds the stage car synchronously).
func sc_perf() -> void:
	profile_career(["sylph_s2"], 30000, 1)
	await load_festival("hub")
	await goto_row("DEALERSHIP")
	await press(A, 10)
	await secs(1.5)
	_max_dt = 0.0
	_hitches = 0
	await secs(1.0)
	log_line("idle dealer: max frame %.1f ms, hitches>50ms %d" % [_max_dt * 1000.0, _hitches])
	_max_dt = 0.0
	_hitches = 0
	for i in range(11):
		await press(DOWN, 2)
		await secs(0.4)
	log_line("scrolling dealer (11 cars, 0.4 s each): max frame %.1f ms, hitches>50ms %d" % [_max_dt * 1000.0, _hitches])
	_max_dt = 0.0
	_hitches = 0
	await press(B, 10)
	await goto_row("GARAGE")
	await press(A, 10)
	await press(A, 10)
	await modal_pick("UPGRADES")
	await secs(1.0)
	_max_dt = 0.0
	await press(RIGHT, 2)
	await press(A, 10)
	var t0 := Time.get_ticks_msec()
	await modal_pick("INSTALL")
	log_line("install upgrade: max frame %.1f ms (sync compute_pi + save)" % [_max_dt * 1000.0])

func sc_modal2() -> void:
	profile_career(["sylph_s2", "rotora_fd"], 60000, 1)
	# Title erase dialog: focus escapes to CONTINUE behind the dialog, A continues with dialog open
	await load_festival()
	await press(A)
	await goto_row("NEW FESTIVAL")
	await press(A, 20)
	await press(LEFT, 10)
	log_line("erase dialog after LEFT focus=" + focus_desc())
	await goto_row("CONTINUE", UP, 4)
	log_line("erase dialog after UP focus=" + focus_desc())
	await step(A, "erase_dialog_A_behind", 40)
	log_line("after A behind: modal=%s top=%s modal_rows=%s" % [fest.modal_open(), top_name(), modal_titles()])
	await step(DOWN, "hub_with_modal_down", 10)
	# Now pick ERASE while on the hub
	if fest.modal_open():
		await modal_pick("ERASE", "erase_from_hub")
		await frames(40)
		await shot("erase_from_hub_settled")
		log_line("after erase-from-hub: garage=%d onboarded=%s top=%s" % [Profile.data.garage.size(), Profile.data.onboarded, top_name()])
	# Double-tap A on NEW FESTIVAL: does the second A hit ERASE (default focus)?
	profile_career(["sylph_s2", "rotora_fd"], 99000, 4)
	await load_festival()
	await press(A)
	await goto_row("NEW FESTIVAL")
	tap_raw(A, true); await frames(1); tap_raw(A, false); await frames(3)
	tap_raw(A, true); await frames(1); tap_raw(A, false)
	await frames(30)
	await shot("new_festival_double_A")
	log_line("after double A: garage=%d credits=%d top=%s modal=%s" % [Profile.data.garage.size(), int(Profile.data.credits), top_name(), fest.modal_open()])

## Real joypad buttons only: which face buttons actually activate / go back?
func sc_padcheck() -> void:
	args["raw_pad"] = "1"
	profile_career(["sylph_s2"], 30000, 1)
	await load_festival()
	await step(A, "title_A_opens_menu")
	await step(A, "A_on_continue")
	await step(Y, "Y_on_continue", 40)
	await load_festival("hub")
	await step(A, "hub_A_on_free_roam")
	await goto_row("EVENTS")
	await step(A, "hub_A_on_events", 30)
	await step(Y, "hub_Y_on_events", 30)
	await step(B, "events_pad_B", 30)
	await step(START, "events_pad_START", 30)

## Text scale / reduced motion / imperial layout stress.
func sc_layout() -> void:
	profile_career(["sylph_s2", "raijin_r"], 12_345_678, 12, 3)
	Settings.set_value("gameplay", "units_metric", false)
	await load_festival("hub")
	await shot("hub_big_numbers")
	audit("hub_big")
	await goto_row("GARAGE")
	await step(A, "garage", 40)
	await press(A, 20)
	await goto_row("TUNING")
	await step(A, "tuning", 40)
	audit("tuning_tabs")
	await press(B, 30)
	await press(A, 20)
	await goto_row("UPGRADES")
	await step(A, "upgrades", 40)
	await press_n(R1, 5, 20)
	await shot("swap_tab")
	audit("swap")
