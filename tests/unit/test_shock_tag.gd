extends GutTest
## Shock Tag sim (M10-03): zap passing, coin draining, clean-time banking,
## and coin-count ranking. Server-side logic only.

const TICK := 1.0 / 30.0


func _game_with(count: int) -> ShockTag:
	var game := ShockTag.new()
	game.meta = ShockTag.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 7)
	return game


## Puts everyone far apart with the zap on `holder` and no lingering immunity.
func _spread(game: ShockTag, holder: int) -> void:
	game.positions[0] = Vector2(-7.0, -7.0)
	game.positions[1] = Vector2(7.0, -7.0)
	game.positions[2] = Vector2(0.0, 7.0)
	game.zapped = holder
	game._tag_back_left = 0.0


func test_setup_electrifies_exactly_one_player() -> void:
	var game := _game_with(4)
	assert_true(game.zapped in game.slots)


func test_max_players_raised_to_eight() -> void:
	assert_eq(ShockTag.make_meta().max_players, 8)


func test_control_spec_present() -> void:
	assert_false(
		ShockTag.make_meta().control_spec.is_empty(), "ships a #832 structured control spec"
	)


## No-crowd fairness (M15 8-cap): the spawn ring already auto-distributes by
## slot count, and at 8 players everyone starts well clear of tag range.
func test_setup_spawns_are_spread_at_eight_players() -> void:
	var game := _game_with(8)
	assert_eq(game.coins.size(), 8)
	for a in 8:
		for b in range(a + 1, 8):
			var dist: float = (game.positions[a] as Vector2).distance_to(game.positions[b])
			assert_gt(
				dist, ShockTag.TAG_RANGE, "slots %d/%d don't spawn already in tag range" % [a, b]
			)
	assert_true(game.zapped in game.slots)


func test_zapped_player_moves_faster() -> void:
	var game := _game_with(3)
	_spread(game, 0)
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(5.0, 5.0)
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	game.handle_input(1, {"mx": -1.0, "my": 0.0})
	game.tick(TICK)
	assert_almost_eq(game.positions[0].x, ShockTag.ZAPPED_SPEED * TICK, 0.001)
	assert_almost_eq(game.positions[1].x, 5.0 - ShockTag.MOVE_SPEED * TICK, 0.001)


func test_tag_passes_the_zap_and_drains_coins() -> void:
	var game := _game_with(3)
	_spread(game, 0)
	game.coins[1] = 20
	game.coins[0] = 3
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(ShockTag.TAG_RANGE * 0.9, 0.0)
	game.tick(TICK)
	assert_eq(game.zapped, 1, "the zap passes on touch")
	assert_eq(game.coins[1], 20 - ShockTag.DRAIN_COINS, "victim drained")
	assert_eq(game.coins[0], 3 + ShockTag.DRAIN_COINS, "tagger pockets the drain")
	assert_eq(game._tag_back_slot, 0, "the player who just passed the zap is now immune")
	assert_almost_eq(game._tag_back_left, ShockTag.NO_TAG_BACK_SEC, 0.05)


func test_drain_never_takes_more_than_the_victim_has() -> void:
	var game := _game_with(3)
	_spread(game, 0)
	game.coins[1] = 2
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(0.1, 0.0)
	game.tick(TICK)
	assert_eq(game.coins[0], 2, "only what they had")


func test_immunity_blocks_instant_tag_backs() -> void:
	var game := _game_with(3)
	_spread(game, 0)
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(0.1, 0.0)
	game.tick(TICK)
	assert_eq(game.zapped, 1)
	game.tick(TICK)
	assert_eq(game.zapped, 1, "still immune: the zap cannot bounce straight back")
	game._tag_back_left = 0.0
	game.tick(TICK)
	assert_eq(game.zapped, 0, "after immunity the collision tags again")


## #809: the immunity only shields the specific player who just passed the
## zap — the newly-zapped chaser can still tag a different bystander at once.
func test_new_zapped_can_tag_a_bystander_during_the_immunity_window() -> void:
	var game := _game_with(3)
	_spread(game, 0)
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(0.1, 0.0)
	game.tick(TICK)
	assert_eq(game.zapped, 1, "the zap passes to slot 1")
	game.positions[2] = game.positions[1]
	game.tick(TICK)
	assert_eq(game.zapped, 2, "a bystander in range gets tagged right away")


func test_clean_players_bank_coins_over_time() -> void:
	var game := _game_with(3)
	_spread(game, 2)
	for _i in 31:
		game.tick(TICK)
	assert_eq(game.coins[0], 1, "one clean second = one coin")
	assert_eq(game.coins[2], 0, "the zapped player banks nothing")


func test_ranking_by_coins_with_ties_and_pickups() -> void:
	var game := _game_with(3)
	_spread(game, 0)
	game.coins = {0: 4, 1: 9, 2: 4}
	game.duration_override = TICK
	game.tick(TICK)
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0, 2]])
	assert_eq(game.get_results().pickup_coins[1], 9, "coins double as capped pickups")


func test_snapshot_shape() -> void:
	var game := _game_with(3)
	_spread(game, 1)
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 3)
	assert_eq(snapshot.zapped, 1)
	assert_eq((snapshot.players[0] as Array).size(), ShockTag.PS_COUNT, "[x, y, coins]")
