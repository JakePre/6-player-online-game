extends GutTest
## Fish Frenzy (#183): seeded cadence spawning, lane catches, streak
## bonuses, escape streak-breaks, and ranking.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> FishFrenzy:
	var game := FishFrenzy.new()
	game.meta = FishFrenzy.make_meta()
	game.setup(player_slots, 42)
	return game


func test_meta_and_catalog() -> void:
	var meta := FishFrenzy.make_meta()
	assert_eq(meta.id, &"fish_frenzy")
	assert_eq(meta.category, MinigameMeta.Category.SKILL)
	assert_eq(meta.max_players, 8)
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"fish_frenzy") is FishFrenzy)
	MinigameCatalog.clear()


## No sim geometry to scale (fixed 3 lanes, no positions); a 24-cap for this
## game isn't planned (ADR 003), so this just confirms setup handles the raised
## cap. A fish in a lane is a shared prize (#776), so more players just means
## more of them can score the same beat.
func test_setup_handles_eight_players() -> void:
	var player_slots: Array[int] = []
	for i in 8:
		player_slots.append(i)
	var game := _game(player_slots)
	assert_eq(game.lane.size(), 8)
	for slot in 8:
		assert_eq(game.lane[slot], 1)
		assert_eq(game.caught[slot], 0)


func test_school_is_deterministic_and_on_cadence() -> void:
	var a := _game()
	var b := _game()
	for _i in 90:
		a.tick(TICK)
		b.tick(TICK)
	assert_gt(a.fish.size(), 0, "fish are inbound")
	assert_eq(a.fish.size(), b.fish.size())
	for i in a.fish.size():
		assert_eq(a.fish[i].lane, b.fish[i].lane, "same seed, same school")


func test_cadence_tightens_over_the_round() -> void:
	var game := _game()
	var early := game.cadence()
	game.elapsed = FishFrenzy.RAMP_SEC * 2.0
	assert_lt(game.cadence(), early)
	assert_almost_eq(game.cadence(), FishFrenzy.CADENCE_MIN_SEC, 0.001)


func test_standing_in_the_lane_catches_at_the_line() -> void:
	var game := _game()
	game._next_spawn_at = 999.0  # No cadence spawns in this focused test.
	game.fish.append({"lane": 2, "arrives_at": game.elapsed})
	game.handle_input(0, {"lane": 2})
	game.tick(TICK)
	assert_eq(game.caught[0], 1)
	assert_eq(game.streak[0], 1)
	assert_eq(game.fish.size(), 0, "caught fish leave the water")


## #776: a fish in a lane is a shared prize — EVERYONE standing there catches
## it and keeps their streak, so no lowest-slot bias (player 1 used to win the
## whole lane). The catch still retires the one fish from the water.
func test_everyone_in_the_lane_catches_the_same_fish() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game._next_spawn_at = 999.0
	game.fish.append({"lane": 2, "arrives_at": game.elapsed})
	game.handle_input(0, {"lane": 2})
	game.handle_input(1, {"lane": 2})
	game.handle_input(2, {"lane": 0})  # different lane: no catch, no streak
	game.tick(TICK)
	assert_eq(game.caught[0], 1, "P1 scores")
	assert_eq(game.caught[1], 1, "P2 in the same lane scores too")
	assert_eq(game.caught[2], 0, "the player in another lane does not")
	assert_eq(game.streak[0], 1)
	assert_eq(game.streak[1], 1)
	assert_eq(game.fish.size(), 0, "the fish is retired once caught")


func test_wrong_lane_misses_and_escape_breaks_the_streak() -> void:
	var game := _game()
	game.streak[0] = 4
	game.handle_input(0, {"lane": 1})
	game.fish.append({"lane": 1, "arrives_at": game.elapsed - FishFrenzy.CATCH_WINDOW_SEC - 0.1})
	# Fish is already past the window in slot 0's lane: it escaped them.
	game.tick(TICK)
	assert_eq(game.caught[0], 0)
	assert_eq(game.streak[0], 0, "an escape in your lane kills the streak")


func test_streak_bonus_every_five() -> void:
	var game := _game()
	game.streak[0] = 4
	game.handle_input(0, {"lane": 0})
	game.fish.append({"lane": 0, "arrives_at": game.elapsed})
	game.tick(TICK)
	assert_eq(game.streak[0], 5)
	assert_eq(game.caught[0], 1 + FishFrenzy.STREAK_BONUS, "fifth in a row pays double")


func test_lane_input_clamped() -> void:
	var game := _game()
	game.handle_input(0, {"lane": 99})
	assert_eq(game.lane[0], FishFrenzy.LANES - 1)
	game.handle_input(0, {"lane": -5})
	assert_eq(game.lane[0], 0)


func test_most_fish_wins_and_catches_become_pickup_coins() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game.caught = {0: 4, 1: 9, 2: 4}
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0, 2]])
	assert_eq(game.get_results().pickup_coins, {0: 4, 1: 9, 2: 4})


func test_snapshot_shape() -> void:
	var game := _game()
	game.fish.append({"lane": 1, "arrives_at": game.elapsed + 1.0})
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players[0].size(), 3)
	assert_eq(snapshot.fish.size(), 1)
	assert_eq(snapshot.fish[0][0], 1)
	assert_almost_eq(float(snapshot.fish[0][1]), 1.0, 0.05)
