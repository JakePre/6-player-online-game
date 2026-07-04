extends GutTest
## Coin Scramble server simulation (M3-06 reference minigame): movement,
## collection, bump-scatter, and coin-count ranking.

const TICK := 1.0 / 30.0


func _make_game(player_count: int) -> CoinScramble:
	var game := CoinScramble.new()
	game.meta = CoinScramble.make_meta()
	var slots: Array[int] = []
	for i in player_count:
		slots.append(i)
	game.setup(slots, 42)
	return game


func test_setup_spreads_players_and_spawns_first_wave() -> void:
	var game := _make_game(4)
	assert_eq(game.coins.size(), CoinScramble.COINS_PER_WAVE)
	for slot in 4:
		assert_eq(game.collected[slot], 0)
		assert_lt(
			(game.positions[slot] as Vector2).length(), CoinScramble.ARENA_HALF, "spawn in arena"
		)


func test_movement_follows_input_and_clamps_to_arena() -> void:
	var game := _make_game(2)
	game.coins.clear()
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	for _i in 240:
		game.tick(TICK)
		game.coins.clear()  # Ignore pickups; this test is about movement.
	assert_eq((game.positions[0] as Vector2).x, CoinScramble.ARENA_HALF)


func test_input_direction_is_capped_at_unit_length() -> void:
	var game := _make_game(2)
	game.handle_input(0, {"mx": 100.0, "my": 100.0})
	assert_almost_eq((game.move_dirs[0] as Vector2).length(), 1.0, 0.001)


func test_walking_over_a_coin_collects_it() -> void:
	var game := _make_game(2)
	game.coins.clear()
	game.coins.append(game.positions[0] as Vector2)
	game.tick(TICK)
	assert_eq(game.collected[0], 1)
	assert_false(game.coins.has(game.positions[0]))


func test_bump_scatters_a_fifth_of_the_richer_players_coins() -> void:
	var game := _make_game(2)
	game.coins.clear()
	game.collected[0] = 10
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(CoinScramble.PLAYER_RADIUS, 0.0)
	game._resolve_bumps(TICK)
	assert_eq(game.collected[0], 8)
	assert_eq(game.coins.size(), 2)


func test_bump_between_equal_players_does_nothing() -> void:
	var game := _make_game(2)
	game.coins.clear()
	game.collected[0] = 5
	game.collected[1] = 5
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2.ZERO
	game._resolve_bumps(TICK)
	assert_eq(game.collected[0], 5)
	assert_eq(game.collected[1], 5)


func test_ranking_groups_ties_and_reports_pickups() -> void:
	var game := _make_game(4)
	game.duration_override = 0.1
	game.coins.clear()  # Nobody may grab a wave coin and skew the counts.
	game.collected = {0: 3, 1: 7, 2: 3, 3: 0}
	game.tick(0.2)
	assert_true(game.finished)
	var results := game.get_results()
	assert_eq(results.placements, [[1], [0, 2], [3]])
	assert_eq(results.pickup_coins, {0: 3, 1: 7, 2: 3, 3: 0})


func test_snapshot_lists_players_and_coins() -> void:
	var game := _make_game(2)
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 2)
	assert_eq(snapshot.coins.size(), game.coins.size())
	var entry: Array = snapshot.players[0]
	assert_eq(entry.size(), 3, "x, y, collected count")


func test_max_players_raised_to_twelve() -> void:
	assert_eq(CoinScramble.make_meta().max_players, 12)


## M15: a 12-player match gets a bigger arena and proportionally more coins.
func test_arena_and_coin_supply_scale_at_twelve() -> void:
	var game := _make_game(12)
	assert_gt(game._play_half, CoinScramble.ARENA_HALF, "the arena grows for a crowd")
	assert_gt(game._coins_per_wave, CoinScramble.COINS_PER_WAVE, "more coins per wave")
	assert_gt(game._max_coins, CoinScramble.MAX_ACTIVE_COINS, "higher active-coin cap")
	assert_eq(game.coins.size(), game._coins_per_wave, "first wave uses the scaled count")


## Backward compatibility: at the 6-player baseline nothing scales.
func test_six_players_unchanged() -> void:
	var game := _make_game(6)
	assert_almost_eq(game._play_half, CoinScramble.ARENA_HALF, 0.001)
	assert_eq(game._coins_per_wave, CoinScramble.COINS_PER_WAVE)
	assert_eq(game._max_coins, CoinScramble.MAX_ACTIVE_COINS)


## Spawns fan out over rings (no overlap) and stay inside the scaled arena.
func test_spawns_distinct_and_within_arena_at_twelve() -> void:
	var game := _make_game(12)
	var seen := {}
	for slot in 12:
		var pos: Vector2 = game.positions[slot]
		assert_lte(pos.length(), game._play_half, "spawn inside the scaled arena")
		seen[pos] = true
	assert_eq(seen.size(), 12, "every player gets a distinct spawn")
