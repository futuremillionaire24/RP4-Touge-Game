class_name RaceManager
extends Node
## Runs one event: builds the route, spawns the grid, countdown, lap/split timing, positions,
## finish detection, rewards and cleanup. Rival cars are appended to NTSim after the player
## (index 0) and removed with truncate_cars(1) when the event ends.

signal race_finished(result: Dictionary)
signal race_aborted

enum State { IDLE, INTRO, COUNTDOWN, RACING, FINISHED, RESULTS }

var world: NTWorld
var sim: NTSim
var player: CarView
var camera: ChaseCamera
var driver: PlayerDriver
var host: Node3D # scene node that owns rival CarViews
var hud: RaceHUD
var event := {}
var route: Route
var state := State.IDLE
var cars: Array[CarView] = [] # [player, rivals...]
var laps := 1
var start_distance := 0.0
var finish_distance := 0.0
var race_time := 0.0
var countdown := 0.0
var finish_times := {} # car_id -> seconds
var finish_order: Array[int] = []
var lap_times := {} # car_id -> Array[float]
var _lap_start := {}
var _last_lap := {}
var best_lap := INF
var splits := PackedInt32Array()
var _split_times := [] # player's split times this lap
var _best_splits := []
var _next_split := 0
var _results_timer := 0.0
var _player_key := ""

func start(p_event: Dictionary) -> void:
	event = p_event
	laps = int(event.get("laps", 1))
	route = Route.from_roads(world, event.roads, event.closed)
	if route.centers.size() < 20:
		push_error("RaceManager: route too short for %s" % event.id)
		race_aborted.emit()
		return
	route.apply_to(sim)
	var rivals: int = event.rivals
	var grid_size := rivals + 1
	# Grid: the player starts at the back on circuits (FH style), second in 1v1 battles.
	var player_slot := 1 if rivals == 1 else grid_size - 1
	var rolling: bool = event.type == EventData.Type.WANGAN_DUEL
	var roll_speed := 25.0 if rolling else 0.0
	sim.reset_car(player.car_id, route.grid_slot(player_slot, grid_size), roll_speed)
	sim.set_assists(player.car_id, Settings.assists_dict())
	cars = [player]
	var keys := _pick_rival_cars(rivals)
	var slot := 0
	for i in range(rivals):
		if slot == player_slot:
			slot += 1
		var key: String = keys[i]
		var id := sim.add_car(key, {}, true, 7000 + i)
		sim.reset_car(id, route.grid_slot(slot, grid_size), roll_speed)
		var difficulty: int = Settings.get_value("assists", "difficulty", 3)
		sim.set_ai_difficulty(id, difficulty)
		var rival := RivalData.get_rival(event.get("rival", "")) if rivals == 1 else {}
		var paint: Material = null
		if not rival.is_empty():
			sim.set_ai_personality(id, rival.personality)
			paint = CarBuilder.paint_material(key, rival.color)
		elif event.type == EventData.Type.TOUGE_BATTLE:
			sim.set_ai_personality(id, {"drift_style": true})
		var view := CarView.new()
		host.add_child(view)
		view.setup(sim, id, key, false, paint)
		cars.append(view)
		slot += 1
	start_distance = route.distance[route.start_index(grid_size)]
	finish_distance = route.length - 20.0 if not route.closed else route.length
	for c in cars:
		lap_times[c.car_id] = []
		_lap_start[c.car_id] = 0.0
		_last_lap[c.car_id] = -1
		sim.reset_progress(c.car_id)
	splits = route.checkpoints(3)
	_best_splits = []
	_split_times = []
	race_time = 0.0
	countdown = 3.9
	state = State.COUNTDOWN
	driver.enabled = false
	for c in cars:
		if c != player:
			sim.set_ai_enabled(c.car_id, false)
		sim.set_input(c.car_id, 0.0, 0.0, 1.0, 1.0, 0.0)
	if rolling:
		countdown = 1.5
	sim.clear_rewind()
	camera.snap()
	hud.begin(self)

func _pick_rival_cars(n: int) -> Array:
	var rival := RivalData.get_rival(event.get("rival", ""))
	if n == 1 and not rival.is_empty():
		return [rival.car]
	var pool := CarData.cars_up_to_class(int(event.get("class_max", 6)))
	pool.erase("ferrari_laferrari") # the championship prize, never a rival
	if player != null:
		var p_car := Profile.current_car()
		var player_pi: int = int(p_car.get("pi", CarData.STOCK_PI.get(player.key, 500)))
		var balanced := pool.filter(func(k):
			var c_pi: int = CarData.STOCK_PI.get(k, 500)
			return absi(c_pi - player_pi) <= 75 or (c_pi <= player_pi + 50 and c_pi >= player_pi - 90)
		)
		if balanced.size() >= 2:
			pool = balanced
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(event.id)
	for i in range(n):
		var idx := mini(pool.size() - 1, int(pow(rng.randf(), 1.6) * pool.size()))
		out.append(pool[idx])
	return out

func progress_of(id: int) -> float:
	var t := sim.get_telemetry(id)
	if route.closed:
		return float(t.progress)
	return float(t.line_distance) - start_distance

func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			countdown -= delta
			hud.countdown_value = countdown
			if countdown <= 0.0:
				_go()
		State.RACING, State.FINISHED:
			race_time += delta
			_track(delta)
			_rubber_band()
			if state == State.FINISHED:
				_results_timer -= delta
				var all_done := finish_order.size() == cars.size()
				if _results_timer <= 0.0 or all_done:
					_show_results()
		State.RESULTS:
			if Pad.pressed("handbrake") or Input.is_action_just_pressed("ui_accept"):
				_end()

func _go() -> void:
	state = State.RACING
	driver.enabled = true
	for c in cars:
		if c != player:
			sim.set_ai_enabled(c.car_id, true)
	hud.countdown_value = -1.0
	Haptics.impact(0.6, 150)

func _track(_delta: float) -> void:
	for c in cars:
		var id := c.car_id
		if finish_times.has(id):
			continue
		var t := sim.get_telemetry(id)
		var done := false
		if route.closed:
			var lap: int = t.lap
			if lap > _last_lap[id]:
				if _last_lap[id] >= 0:
					var lt := race_time - float(_lap_start[id])
					lap_times[id].append(lt)
					if id == player.car_id:
						_on_player_lap(lt)
				_lap_start[id] = race_time
				_last_lap[id] = lap
			done = lap >= laps
		else:
			done = float(t.line_distance) >= finish_distance
		if id == player.car_id:
			_track_splits(t)
		if done:
			finish_times[id] = race_time
			finish_order.append(id)
			if id == player.car_id:
				_on_player_finish()
			elif not route.closed:
				# Past the flag on a point-to-point route: brake to a stop before the road ends.
				sim.set_ai_enabled(id, false)

func _on_player_lap(lt: float) -> void:
	if lt < best_lap:
		best_lap = lt
		_best_splits = _split_times.duplicate()
		hud.flash("BEST LAP  " + RaceHUD.fmt_time(lt), Color(0.3, 1.0, 0.5))
	else:
		hud.flash("LAP  " + RaceHUD.fmt_time(lt), Color.WHITE)
	_split_times = []
	_next_split = 0

func _track_splits(t: Dictionary) -> void:
	if _next_split >= splits.size():
		return
	var idx: int = t.line_index
	if idx >= splits[_next_split] and idx < splits[_next_split] + 40:
		var lap_t := race_time - float(_lap_start[player.car_id])
		_split_times.append(lap_t)
		if _next_split < _best_splits.size():
			hud.split_delta = lap_t - float(_best_splits[_next_split])
			hud.split_timer = 3.0
		_next_split += 1

func _on_player_finish() -> void:
	state = State.FINISHED
	_results_timer = 15.0
	driver.enabled = false
	sim.set_ai(player.car_id, true) # AI brings the player's car home smoothly
	sim.set_ai_difficulty(player.car_id, 1)
	var pos := finish_order.find(player.car_id) + 1
	hud.flash("FINISHED  %s" % RaceHUD.ordinal(pos), Color(1.0, 0.2, 0.55))
	Haptics.impact(0.8, 250)

## Gentle catch-up at lower difficulties only; top difficulties race straight.
func _rubber_band() -> void:
	var difficulty: int = Settings.get_value("assists", "difficulty", 3)
	var strength := clampf((4 - difficulty) / 4.0, 0.0, 1.0) * 0.08
	var p := progress_of(player.car_id)
	for c in cars:
		if c == player:
			continue
		var gap := progress_of(c.car_id) - p # + ahead of player
		var scale := 1.0 - clampf(gap / 300.0, -1.0, 1.0) * strength
		sim.set_ai_speed_scale(c.car_id, scale)

## Current order: finishers first (in finish order), then by progress.
func standings() -> Array[int]:
	var rest: Array[int] = []
	for c in cars:
		if not finish_times.has(c.car_id):
			rest.append(c.car_id)
	rest.sort_custom(func(a, b): return progress_of(a) > progress_of(b))
	var out: Array[int] = finish_order.duplicate()
	out.append_array(rest)
	return out

func position_of(id: int) -> int:
	return standings().find(id) + 1

func _show_results() -> void:
	state = State.RESULTS
	var order := standings()
	var pos := order.find(player.car_id) + 1
	var difficulty: int = clampi(int(Settings.get_value("assists", "difficulty", 3)), 0, 6)
	var mult := 1.0 + 0.12 * float(difficulty)
	var is_time_attack := int(event.get("rivals", 1)) == 0 or cars.size() == 1
	if is_time_attack:
		mult = 1.0 # No AI difficulty bonus for solo time attack
	elif not Settings.get_value("assists", "rewind", true):
		mult += 0.1
	var is_duel := cars.size() <= 2
	var share: float = 1.0
	if pos > 1:
		share = 0.25 if is_duel else ([1.0, 0.6, 0.45, 0.35][mini(pos - 1, 3)] if pos <= 4 else 0.25)
	var credits := int(round(float(event.credits) * share * mult / 100.0) * 100)
	var xp := int(float(event.xp) * (1.0 if pos == 1 else 0.4) * mult)
	var rows := []
	for id in order:
		var view: CarView = null
		for c in cars:
			if c.car_id == id:
				view = c
		rows.append({"id": id, "car": CarData.get_car(view.key).name, "player": id == player.car_id,
			"time": finish_times.get(id, -1.0), "best": (lap_times[id].min() if not lap_times[id].is_empty() else -1.0)})
	var result := {"event": event.id, "position": pos, "cars": cars.size(), "time": finish_times.get(player.car_id, -1.0),
		"best_lap": best_lap if best_lap < INF else -1.0, "credits": credits, "xp": xp, "rows": rows}
	if pos == 1 and event.has("reward_car"):
		var r_car: String = event.reward_car
		if not Profile.owns(r_car):
			Profile.add_car(r_car, "championship")
			hud.toast("CHAMPIONSHIP WON! %s ADDED TO GARAGE!" % CarData.get_car(r_car).name.to_upper(), 4.0)
	hud.show_results(result)
	race_finished.emit(result)

## Quit mid-race (pause menu): no result is recorded.
func abort() -> void:
	if state == State.IDLE:
		return
	race_aborted.emit()
	_end()

func _end() -> void:
	hud.end()
	for c in cars:
		if c != player:
			c.queue_free()
	sim.truncate_cars(1)
	sim.set_ai(player.car_id, false)
	sim.clear_racing_line()
	driver.enabled = true
	state = State.IDLE
	queue_free()
