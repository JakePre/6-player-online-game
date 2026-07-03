extends GutTest
## Bullet Waltz (PHASE2.md $4 #35): seeded escalating patterns, one-hit KOs
## with ties, graze coins, and survival ranking.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> BulletWaltz:
	var game := BulletWaltz.new()
	game.meta = BulletWaltz.make_meta()
	game.setup(player_slots, 42)
	return game


func test_meta_and_catalog() -> void:
	var meta := BulletWaltz.make_meta()
	assert_eq(meta.id, &"bullet_waltz")
	assert_eq(meta.category, MinigameMeta.Category.SKILL)
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"bullet_waltz") is BulletWaltz)
	MinigameCatalog.clear()


func test_patterns_are_deterministic_from_seed() -> void:
	var a := _game()
	var b := _game()
	for _i in 90:
		a.tick(TICK)
		b.tick(TICK)
	assert_eq(a.bullets.size(), b.bullets.size())
	for i in a.bullets.size():
		assert_eq(a.bullets[i].pos, b.bullets[i].pos, "same seed, same storm")


func test_escalation_ramps_cadence_and_speed() -> void:
	var game := _game()
	var early_interval := game.fire_interval()
	var early_speed := game.bullet_speed()
	game.elapsed = BulletWaltz.RAMP_SEC * 2.0
	assert_lt(game.fire_interval(), early_interval)
	assert_gt(game.bullet_speed(), early_speed)
	assert_almost_eq(game.fire_interval(), BulletWaltz.FIRE_INTERVAL_MIN, 0.001)


func test_bullet_hit_kos_and_ends_at_one_survivor() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game.bullets.append({"pos": game.positions[0], "vel": Vector2.ZERO})
	game.tick(TICK)
	assert_false(game._is_in(0))
	assert_eq(game.ko_order, [[0]])
	assert_false(game.finished, "two still dancing")
	game.bullets.append({"pos": game.positions[1], "vel": Vector2.ZERO})
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[2], [1], [0]])


func test_same_tick_kos_tie() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game.bullets.append({"pos": game.positions[0], "vel": Vector2.ZERO})
	game.bullets.append({"pos": game.positions[1], "vel": Vector2.ZERO})
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[2], [0, 1]])


func test_graze_banks_a_coin_once_per_pass() -> void:
	var game := _game()
	var pos: Vector2 = game.positions[0]
	# Inside the graze ring but outside the hit radius, moving nowhere.
	game.bullets.append({"pos": pos + Vector2(0.8, 0.0), "vel": Vector2.ZERO})
	game.tick(TICK)
	assert_eq(game.graze_coins[0], 1)
	game.tick(TICK)
	assert_eq(game.graze_coins[0], 1, "lingering in the ring is one graze, not a faucet")


func test_graze_coins_become_pickup_coins() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game.graze_coins[0] = 7
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().pickup_coins[0], 7)
	assert_eq(game.get_results().placements[0].size(), 3, "timeout survivors tie")


func test_bullets_expire_out_of_range() -> void:
	var game := _game()
	game.bullets.append({"pos": Vector2(BulletWaltz.BULLET_RANGE + 1.0, 0.0), "vel": Vector2.RIGHT})
	game.tick(TICK)
	assert_eq(game.bullets.size(), 0)


func test_snapshot_shape() -> void:
	var game := _game()
	game.bullets.append({"pos": Vector2(1.0, 2.0), "vel": Vector2.RIGHT})
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 2)
	assert_eq(snapshot.players[0].size(), 3)
	assert_eq(snapshot.bullets, [[1.0, 2.0]])
	assert_eq(snapshot.out, [])
