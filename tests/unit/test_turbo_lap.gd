extends GutTest
## Turbo Lap (M14-02): one-lap kart race — grid spawns, arcade handling,
## drift mini-turbos, boost/item pads, the three items, checkpoint progress,
## finish-order placement, and the timeout progress ranking.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> TurboLap:
	var game := TurboLap.new()
	game.meta = TurboLap.make_meta()
	game.setup(player_slots, 42)
	return game


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


func test_full_lap_finishes_in_order() -> void:
	var game := _game()
	_drive(game, 0, 400)
	var kart: Dictionary = game.karts[0]
	assert_true(bool(kart.finished), "one driven lap crosses the line")
	assert_eq(game.finish_order.size(), 1)
	assert_eq(game.finish_order[0], [0])
	var snap := game.get_snapshot()
	assert_true(int(snap.players[0][TurboLap.PS_BITS]) & 8 > 0, "the finished bit replicates")
	assert_eq(int(snap.standings[0]), 0, "the finisher tops the standings")


func test_all_finished_ends_the_race_with_placements() -> void:
	var game := _game()
	_drive(game, 0, 400)
	_drive(game, 1, 400)
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
