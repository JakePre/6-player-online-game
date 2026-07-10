extends GutTest
## Putt Panic server simulation (M14-08): tee setup, putt/stroke, rolling
## friction, wall + block bounce, the sink rule, the shot clock, and ranking.

const TICK := 1.0 / 30.0


func _game(count: int = 2) -> PuttPanic:
	var game := PuttPanic.new()
	game.meta = PuttPanic.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 42)
	return game


func test_meta_and_catalog() -> void:
	var meta := PuttPanic.make_meta()
	assert_eq(meta.id, &"putt_panic")
	assert_eq(meta.category, MinigameMeta.Category.SKILL)
	assert_eq(meta.min_players, 2)
	assert_eq(meta.max_players, 8)
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"putt_panic") is PuttPanic)
	MinigameCatalog.clear()


func test_setup_tees_balls_aimed_at_the_cup() -> void:
	var game := _game(4)
	for slot in 4:
		assert_eq(int(game.strokes[slot]), 0)
		assert_false(bool(game.sunk[slot]))
		assert_true(game._at_rest(slot), "balls start at rest")
		# Aim points up-field toward the cup.
		assert_gt((game.aims[slot] as Vector2).y, 0.0, "aimed toward the cup")


func test_putt_launches_the_ball_and_counts_a_stroke() -> void:
	var game := _game()
	game.aims[0] = Vector2(0.0, 1.0)
	game.handle_input(0, {"putt": true, "power": 1.0})
	assert_eq(int(game.strokes[0]), 1)
	assert_almost_eq((game.velocities[0] as Vector2).length(), PuttPanic.MAX_POWER, 0.01)
	assert_false(game._at_rest(0), "the ball is now rolling")


func test_cannot_putt_while_the_ball_is_moving() -> void:
	var game := _game()
	game.velocities[0] = Vector2(0.0, 5.0)  # already rolling
	game.handle_input(0, {"putt": true, "power": 1.0})
	assert_eq(int(game.strokes[0]), 0, "no re-putt mid-roll")


func test_friction_brings_the_ball_to_rest() -> void:
	var game := _game()
	game.positions[0] = Vector2(-6.0, -6.0)
	game.velocities[0] = Vector2(0.0, 3.0)
	for _i in 60:
		game.tick(TICK)
	assert_true(game._at_rest(0), "friction stops the ball within two seconds")


func test_wall_bounce_reflects_velocity() -> void:
	var game := _game()
	game.positions[0] = Vector2(PuttPanic.ARENA_HALF - 0.1, 0.0)
	game.velocities[0] = Vector2(8.0, 0.0)  # into the +x wall
	game._roll(0, TICK)
	assert_lt((game.velocities[0] as Vector2).x, 0.0, "the ball rebounds off the wall")


func test_block_bounce_pushes_out_and_reflects() -> void:
	var game := _game()
	var center := Vector2.ZERO
	var half := Vector2(1.0, 1.0)
	# Ball overlapping the top face, driving down into the block.
	game.positions[0] = Vector2(0.0, 1.15)
	game.velocities[0] = Vector2(0.0, -6.0)
	game._bounce_box(0, center, half)
	assert_almost_eq((game.positions[0] as Vector2).y, 1.0 + PuttPanic.BALL_RADIUS, 0.01, "ejected")
	assert_gt((game.velocities[0] as Vector2).y, 0.0, "velocity reflected upward")


func test_slow_ball_sinks_but_a_fast_one_rolls_over() -> void:
	# Slow arrival drops.
	var slow := _game()
	slow.positions[0] = PuttPanic.CUP_POS + Vector2(0.2, 0.0)
	slow.velocities[0] = Vector2(-2.0, 0.0)
	slow._roll(0, TICK)
	assert_true(bool(slow.sunk[0]), "a gentle ball drops in")
	# Fast arrival lips out.
	var fast := _game()
	fast.positions[1] = PuttPanic.CUP_POS + Vector2(0.2, 0.0)
	fast.velocities[1] = Vector2(-12.0, 0.0)
	fast._roll(1, TICK)
	assert_false(bool(fast.sunk[1]), "too fast rolls over the lip")


func test_shot_clock_auto_putts_an_idler() -> void:
	var game := _game()
	game.rest_time[0] = PuttPanic.SHOT_CLOCK_SEC
	game.tick(TICK)
	assert_eq(int(game.strokes[0]), 1, "idling past the shot clock forces a putt")


func test_ranking_sunk_by_strokes_then_unsunk_by_distance() -> void:
	var game := _game(4)
	game.sunk[0] = true
	game.strokes[0] = 2
	game.sunk[1] = true
	game.strokes[1] = 3
	game.positions[2] = PuttPanic.CUP_POS + Vector2(1.0, 0.0)  # unsunk, close
	game.positions[3] = PuttPanic.CUP_POS + Vector2(5.0, 0.0)  # unsunk, far
	assert_eq(
		game._rank_players(), [[0], [1], [2], [3]], "fewest strokes first, then the nearest unsunk"
	)


func test_all_sunk_finishes_the_round() -> void:
	var game := _game()
	game.sunk[0] = true
	game.sunk[1] = true
	game.tick(TICK)
	assert_true(game.finished)
