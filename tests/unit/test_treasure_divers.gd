extends GutTest
## Treasure Divers sim (M10-04): dive/surface state, air drain and blackout,
## seabed collection, and coin ranking. Server-side logic only.

const TICK := 1.0 / 30.0


func _game_with(count: int) -> TreasureDivers:
	var game := TreasureDivers.new()
	game.meta = TreasureDivers.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 7)
	return game


func test_setup_starts_everyone_surfaced_with_full_air() -> void:
	var game := _game_with(3)
	for slot: int in game.slots:
		assert_false(game.diving[slot])
		assert_almost_eq(game.air[slot], TreasureDivers.AIR_MAX_SEC, 0.001)


func test_diving_is_slower_than_swimming() -> void:
	var game := _game_with(2)
	game.positions[0] = Vector2.ZERO
	game.positions[1] = Vector2(0.0, 3.0)
	game.handle_input(0, {"dive": true})
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	game.handle_input(1, {"mx": 1.0, "my": 0.0})
	game.tick(TICK)
	assert_almost_eq(game.positions[0].x, TreasureDivers.DIVE_SPEED * TICK, 0.001)
	assert_almost_eq(game.positions[1].x, TreasureDivers.SURFACE_SPEED * TICK, 0.001)


func test_only_divers_collect_treasure() -> void:
	var game := _game_with(2)
	game._wave_left = 999.0  # keep the seeded waves out of this hand-built board
	game.positions[0] = Vector2(2.0, 2.0)
	game.positions[1] = Vector2(-2.0, -2.0)
	game.treasure = [Vector2(2.0, 2.0), Vector2(-2.0, -2.0)]
	game.handle_input(0, {"dive": true})
	game.tick(TICK)
	assert_eq(game.coins[0], 1, "the diver scoops the coin")
	assert_eq(game.coins[1], 0, "the swimmer floats right over theirs")
	assert_eq(game.treasure.size(), 1)


func test_air_drains_diving_and_refills_faster_surfaced() -> void:
	var game := _game_with(2)
	game.handle_input(0, {"dive": true})
	game.tick(1.0)
	assert_almost_eq(game.air[0], TreasureDivers.AIR_MAX_SEC - 1.0, 0.001)
	game.handle_input(0, {"dive": false})
	game.tick(0.2)
	assert_almost_eq(
		game.air[0], TreasureDivers.AIR_MAX_SEC - 1.0 + 0.2 * TreasureDivers.AIR_REFILL_RATE, 0.001
	)


func test_empty_air_blacks_out_forces_surface_and_stuns() -> void:
	var game := _game_with(2)
	game.handle_input(0, {"dive": true})
	game.tick(TreasureDivers.AIR_MAX_SEC + TICK)
	assert_false(game.diving[0], "blackout forces you up")
	assert_almost_eq(game.stunned[0], TreasureDivers.BLACKOUT_STUN_SEC, 0.001)
	game.handle_input(0, {"dive": true})
	assert_false(game.diving[0], "cannot dive while stunned")
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	var before: Vector2 = game.positions[0]
	game.tick(TICK)
	assert_almost_eq(game.positions[0].x, before.x, 0.001, "stunned players cannot move")


func test_stun_wears_off_and_diving_resumes() -> void:
	var game := _game_with(2)
	game.stunned[0] = TICK
	game.tick(TICK)
	assert_eq(game.stunned[0], 0.0)
	game.handle_input(0, {"dive": true})
	assert_true(game.diving[0])


func test_treasure_waves_spawn_up_to_the_cap() -> void:
	var game := _game_with(2)
	for _i in 300:
		game.tick(TICK)
	assert_gt(game.treasure.size(), 0)
	assert_lte(game.treasure.size(), TreasureDivers.MAX_ACTIVE_COINS)


func test_ranking_by_coins_with_pickups() -> void:
	var game := _game_with(3)
	game.coins = {0: 2, 1: 8, 2: 2}
	game.duration_override = TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0, 2]])
	assert_eq(game.get_results().pickup_coins[1], 8)


func test_snapshot_shape() -> void:
	var game := _game_with(2)
	game.handle_input(0, {"dive": true})
	game.tick(TICK)
	var snapshot := game.get_snapshot()
	assert_eq((snapshot.players[0] as Array).size(), 6, "[x, y, coins, diving, air, stun]")
	assert_eq(snapshot.players[0][3], 1)
	assert_eq(snapshot.players[1][3], 0)
