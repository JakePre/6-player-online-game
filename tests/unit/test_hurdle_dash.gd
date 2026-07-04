extends GutTest
## Hurdle Dash (SPEC $7 #8): jump timing over hurdles, stun/knockback on a
## miss, finish order = placement, timeout distance ranking.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> HurdleDash:
	var game := HurdleDash.new()
	game.meta = HurdleDash.make_meta()
	game.setup(player_slots, 42)
	return game


func _run(game: HurdleDash, slot: int) -> void:
	game.handle_input(slot, {"mx": 1.0})


## Ticks with jump inputs timed so `slot` clears every hurdle.
func _sprint_clean(game: HurdleDash, slot: int) -> void:
	_run(game, slot)
	var guard := 0
	while not game._is_done(slot) and not game.finished and guard < 10_000:
		guard += 1
		var next_hurdle := INF
		for hurdle: float in game.hurdles:
			if hurdle - HurdleDash.HURDLE_HALF_DEPTH > float(game.progress[slot]):
				next_hurdle = minf(next_hurdle, hurdle)
		var gap := next_hurdle - HurdleDash.HURDLE_HALF_DEPTH - float(game.progress[slot])
		if gap < HurdleDash.RUN_SPEED * TICK * 2.0:
			game.handle_input(slot, {"jump": true})
			_run(game, slot)
		game.tick(TICK)


func test_meta() -> void:
	var meta := HurdleDash.make_meta()
	assert_eq(meta.id, &"hurdle_dash")
	assert_eq(meta.category, MinigameMeta.Category.SKILL)
	assert_eq(meta.min_players, 2)
	assert_eq(meta.max_players, 24)


func test_registered_in_catalog() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"hurdle_dash") is HurdleDash)
	MinigameCatalog.clear()


func test_course_is_deterministic_from_seed_and_shared() -> void:
	var a := _game()
	var b := _game()
	assert_eq(a.hurdles, b.hurdles, "same seed, same course")
	assert_eq(a.hurdles.size(), HurdleDash.HURDLE_COUNT)
	for hurdle: float in a.hurdles:
		assert_between(hurdle, HurdleDash.FIRST_HURDLE, HurdleDash.LAST_HURDLE)


func test_running_advances_until_a_hurdle_stuns() -> void:
	var game := _game()
	_run(game, 0)
	var first: float = game.hurdles[0]
	var guard := 0
	while float(game.stun_left[0]) <= 0.0 and guard < 1000:
		guard += 1
		game.tick(TICK)
	assert_gt(float(game.stun_left[0]), 0.0, "grounded runner hits the first hurdle")
	assert_lt(float(game.progress[0]), first, "knocked back before the hurdle")


func test_jump_clears_a_hurdle() -> void:
	var game := _game()
	var first: float = game.hurdles[0]
	game.progress[0] = first - HurdleDash.HURDLE_HALF_DEPTH - 0.2
	_run(game, 0)
	game.handle_input(0, {"jump": true})
	game.tick(TICK)
	assert_eq(float(game.stun_left[0]), 0.0)
	assert_gt(float(game.progress[0]), first - HurdleDash.HURDLE_HALF_DEPTH)


func test_no_jumping_while_stunned_or_airborne() -> void:
	var game := _game()
	game.stun_left[0] = HurdleDash.STUN_SEC
	game.handle_input(0, {"jump": true})
	assert_eq(float(game.air_left[0]), 0.0, "stunned runners cannot jump")
	var game2 := _game()
	game2.handle_input(0, {"jump": true})
	game2.tick(TICK)
	var air_before: float = game2.air_left[0]
	game2.handle_input(0, {"jump": true})
	assert_eq(float(game2.air_left[0]), air_before, "no double jump refresh")


func test_stunned_runner_does_not_move() -> void:
	var game := _game()
	game.stun_left[0] = HurdleDash.STUN_SEC
	game.progress[0] = 2.0
	_run(game, 0)
	game.tick(TICK)
	assert_eq(float(game.progress[0]), 2.0)


func test_finish_order_becomes_placements() -> void:
	var game := _game([0, 1, 2] as Array[int])
	_sprint_clean(game, 1)
	assert_false(game.finished, "others still on course")
	_sprint_clean(game, 0)
	game.progress[2] = 5.0
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0], [2]])
	assert_eq(game.get_results().pickup_coins, {})


func test_all_finished_ends_early() -> void:
	var game := _game()
	_sprint_clean(game, 0)
	_sprint_clean(game, 1)
	assert_true(game.finished)
	assert_lt(game.elapsed, game.effective_duration())


func test_timeout_ranks_unfinished_by_distance_with_ties() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game.progress[0] = 10.0
	game.progress[1] = 10.0
	game.progress[2] = 4.0
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0, 1], [2]])


func test_snapshot_shape() -> void:
	var game := _game()
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 2)
	assert_eq(snapshot.players[0].size(), 4)
	assert_eq(snapshot.hurdles.size(), HurdleDash.HURDLE_COUNT)
	assert_eq(snapshot.course_len, HurdleDash.COURSE_LEN)


## No player collision (M15): each runner races their own lane independently
## on the same shared course, so a 24-player race is just 24 independent
## progress trackers advancing off one runner's input.
func test_setup_handles_twenty_four_players() -> void:
	var player_slots: Array[int] = []
	for i in 24:
		player_slots.append(i)
	var game := _game(player_slots)
	assert_eq(game.progress.size(), 24)
	for slot in 24:
		assert_eq(game.progress[slot], 0.0)
	# Slot 0 sprints clean to the finish; everyone else never got a run input,
	# so their progress stays untouched — lanes are fully independent.
	_sprint_clean(game, 0)
	assert_true(game._is_done(0))
	for slot in range(1, 24):
		assert_eq(game.progress[slot], 0.0, "idle runners are unaffected by slot 0's race")
