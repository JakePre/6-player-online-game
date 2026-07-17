extends GutTest
## Putt Panic server simulation (M14-08): tee setup, putt/stroke, rolling
## friction, wall + block bounce, the sink rule, the shot clock, and ranking.

const TICK := 1.0 / 30.0
## #961 anti-collapse floor: bot-round median must clear this fraction of meta
## (the #933 red-flag threshold). See the guard test below.
const COLLAPSE_FLOOR_FRAC := 0.4


func _game(count: int = 2) -> PuttPanic:
	var game := PuttPanic.new()
	game.meta = PuttPanic.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 42)
	return game


## Drives a full bot field to completion, returning how long the round lasted.
func _run_bot_round(count: int, seed_value: int) -> float:
	var game := PuttPanic.new()
	game.meta = PuttPanic.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, seed_value)
	var brains := {}
	for slot: int in game.slots:
		brains[slot] = BotBrains.brain_for(&"putt_panic", slot, seed_value)
	var t := 0.0
	while not game.finished and t < game.meta.duration_sec:
		var match_state := {"game": game.get_snapshot()}
		for slot: int in game.slots:
			game.handle_input(slot, brains[slot].think(match_state, {}))
		game.tick(TICK)
		t += TICK
	return t


## #961: putt_panic bot rounds collapsed to ~6s of a 90s hole because the brains
## machine-gunned a putt the instant the ball came to rest (~0.45s apart, ~11
## strokes ground out in seconds). The putt-pacing readiness beat spaces strokes
## to a human cadence; the round now fills a real fraction of the hole. Assert
## the MEDIAN round across a seed batch clears the #933 red-flag floor (≥40% of
## meta) for the common player counts — individual seeds still vary (that spread
## is the point), so the guard is on the median, not every round.
func test_bot_rounds_do_not_collapse_to_machine_gun_putts() -> void:
	var floor_sec := PuttPanic.make_meta().duration_sec * COLLAPSE_FLOOR_FRAC
	for count: int in [4, 6]:
		var lens: Array[float] = []
		for s in range(1, 13):
			lens.append(_run_bot_round(count, s))
		lens.sort()
		var median := (lens[5] + lens[6]) / 2.0
		assert_gt(
			median,
			floor_sec,
			"%d-bot median round (%.0fs) clears the #933 >=40%%-of-meta floor" % [count, median]
		)


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
		# The tee ring (#1071) puts seats all around the cup, so "toward the
		# cup" is per-seat: the default aim tracks each ball's own line.
		var to_cup: Vector2 = (game.cup_pos - game.positions[slot]).normalized()
		assert_gt((game.aims[slot] as Vector2).dot(to_cup), 0.99, "aimed at the cup")


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
	slow.positions[0] = slow.cup_pos + Vector2(0.2, 0.0)
	slow.velocities[0] = Vector2(-2.0, 0.0)
	slow._roll(0, TICK)
	assert_true(bool(slow.sunk[0]), "a gentle ball drops in")
	# Fast arrival lips out.
	var fast := _game()
	fast.positions[1] = fast.cup_pos + Vector2(0.2, 0.0)
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
	game.positions[2] = game.cup_pos + Vector2(1.0, 0.0)  # unsunk, close
	game.positions[3] = game.cup_pos + Vector2(5.0, 0.0)  # unsunk, far
	assert_eq(
		game._rank_players(), [[0], [1], [2], [3]], "fewest strokes first, then the nearest unsunk"
	)


func test_all_sunk_finishes_the_round() -> void:
	var game := _game()
	game.sunk[0] = true
	game.sunk[1] = true
	game.tick(TICK)
	assert_true(game.finished)


## #793: the same seed reproduces the same course, so every peer agrees.
func test_course_is_deterministic_for_a_seed() -> void:
	var a := PuttPanic.new()
	a.meta = PuttPanic.make_meta()
	a.setup([0, 1] as Array[int], 123)
	var b := PuttPanic.new()
	b.meta = PuttPanic.make_meta()
	b.setup([0, 1] as Array[int], 123)
	assert_eq(a.cup_pos, b.cup_pos, "same seed = same cup")
	assert_eq(a.course, b.course, "same seed = same archetype")
	assert_eq(a.bar_range, b.bar_range, "same seed = same orbit")
	assert_eq(a.blocks.size(), b.blocks.size(), "same seed = same block set")


## #793: different seeds give different courses — the point of the feature.
func test_course_varies_across_seeds() -> void:
	var a := PuttPanic.new()
	a.meta = PuttPanic.make_meta()
	a.setup([0, 1] as Array[int], 1)
	var b := PuttPanic.new()
	b.meta = PuttPanic.make_meta()
	b.setup([0, 1] as Array[int], 2)
	assert_ne(a.cup_pos, b.cup_pos, "a different seed moves the cup")


## #1071 fairness: whatever the seed and archetype, every tee sits exactly
## TEE_RADIUS from the cup (equal distance = equal hole-in-one potential — the
## owner's wave-4 complaint), every obstacle keeps clear of both the cup mouth
## and the tees, and the whole layout stays inside the walls.
func test_every_tee_is_equidistant_from_the_cup_on_every_course() -> void:
	for seed_value in [0, 7, 42, 99, 500, 2024, 31337]:
		var game := PuttPanic.new()
		game.meta = PuttPanic.make_meta()
		game.setup([0, 1, 2, 3, 4, 5] as Array[int], seed_value)
		for slot in 6:
			assert_almost_eq(
				(game.positions[slot] as Vector2).distance_to(game.cup_pos),
				PuttPanic.TEE_RADIUS,
				0.001,
				"seed %d: every seat putts the same distance" % seed_value
			)
			var tee: Vector2 = game.positions[slot]
			assert_true(
				(
					absf(tee.x) < PuttPanic.ARENA_HALF - PuttPanic.BALL_RADIUS
					and absf(tee.y) < PuttPanic.ARENA_HALF - PuttPanic.BALL_RADIUS
				),
				"seed %d: tees stay inside the walls" % seed_value
			)


func test_generated_course_stays_within_fair_bounds() -> void:
	for seed_value in [0, 7, 42, 99, 500, 2024]:
		var game := PuttPanic.new()
		game.meta = PuttPanic.make_meta()
		game.setup([0, 1] as Array[int], seed_value)
		assert_between(
			game.cup_pos.x, -PuttPanic.CUP_JITTER, PuttPanic.CUP_JITTER, "cup near centre"
		)
		assert_between(
			game.cup_pos.y, -PuttPanic.CUP_JITTER, PuttPanic.CUP_JITTER, "cup near centre"
		)
		# The bar's orbit never sweeps the cup mouth shut...
		var bar_clearance: float = game.bar_range - game.bar_half.x
		assert_gt(
			bar_clearance,
			PuttPanic.CUP_RADIUS + PuttPanic.BALL_RADIUS,
			"the orbiting bar clears the cup by more than a ball"
		)
		# ...and every block ring keeps clear of the cup and of the tee circle.
		for block: Dictionary in game.blocks:
			var dist: float = (block.pos as Vector2).distance_to(game.cup_pos)
			var reach: float = (block.half as Vector2).length()
			assert_gt(
				dist - reach,
				PuttPanic.CUP_RADIUS + PuttPanic.BALL_RADIUS,
				"blocks leave the cup mouth open"
			)
			assert_lt(
				dist + reach, PuttPanic.TEE_RADIUS - PuttPanic.BALL_RADIUS, "blocks clear the tees"
			)


## #1071: the pool actually cycles — a spread of seeds reaches more than one
## archetype (and at least once, one with blocks and one without).
func test_course_pool_reaches_multiple_archetypes() -> void:
	var seen := {}
	for seed_value in 24:
		var game := PuttPanic.new()
		game.meta = PuttPanic.make_meta()
		game.setup([0, 1] as Array[int], seed_value)
		seen[game.course] = true
	assert_gt(seen.size(), 1, "24 seeds reach more than one archetype")
