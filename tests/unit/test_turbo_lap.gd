extends GutTest
## Turbo Lap (M14-02): a LAP_COUNT-lap kart race — grid spawns, arcade handling,
## drift mini-turbos, boost/item pads, the three items, checkpoint progress,
## finish-order placement, and the timeout progress ranking.

const TICK := 1.0 / 30.0
## #961 anti-collapse floor: a full 3-lap bot race must run far longer than the
## old ~8s one-lap wipe. See the guard test below.
const MIN_RACE_SEC := 12.0


func _game(player_slots: Array[int] = [0, 1]) -> TurboLap:
	var game := TurboLap.new()
	game.meta = TurboLap.make_meta()
	game.setup(player_slots, 42)
	return game


func _run_bot_round(count: int, seed_value: int) -> Dictionary:
	var game := TurboLap.new()
	game.meta = TurboLap.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, seed_value)
	var brains := {}
	for slot: int in game.slots:
		brains[slot] = BotBrains.brain_for(&"turbo_lap", slot, seed_value)
	var t := 0.0
	while not game.finished and t < game.meta.duration_sec:
		var match_state := {"game": game.get_snapshot()}
		for slot: int in game.slots:
			game.handle_input(slot, brains[slot].think(match_state, {}))
		game.tick(TICK)
		t += TICK
	var caps: Array = []
	for slot: int in game.slots:
		caps.append(int(game.karts[slot].captured))
	return {"t": t, "caps": caps, "finished": game.finished, "winner_slot0": game.finish_order}


## #961: turbo_lap's telemetry collapse (8s vs 90s) was the pre-#785 ONE-lap
## race; the #785 course rebuild made it LAP_COUNT (3) laps, and a full bot field
## now runs a real ~18-41s race that finishes by crossing the line, not by
## timeout. This locks that in — every kart completes all three laps and the race
## lasts far longer than the old ~8s one-lap wipe. (The remaining gap to the
## #933 40%-of-meta bar is the generous 90s TIMEOUT, not a collapse — a race is
## meant to finish before its clock; flagged on the issue for a meta trim.)
func test_bot_rounds_run_a_full_three_lap_race() -> void:
	var need := TurboLap.WAYPOINT_COUNT * TurboLap.LAP_COUNT
	for count: int in [2, 4, 6]:
		for seed_value: int in [1, 2, 3]:
			var r := _run_bot_round(count, seed_value)
			assert_true(r.finished, "%d bots (seed %d): race finishes" % [count, seed_value])
			for caps: int in r.caps:
				assert_eq(caps, need, "every kart completes all %d laps" % TurboLap.LAP_COUNT)
			assert_gt(r.t, MIN_RACE_SEC, "runs a real race, not the old ~8s one-lap collapse")


## Test chauffeur: aims the kart straight at its next waypoint each tick and
## holds the gas, so lap tests exercise capture/finish without depending on
## steering-rate tuning (steering has its own test).
func _drive(game: TurboLap, slot: int, ticks: int) -> void:
	var points := TurboLap.waypoints()
	for _i in ticks:
		if game.finished:
			return
		var kart: Dictionary = game.karts[slot]
		var target: Vector2 = points[int(kart.next_wp) % TurboLap.WAYPOINT_COUNT]
		kart.heading = ((target - (kart.pos as Vector2)) as Vector2).angle()
		game.handle_input(slot, {"mx": 0.0, "my": -1.0})
		game.tick(TICK)


func test_meta_and_catalog() -> void:
	var meta := TurboLap.make_meta()
	assert_eq(meta.id, &"turbo_lap")
	assert_eq(meta.max_players, 12)
	assert_false(meta.controls_text.is_empty())
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"turbo_lap") is TurboLap)
	MinigameCatalog.clear()


func test_grid_spawns_behind_the_line_facing_the_course() -> void:
	var game := _game([0, 1, 2, 3] as Array[int])
	var points := TurboLap.waypoints()
	var tangent := (points[1] - points[0]).normalized()
	for slot in [0, 1, 2, 3]:
		var kart: Dictionary = game.karts[slot]
		assert_lt((kart.pos as Vector2).distance_to(points[0]), 6.0, "near the start line")
		assert_almost_eq(float(kart.heading), tangent.angle(), 0.001, "facing down the course")
	var row_two: Vector2 = game.karts[3].pos
	var row_one: Vector2 = game.karts[0].pos
	assert_gt(row_one.distance_to(points[0]), 0.0)
	assert_gt(row_two.distance_to(points[0]), row_one.distance_to(points[0]), "rows stack back")


func test_throttle_accelerates_and_steering_turns() -> void:
	var game := _game()
	game.handle_input(0, {"mx": 0.0, "my": -1.0})
	for _i in 30:
		game.tick(TICK)
	assert_gt(float(game.karts[0].speed), 5.0, "a second of gas gets moving")
	var heading_before := float(game.karts[0].heading)
	game.handle_input(0, {"mx": 1.0, "my": -1.0})
	for _i in 10:
		game.tick(TICK)
	assert_gt(float(game.karts[0].heading), heading_before, "steering right turns right")


func test_spin_out_locks_control_and_bleeds_speed() -> void:
	var game := _game()
	var kart: Dictionary = game.karts[0]
	kart.speed = 8.0
	game._spin_out(kart)
	game.handle_input(0, {"mx": 0.0, "my": -1.0})
	for _i in 6:
		game.tick(TICK)
	assert_lt(float(kart.speed), 8.0, "the gas pedal does nothing mid-spin")
	assert_gt(float(kart.spin_left), 0.0)


## #1067 (owner playtest): the pad gas button — held action_primary is full
## throttle no matter what the stick's y does, and release falls back to it.
func test_gas_button_overrides_stick_throttle() -> void:
	var game := _game()
	var kart: Dictionary = game.karts[0]
	game.handle_input(0, {"gas": true})
	game.handle_input(0, {"mx": 0.5, "my": 0.0})
	assert_almost_eq(float(kart.throttle), 1.0, 0.001, "gas held = full throttle, stick idle")
	game.handle_input(0, {"mx": 0.5, "my": 1.0})
	assert_almost_eq(float(kart.throttle), 1.0, 0.001, "gas beats stick-down while held")
	game.handle_input(0, {"gas": false})
	game.handle_input(0, {"mx": 0.5, "my": 1.0})
	assert_almost_eq(float(kart.throttle), -1.0, 0.001, "release = stick brake works again")


## #1067: with gas on the button, slamming the stick sideways at speed IS the
## drift — no third button. A gentle line does not drift.
func test_hard_turn_at_speed_drifts_while_gassing() -> void:
	var game := _game()
	var kart: Dictionary = game.karts[0]
	kart.speed = 8.0
	game.handle_input(0, {"gas": true})
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	assert_true(game._is_drifting(kart), "gas + full deflection at speed = drift")
	game.handle_input(0, {"mx": 0.5, "my": 0.0})
	assert_false(game._is_drifting(kart), "a moderate line is grip, not drift")
	game.handle_input(0, {"gas": false})
	game.handle_input(0, {"mx": 1.0, "my": -1.0})
	assert_false(game._is_drifting(kart), "no gas, no explicit drift input -> no drift")


func test_drift_release_banks_a_mini_turbo() -> void:
	var game := _game()
	var kart: Dictionary = game.karts[0]
	kart.speed = 8.0
	game.handle_input(0, {"mx": 1.0, "my": -1.0})
	game.handle_input(0, {"drift": true})
	for _i in 20:  # ~0.66 s of held drift > DRIFT_BOOST_AT
		kart.speed = 8.0  # keep it fast enough to hold the drift
		game.tick(TICK)
	assert_gt(float(kart.drift_charge), TurboLap.DRIFT_BOOST_AT, "charge builds while held")
	game.handle_input(0, {"drift": false})
	game.tick(TICK)
	assert_gt(float(kart.boost_left), 0.0, "releasing the drift cashes the boost")


func test_boost_pad_grants_a_boost() -> void:
	var game := _game()
	var kart: Dictionary = game.karts[0]
	kart.pos = TurboLap.boost_pad_positions()[0]
	kart.speed = 1.0
	game.tick(TICK)
	assert_gt(float(kart.boost_left), 0.0, "driving the pad boosts")


func test_item_pad_grants_one_item_then_cools_down() -> void:
	var game := _game()
	var kart: Dictionary = game.karts[0]
	kart.pos = TurboLap.item_pad_positions()[0]
	game.tick(TICK)
	assert_ne(int(kart.item), TurboLap.ITEM_NONE, "the pad hands out an item")
	var rival: Dictionary = game.karts[1]
	rival.pos = TurboLap.item_pad_positions()[0]
	game.tick(TICK)
	assert_eq(int(rival.item), TurboLap.ITEM_NONE, "a fresh-taken pad is cooling down")
	var snap := game.get_snapshot()
	assert_eq(int(snap.pads[0][2]), 0, "the cooldown replicates")


func test_oil_slick_spins_a_pursuer_but_spares_its_owner() -> void:
	var game := _game()
	var owner_kart: Dictionary = game.karts[0]
	owner_kart.item = TurboLap.ITEM_OIL
	owner_kart.pos = Vector2(11.0, 0.5)
	game.handle_input(0, {"use": true})
	assert_eq(game.oils.size(), 1, "the slick drops behind")
	game.tick(TICK)
	assert_eq(float(owner_kart.spin_left), 0.0, "the dropper is immune while fleeing")
	var victim: Dictionary = game.karts[1]
	victim.pos = game.oils[0].pos
	game.tick(TICK)
	assert_gt(float(victim.spin_left), 0.0, "the pursuer hits the slick and spins")


func test_shell_hunts_the_kart_ahead() -> void:
	var game := _game()
	var ahead: Dictionary = game.karts[1]
	ahead.captured = 4
	ahead.next_wp = 5
	ahead.pos = TurboLap.waypoints()[4]
	var firer: Dictionary = game.karts[0]
	firer.item = TurboLap.ITEM_SHELL
	game.handle_input(0, {"use": true})
	assert_eq(game.shells.size(), 1, "the shell launches")
	assert_eq(int(game.shells[0].target), 1, "hunting the kart directly ahead")
	for _i in 60:
		game.tick(TICK)
		if game.shells.is_empty():
			break
	assert_eq(game.shells.size(), 0, "the shell connected and is gone")
	assert_gt(float(ahead.spin_left), 0.0, "the victim is mid-spin the tick it lands")


func test_leaders_shell_fizzles() -> void:
	var game := _game()
	var leader: Dictionary = game.karts[0]
	leader.captured = 4
	leader.next_wp = 5
	leader.item = TurboLap.ITEM_SHELL
	game.handle_input(0, {"use": true})
	assert_eq(game.shells.size(), 0, "no one ahead — nothing to hunt")
	assert_eq(int(leader.item), TurboLap.ITEM_NONE, "the item is still spent")


func test_grass_is_slower_than_track() -> void:
	var game := _game()
	var kart: Dictionary = game.karts[0]
	kart.pos = Vector2.ZERO  # dead center: infield grass
	game.handle_input(0, {"mx": 0.0, "my": -1.0})
	for _i in 45:
		kart.pos = Vector2.ZERO  # stay on grass regardless of motion
		game.tick(TICK)
	assert_lte(
		float(kart.speed), TurboLap.MAX_SPEED * TurboLap.OFFTRACK_GRIP + 0.1, "grass caps the speed"
	)


## #1041: the track edges are solid walls now — a racing kart shoved past the
## ±TRACK_HALF_WIDTH ribbon is clamped back onto it, not driven through.
func test_a_racing_kart_is_walled_onto_the_track() -> void:
	var game := _game()
	var kart: Dictionary = game.karts[0]
	# Deep in the infield, well inside the loop and past the inner wall.
	kart.pos = Vector2.ZERO
	kart.speed = 0.0
	game.tick(TICK)
	var dist := SimGeometry.distance_to_polyline(kart.pos, TurboLap.waypoints(), true)
	assert_lte(dist, TurboLap.TRACK_HALF_WIDTH + 0.001, "the wall pulls it back onto the ribbon")


## A finished kart eases to a pit slot that deliberately sits outside the ribbon,
## so the wall must not trap it on the track (#1041).
func test_a_finished_kart_may_leave_the_ribbon_for_its_pit() -> void:
	var game := _game()
	game.karts[0].finished = true
	game.finish_order = [[0]]
	for _i in 120:
		game.tick(TICK)
	var pit := game._pit_slot(0)
	assert_almost_eq(float(game.karts[0].pos.x), pit.x, 0.5, "reaches its pit outside the ribbon")
	assert_almost_eq(float(game.karts[0].pos.y), pit.y, 0.5)


func test_full_race_finishes_in_order() -> void:
	var game := _game()
	_drive(game, 0, 1600)  # enough to complete every lap
	var kart: Dictionary = game.karts[0]
	assert_true(bool(kart.finished), "driving the whole race crosses the line")
	assert_eq(game.finish_order.size(), 1)
	assert_eq(game.finish_order[0], [0])
	var snap := game.get_snapshot()
	assert_true(int(snap.players[0][TurboLap.PS_BITS]) & 8 > 0, "the finished bit replicates")
	assert_eq(int(snap.standings[0]), 0, "the finisher tops the standings")


## #930: a finished kart used to coast dead-ahead on whatever heading it
## crossed the line with, sometimes carrying it off-track into the infield.
## It now eases into a parking slot beside the start line and stops there.
func test_finished_kart_parks_in_its_pit_slot() -> void:
	var game := _game()
	_drive(game, 0, 1600)  # enough to finish, then coast all the way to the pit
	var kart: Dictionary = game.karts[0]
	assert_true(bool(kart.finished))
	var target: Vector2 = game._pit_slot(0)
	assert_lt(
		(kart.pos as Vector2).distance_to(target),
		TurboLap.PIT_ARRIVE_RADIUS + 0.01,
		"parks at its pit slot"
	)
	assert_almost_eq(float(kart.speed), 0.0, 0.01, "comes to a stop once parked")
	assert_false(game._on_track(target), "the pit row sits off the racing line")


func test_pit_slots_are_distinct_per_finish_rank() -> void:
	var game := _game()
	var first: Vector2 = game._pit_slot(0)
	var second: Vector2 = game._pit_slot(1)
	assert_gt(first.distance_to(second), 1.0, "each finisher gets a distinct parking spot")


func test_all_finished_ends_the_race_with_placements() -> void:
	var game := _game()
	_drive(game, 0, 1600)
	_drive(game, 1, 1600)
	assert_true(game.finished, "everyone home ends the round early")
	var results := game.get_results()
	assert_eq(results.placements[0], [0], "first across the line wins")
	assert_eq(results.placements[1], [1])


func test_timeout_ranks_by_lap_progress() -> void:
	var game := _game()
	game.duration_override = 0.2
	var leader: Dictionary = game.karts[1]
	leader.captured = 5
	leader.next_wp = 6
	leader.pos = TurboLap.waypoints()[5]
	for _i in 10:
		game.tick(TICK)
	assert_true(game.finished, "the clock ran out")
	assert_eq(game.get_results().placements[0], [1], "further along ranks higher")


## #785: the race is more than one lap now — finishing takes a full LAP_COUNT
## passes around the waypoint loop, not a single circuit.
func test_race_is_multiple_laps() -> void:
	assert_gte(TurboLap.LAP_COUNT, 2, "more than one lap")
	var game := _game()
	var kart: Dictionary = game.karts[0]
	# One lap's worth of captures is not a finish...
	kart.captured = TurboLap.WAYPOINT_COUNT
	kart.next_wp = TurboLap.WAYPOINT_COUNT
	kart.pos = TurboLap.waypoints()[0]
	game.tick(TICK)
	assert_false(bool(kart.finished), "one lap is not the whole race")
	# ...the final lap's last waypoint is.
	kart.captured = TurboLap.WAYPOINT_COUNT * TurboLap.LAP_COUNT - 1
	kart.next_wp = TurboLap.WAYPOINT_COUNT * TurboLap.LAP_COUNT
	kart.pos = TurboLap.waypoints()[
		(TurboLap.WAYPOINT_COUNT * TurboLap.LAP_COUNT) % TurboLap.WAYPOINT_COUNT
	]
	game.tick(TICK)
	assert_true(bool(kart.finished), "the last lap's final checkpoint ends the race")


## #785: the shaped course is a valid closed loop — waypoints are distinct,
## evenly-ish spaced, and advance monotonically around the center (so the ribbon
## never crosses itself), while reaching past the base ellipse (varied corners).
func test_shaped_course_is_a_valid_loop() -> void:
	var points := TurboLap.waypoints()
	assert_eq(points.size(), TurboLap.WAYPOINT_COUNT)
	var reaches_past_base := false
	var last_angle: float = points[0].angle()
	var turned := 0.0
	for i in points.size():
		var here: Vector2 = points[i]
		var next: Vector2 = points[(i + 1) % points.size()]
		assert_gt(here.distance_to(next), 0.5, "no doubled-up waypoints")
		if absf(here.x) > TurboLap.TRACK_RX or absf(here.y) > TurboLap.TRACK_RY:
			reaches_past_base = true
		# Accumulated turn should be one clean revolution (monotonic winding =
		# no self-intersection).
		var step := wrapf(next.angle() - last_angle, -PI, PI)
		assert_gt(step, 0.0, "waypoints wind one consistent direction")
		turned += step
		last_angle = next.angle()
	assert_almost_eq(turned, TAU, 0.001, "exactly one loop")
	assert_true(reaches_past_base, "the shaped course bulges past a plain ellipse")


func test_snapshot_shape_and_junk_input() -> void:
	var game := _game()
	game.handle_input(0, {"bogus": 1})
	game.handle_input(9, {"mx": 1.0})
	game.handle_input(0, {"use": true})
	game.tick(TICK)
	var snap := game.get_snapshot()
	for key in ["players", "shells", "oils", "pads", "standings"]:
		assert_true(snap.has(key), "%s replicates" % key)
	assert_eq((snap.players[0] as Array).size(), TurboLap.PS_COUNT)
	assert_eq((snap.pads as Array).size(), 3)
	assert_eq((snap.standings as Array).size(), 2)
