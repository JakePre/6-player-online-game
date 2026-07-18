extends GutTest
## Storm Court (#936, finale variant build 1): the dodgeball royale — shop
## loadouts, facing throws that strip lives, the two-life catch swing,
## sabotage sky-strikes, hit protection, the staged court shrink, royale
## elimination and the Gauntlet-shaped ranking FinaleRanking consumes.

const TICK := 1.0 / 30.0


func _game(count: int = 3) -> StormCourt:
	var game := StormCourt.new()
	game.meta = StormCourt.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 42)
	# Tests drive hits explicitly — clear the whistle protection window.
	game._invuln_left.clear()
	return game


## Faces `thrower` at `victim` point-blank with a held ball, both unprotected.
func _arm_and_square(game: StormCourt, thrower: int, victim: int) -> Dictionary:
	game.positions[thrower] = Vector2(0.0, 0.0)
	game.positions[victim] = Vector2(2.0, 0.0)
	var ball: Dictionary = game.balls[0]
	ball.state = StormCourt.BallState.HELD
	ball.holder = thrower
	game.facings[thrower] = Vector2.RIGHT
	game.move_dirs[thrower] = Vector2.ZERO
	return ball


func _fly_until_resolved(game: StormCourt, ball: Dictionary) -> void:
	for _i in 60:
		if int(ball.state) != StormCourt.BallState.FLYING:
			return
		game.tick(TICK)


func test_loadouts_apply_on_top_of_the_base_kit() -> void:
	var game := _game()
	game.apply_loadouts(
		{0: {"items": {&"extra_life": 2, &"shield": 1, &"speed_boost": 1, &"sabotage_token": 1}}}
	)
	assert_eq(game.lives[0], 3, "1 base + 2 bought")
	assert_true(game.shields[0])
	assert_true(game.speed_boosts[0])
	assert_eq(game.sabotage_tokens[0], 1)
	assert_eq(game.lives[1], 1, "absent slots keep the base kit")


func test_throw_hit_strips_a_life_and_shield_shrugs_first() -> void:
	var game := _game()
	game.lives[1] = 2
	game.shields[1] = true
	var ball := _arm_and_square(game, 0, 1)
	game.handle_input(0, {"act": true})
	assert_eq(int(ball.state), StormCourt.BallState.FLYING, "held ball throws")
	_fly_until_resolved(game, ball)
	assert_eq(game.lives[1], 2, "the shield shrugs the first hit")
	assert_false(game.shields[1], "and is spent")
	game._invuln_left.clear()  # past the hit-protection window
	ball = _arm_and_square(game, 0, 1)
	game.handle_input(0, {"act": true})
	_fly_until_resolved(game, ball)
	assert_eq(game.lives[1], 1, "the second hit strips a life")


## #936, the owner-locked hook: a catch swings TWO — thrower loses a life,
## catcher gains one and holds the ball.
func test_catch_swings_two_lives() -> void:
	var game := _game()
	game.lives[0] = 2
	game.lives[1] = 1
	var ball := _arm_and_square(game, 0, 1)
	game.handle_input(0, {"act": true})
	# The victim buffers the catch while the ball is inbound.
	game.catch_until[1] = game.elapsed + 60.0
	_fly_until_resolved(game, ball)
	assert_eq(game.lives[0], 1, "the thrower pays a life")
	assert_eq(game.lives[1], 2, "the catcher steals one")
	assert_eq(int(ball.state), StormCourt.BallState.HELD, "and holds the ball")
	assert_eq(int(ball.holder), 1)


func test_hit_protection_blocks_a_follow_up_volley() -> void:
	var game := _game()
	game.lives[1] = 3
	var ball := _arm_and_square(game, 0, 1)
	game.handle_input(0, {"act": true})
	_fly_until_resolved(game, ball)
	assert_eq(game.lives[1], 2)
	# Immediately re-throw: the fresh HIT_PROTECT window swallows it.
	ball = _arm_and_square(game, 0, 1)
	game.handle_input(0, {"act": true})
	for _i in 10:
		game.tick(TICK)
	assert_eq(game.lives[1], 2, "no combo through the protection window")


func test_sabotage_strike_telegraphs_then_hits_the_circle() -> void:
	var game := _game()
	game.sabotage_tokens[0] = 1
	game.lives[1] = 2
	game.positions[1] = Vector2(3.0, 0.0)
	game.move_dirs[1] = Vector2.ZERO
	game.handle_input(0, {"sabotage": 1})
	assert_eq(game.strikes.size(), 1, "token spent, strike telegraphed")
	assert_eq(game.sabotage_tokens[0], 0)
	game.handle_input(0, {"sabotage": 1})
	assert_eq(game.strikes.size(), 1, "no tokens, no second strike")
	for _i in int(StormCourt.SABOTAGE_WARN_SEC / TICK) + 2:
		game.tick(TICK)
	assert_eq(game.strikes.size(), 0, "the strike landed")
	assert_eq(game.lives[1], 1, "and stripped a life from the circle")


func test_court_shrinks_in_stages_to_the_minimum() -> void:
	var game := _game()
	var before: float = game.radius
	for _i in int(StormCourt.SHRINK_STAGE_SEC / TICK) + 2:
		game.tick(TICK)
	assert_lt(game.radius, before, "a stage landed")
	game.radius = StormCourt.MIN_RADIUS
	game._stage_accum = StormCourt.SHRINK_STAGE_SEC
	game.tick(TICK)
	assert_eq(game.radius, StormCourt.MIN_RADIUS, "never below the minimum")
	# Players stay clamped inside the live court.
	game.positions[0] = Vector2(StormCourt.START_RADIUS, 0.0)
	game.tick(TICK)
	assert_lte(
		(game.positions[0] as Vector2).length(),
		game.radius - StormCourt.PLAYER_RADIUS + 0.001,
		"clamped into the storm walls"
	)


func test_last_one_standing_finishes_with_gauntlet_shaped_ranking() -> void:
	var game := _game(3)
	game.lives[1] = 0
	game._pending_elims.append(1)
	game.tick(TICK)
	assert_false(game.finished, "two still standing")
	game.lives[2] = 0
	game._pending_elims.append(2)
	game.tick(TICK)
	assert_true(game.finished, "royale: one left ends it")
	var placements: Array = game.get_results().placements
	assert_eq(placements[0], [0], "the survivor wins")
	assert_eq(placements[1], [2], "then the last eliminated")
	assert_eq(placements[2], [1], "then the first")


func test_snapshot_shape() -> void:
	var game := _game()
	var snap := game.get_snapshot()
	for key in ["radius", "shrink_in", "players", "balls", "strikes", "eliminated"]:
		assert_true(snap.has(key), "%s replicates" % key)
	assert_eq((snap.players[0] as Array).size(), StormCourt.PS_COUNT)
	assert_eq(snap.balls.size(), StormCourt.ball_count_for(3))
	assert_eq((snap.balls[0] as Array).size(), StormCourt.BL_COUNT)
