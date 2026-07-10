extends GutTest
## Dodgeball (#791, retires ro_sham_bo): grab/throw/hit/catch resolution, the
## catch-beats-hit window, self- and friendly-fire exemptions, court-line clamp
## in team mode, elimination ordering as placement, and endgame ranking.

const TICK := 1.0 / 30.0


func _ffa_game(player_slots: Array[int] = [0, 1]) -> Dodgeball:
	var game := Dodgeball.new()
	game.meta = Dodgeball.make_meta()
	game.setup(player_slots, 42)
	return game


func _team_game(player_slots: Array[int] = [0, 1, 2, 3]) -> Dodgeball:
	var game := Dodgeball.new()
	game.meta = Dodgeball.make_meta()
	game.setup(player_slots, 7)
	return game


func _held_ball(holder: int, pos: Vector2) -> Dictionary:
	return {
		"pos": pos,
		"vel": Vector2.ZERO,
		"state": Dodgeball.BallState.HELD,
		"holder": holder,
		"thrower": -1
	}


func _flying_ball(thrower: int, pos: Vector2, vel: Vector2) -> Dictionary:
	return {
		"pos": pos,
		"vel": vel,
		"state": Dodgeball.BallState.FLYING,
		"holder": thrower,
		"thrower": thrower
	}


func _loose_ball(pos: Vector2) -> Dictionary:
	return {
		"pos": pos,
		"vel": Vector2.ZERO,
		"state": Dodgeball.BallState.LOOSE,
		"holder": -1,
		"thrower": -1
	}


func test_meta() -> void:
	var meta := Dodgeball.make_meta()
	assert_eq(meta.id, &"dodgeball")
	assert_eq(meta.min_players, 2)
	assert_eq(meta.max_players, 12)
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")


func test_registered_in_catalog_and_ro_sham_bo_retired() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"dodgeball") is Dodgeball)
	assert_false(
		MinigameCatalog.registered_ids().has(&"ro_sham_bo"),
		"the retired game is gone from the catalog"
	)
	MinigameCatalog.clear()


func test_ffa_below_four_players() -> void:
	var game := _ffa_game([0, 1, 2])
	assert_false(game.team_mode, "2-3 players is free-for-all")
	assert_true(game.teams.is_empty())
	assert_eq(game.positions.size(), 3)


func test_team_split_at_four_players() -> void:
	var game := _team_game([0, 1, 2, 3])
	assert_true(game.team_mode)
	assert_eq(game.team_count, 2)
	assert_eq(game.teams.size(), 2)
	# Team 0 starts on -x, team 1 on +x.
	for slot: int in game.teams[0]:
		assert_lt(float(game.positions[slot].x), 0.0, "team 0 starts left")
	for slot: int in game.teams[1]:
		assert_gt(float(game.positions[slot].x), 0.0, "team 1 starts right")


func test_center_balls_spawn_on_the_line() -> void:
	var game := _ffa_game([0, 1])
	assert_gt(game.balls.size(), 0, "at least one ball is seeded")
	for ball: Dictionary in game.balls:
		assert_almost_eq(float((ball.pos as Vector2).x), 0.0, 0.001, "seeded on the center line")


func test_walking_over_a_loose_ball_grabs_it() -> void:
	var game := _ffa_game([0, 1])
	game.balls = [_loose_ball(Vector2(0.0, 0.0))]
	game.positions[0] = Vector2(0.0, 0.0)
	game.move_dirs[0] = Vector2.ZERO
	game._tick(TICK)
	assert_eq(int(game.balls[0].state), Dodgeball.BallState.HELD)
	assert_eq(int(game.balls[0].holder), 0)


func test_throw_launches_the_ball_along_facing() -> void:
	var game := _ffa_game([0, 1])
	game.positions[0] = Vector2(-3.0, 0.0)
	game.facings[0] = Vector2(1.0, 0.0)
	game.balls = [_held_ball(0, game.positions[0])]
	game.handle_input(0, {"act": true})
	assert_eq(int(game.balls[0].state), Dodgeball.BallState.FLYING)
	assert_almost_eq(float(game.balls[0].vel.x), Dodgeball.THROW_SPEED, 0.01)


func test_a_hit_eliminates_the_target() -> void:
	var game := _ffa_game([0, 1])
	game.positions[0] = Vector2(-5.0, 0.0)
	game.positions[1] = Vector2(5.0, 0.0)
	game.balls = [_flying_ball(0, Vector2(5.0, 0.0), Vector2(0.1, 0.0))]
	game._tick(TICK)
	assert_false(game._is_in(1), "the struck player is out")
	assert_eq(int(game.balls[0].state), Dodgeball.BallState.LOOSE, "the ball drops loose")


func test_a_timed_catch_reflects_onto_the_thrower() -> void:
	var game := _ffa_game([0, 1])
	game.positions[0] = Vector2(-5.0, 0.0)
	game.positions[1] = Vector2(5.0, 0.0)
	# Ball inside the catch band (1.0) but outside the hit band (0.75), moving slow.
	game.balls = [_flying_ball(0, Vector2(4.0, 0.0), Vector2(0.1, 0.0))]
	game.catch_until[1] = game.elapsed + 1.0
	game._tick(TICK)
	assert_false(game._is_in(0), "the thrower is out — the catch reflected it")
	assert_true(game._is_in(1), "the catcher survives")


func test_without_a_catch_the_ball_reaches_the_hit_band() -> void:
	var game := _ffa_game([0, 1])
	game.positions[1] = Vector2(5.0, 0.0)
	# Same catch-band distance, but no buffered attempt — it carries into a hit.
	game.balls = [_flying_ball(0, Vector2(5.0, 0.0), Vector2(0.1, 0.0))]
	game._tick(TICK)
	assert_false(game._is_in(1), "no catch buffer, so the hit lands")


func test_a_ball_never_hits_its_own_thrower() -> void:
	var game := _ffa_game([0, 1])
	game.positions[0] = Vector2(0.0, 0.0)
	game.positions[1] = Vector2(9.0, 9.0)  # far away
	game.balls = [_flying_ball(0, Vector2(0.0, 0.0), Vector2(0.1, 0.0))]
	game._tick(TICK)
	assert_true(game._is_in(0), "the thrower is immune to their own throw")


func test_team_mode_spares_teammates() -> void:
	var game := _team_game([0, 1, 2, 3])
	var thrower: int = game.teams[0][0]
	var mate: int = game.teams[0][1]
	game.positions[mate] = Vector2(-4.0, 0.0)
	game.balls = [_flying_ball(thrower, Vector2(-4.0, 0.0), Vector2(0.1, 0.0))]
	game._tick(TICK)
	assert_true(game._is_in(mate), "friendly fire doesn't eliminate a teammate")


func test_court_line_clamps_teams_to_their_half() -> void:
	var game := _team_game([0, 1, 2, 3])
	var slot: int = game.teams[0][0]
	game.move_dirs[slot] = Vector2(1.0, 0.0)  # shove toward the enemy side
	for _i in 120:
		game._tick(TICK)
	assert_lte(
		float(game.positions[slot].x), -Dodgeball.CENTER_GAP + 0.01, "team 0 can't cross the line"
	)


func test_ffa_elimination_order_is_reverse_placement() -> void:
	var game := _ffa_game([0, 1, 2])
	game._pending_falls = [1]
	game._flush_falls()
	game._pending_falls = [2]
	game._flush_falls()
	# 0 survives; 2 fell last (2nd), 1 fell first (3rd).
	var placements: Array = game._rank_players()
	assert_eq(placements[0], [0], "the survivor wins")
	assert_eq(placements[1], [2], "last out places above earlier outs")
	assert_eq(placements[2], [1])


func test_last_player_standing_ends_the_game() -> void:
	var game := _ffa_game([0, 1])
	game._pending_falls = [1]
	game._flush_falls()
	game._check_end()
	assert_true(game.finished)
	assert_eq(game.get_results().placements[0], [0])


func test_team_wipeout_ends_with_the_team_tables() -> void:
	var game := _team_game([0, 1, 2, 3])
	for slot: int in game.teams[1]:
		game._pending_falls.append(slot)
	game._flush_falls()
	game._check_end()
	assert_true(game.finished)
	var placements: Array = game.get_results().placements
	assert_eq(placements[0], game.teams[0], "the surviving team is ranked first")
	assert_true(game.get_results().team_mode)


func test_balls_escalate_over_time() -> void:
	var game := _ffa_game([0, 1])
	var before := game.balls.size()
	game.elapsed = Dodgeball.EXTRA_BALL_SEC + 0.1
	game._tick_ball_spawn()
	assert_eq(game.balls.size(), before + 1, "an extra ball drops in to break stalls")


func test_snapshot_shape() -> void:
	var game := _team_game([0, 1, 2, 3])
	var snap := game.get_snapshot()
	assert_true(snap.has("players") and snap.has("balls") and snap.has("teams"))
	assert_true(snap.has("team_mode") and snap.has("half") and snap.has("fallen"))
	var any_slot: int = game.slots[0]
	assert_eq((snap.players[any_slot] as Array).size(), Dodgeball.PS_COUNT)
	if not (snap.balls as Array).is_empty():
		assert_eq((snap.balls[0] as Array).size(), Dodgeball.BL_COUNT)
