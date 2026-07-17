extends GutTest
## Bey Brawl (#1034, retires sumo_smash): bowl pull, momentum steering, spin
## as HP/power, clash winner/loser resolution with the aim bias, the per-pair
## clash cooldown, topple + lip ring-out eliminations, and spin-ranked timeout
## placements.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> BeyBrawl:
	var game := BeyBrawl.new()
	game.meta = BeyBrawl.make_meta()
	game.setup(player_slots, 42)
	return game


func test_meta() -> void:
	var meta := BeyBrawl.make_meta()
	assert_eq(meta.id, &"bey_brawl")
	assert_eq(meta.min_players, 2)
	assert_eq(meta.max_players, 8)
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")


func test_registered_in_catalog_and_sumo_smash_retired() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"bey_brawl") is BeyBrawl)
	assert_false(
		MinigameCatalog.registered_ids().has(&"sumo_smash"),
		"the retired game is gone from the catalog"
	)
	MinigameCatalog.clear()


func test_bowl_pull_draws_an_idle_body_inward() -> void:
	var game := _game()
	game.positions[0] = Vector2(6.0, 0.0)
	game.velocities[0] = Vector2.ZERO
	for _i in 30:
		game.tick(TICK)
	assert_lt(float(game.positions[0].length()), 6.0, "the slope drags everyone toward center")


func test_steering_builds_momentum_and_coasts() -> void:
	var game := _game()
	game.positions[0] = Vector2.ZERO  # centered: no bowl pull to muddy the read
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	for _i in 15:
		game.tick(TICK)
	var built := float(game.velocities[0].x)
	assert_gt(built, 2.0, "thrust builds real speed")
	game.handle_input(0, {"mx": 0.0, "my": 0.0})
	game.tick(TICK)
	assert_gt(float(game.velocities[0].x), built * 0.8, "releasing the stick coasts, not stops")


func test_clash_launches_the_slower_body_and_drains_its_spin() -> void:
	var game := _game()
	game.positions[0] = Vector2(0.0, 0.0)
	game.positions[1] = Vector2(0.8, 0.0)
	game.velocities[0] = Vector2(5.0, 0.0)
	game.velocities[1] = Vector2.ZERO
	game.tick(TICK)
	assert_gt(float(game.velocities[1].x), 5.0, "the loser is launched hard along the axis")
	assert_almost_eq(
		float(game.spins[1]), 1.0 - BeyBrawl.CLASH_SPIN_COST_LOSER, 0.01, "loser pays the big cost"
	)
	assert_almost_eq(
		float(game.spins[0]),
		1.0 - BeyBrawl.CLASH_SPIN_COST_WINNER,
		0.01,
		"winner pays the small one"
	)
	assert_eq(int(game.clash_seq[0]), 1, "both bodies register the clash for view FX")
	assert_eq(int(game.clash_seq[1]), 1)


func test_winner_steer_bends_the_losers_launch() -> void:
	var game := _game()
	game.positions[0] = Vector2(0.0, 0.0)
	game.positions[1] = Vector2(0.8, 0.0)
	game.velocities[0] = Vector2(5.0, 0.0)
	game.velocities[1] = Vector2.ZERO
	game.handle_input(0, {"mx": 0.0, "my": 1.0})  # winner aims the collision sideways
	game.tick(TICK)
	assert_gt(float(game.velocities[1].y), 1.0, "the aim bias bends where the loser flies")


func test_pair_clash_cooldown_prevents_per_tick_pileup() -> void:
	var game := _game()
	game.positions[0] = Vector2(0.0, 0.0)
	game.positions[1] = Vector2(0.5, 0.0)
	game.velocities[0] = Vector2(3.0, 0.0)
	game.tick(TICK)
	assert_eq(int(game.clash_seq[0]), 1, "first overlap clashes")
	# Force them back into overlap immediately: still inside the pair cooldown.
	game.positions[0] = Vector2(0.0, 0.0)
	game.positions[1] = Vector2(0.5, 0.0)
	game.tick(TICK)
	assert_eq(int(game.clash_seq[0]), 1, "no re-clash inside the cooldown window")


func test_zero_spin_topples() -> void:
	var game := _game([0, 1, 2])
	game.spins[0] = 0.0
	game.tick(TICK)
	assert_eq(game._elim.order, [[0]], "out of spin = toppled out")
	assert_false(game.finished, "two still spinning")


func test_slow_lip_crossing_slides_back_in() -> void:
	var game := _game()
	game.positions[0] = Vector2(BeyBrawl.BOWL_RADIUS + 0.5, 0.0)
	game.velocities[0] = Vector2(2.0, 0.0)  # well under LIP_ESCAPE_SPEED
	game.tick(TICK)
	assert_eq(game._elim.order, [], "a slow drift over the lip is caught")
	assert_lte(
		float(game.positions[0].length()), BeyBrawl.BOWL_RADIUS + 0.001, "clamped back onto the rim"
	)


func test_fast_lip_crossing_rings_out() -> void:
	var game := _game([0, 1, 2])
	game.positions[0] = Vector2(BeyBrawl.BOWL_RADIUS + 0.5, 0.0)
	game.velocities[0] = Vector2(BeyBrawl.LIP_ESCAPE_SPEED + 4.0, 0.0)
	game.tick(TICK)
	assert_eq(game._elim.order, [[0]], "launched clean over the lip = out")


func test_last_one_spinning_ends_the_round() -> void:
	var game := _game()
	game.spins[1] = 0.0
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0], [1]])


func test_timeout_ranks_survivors_by_remaining_spin() -> void:
	var game := _game([0, 1, 2])
	game.duration_override = TICK * 2.0
	game.spins[0] = 0.9
	game.spins[1] = 0.2
	game.spins[2] = 0.5
	# Park everyone apart so no clash muddies the meters before the buzzer.
	game.positions[0] = Vector2(0.0, -4.0)
	game.positions[1] = Vector2(4.0, 4.0)
	game.positions[2] = Vector2(-4.0, 4.0)
	game.tick(TICK)
	game.tick(TICK)
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0], [2], [1]], "healthier spin places higher")


func test_snapshot_shape_and_junk_input() -> void:
	var game := _game()
	game.handle_input(0, {})  # junk-tolerant like every sim post-#970
	var snap := game.get_snapshot()
	assert_eq(float(snap.radius), BeyBrawl.BOWL_RADIUS)
	assert_eq((snap.players as Dictionary).size(), 2)
	var row: Array = snap.players[0]
	assert_eq(row.size(), BeyBrawl.PS_COUNT, "[x, y, spin, clash_seq]")
	assert_almost_eq(float(row[BeyBrawl.PS_SPIN]), 1.0, 0.01)
	assert_eq(snap.out, [])
