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
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"bullet_waltz") is BulletWaltz)
	MinigameCatalog.clear()


func test_patterns_are_deterministic_from_seed() -> void:
	var a := _game()
	var b := _game()
	for _i in 150:
		a.tick(TICK)
		b.tick(TICK)
	assert_gt(a.bullets.size(), 0, "past the grace the storm is live")
	assert_eq(a.bullets.size(), b.bullets.size())
	for i in a.bullets.size():
		assert_eq(a.bullets[i].pos, b.bullets[i].pos, "same seed, same storm")


## #208: the opening grace holds the first volley, then firing resumes on
## the normal cadence.
func test_opening_grace_delays_the_first_volley() -> void:
	var game := _game()
	var grace_ticks := int(BulletWaltz.SPAWN_GRACE_SEC / TICK) - 1
	for _i in grace_ticks:
		game.tick(TICK)
	assert_true(game.bullets.is_empty(), "no bullets during the grace")
	var until_first := int((BulletWaltz.FIRE_INTERVAL_START + 0.1) / TICK) + 2
	for _i in until_first:
		game.tick(TICK)
	assert_gt(game.bullets.size(), 0, "first volley lands after grace + interval")


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
	# #959: graze score breaks the timeout survivor tie — the bold dancer
	# out-places the coin-shy pair rather than everyone tying flat.
	assert_eq(game.get_results().placements, [[0], [1, 2]], "graze breaks the survivor tie")


## #959: within a same-tick KO group, more grazes place higher — dying while
## dancing close beats dying in a corner.
func test_graze_breaks_a_same_tick_ko_tie() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game.graze_coins[1] = 5
	game.bullets.append({"pos": game.positions[0], "vel": Vector2.ZERO})
	game.bullets.append({"pos": game.positions[1], "vel": Vector2.ZERO})
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[2], [1], [0]], "grazier KO ranks above")


## #959: the Waltz Bomb culls bullets inside its radius, leaves the rest, and
## fires only once per round.
func test_waltz_bomb_clears_nearby_bullets_and_is_single_use() -> void:
	var game := _game()
	var here: Vector2 = game.positions[0]
	game.bullets.append({"pos": here + Vector2(1.0, 0.0), "vel": Vector2.ZERO})
	game.bullets.append(
		{"pos": here + Vector2(BulletWaltz.WALTZ_BOMB_RADIUS + 2.0, 0.0), "vel": Vector2.ZERO}
	)
	game.handle_input(0, {"bomb": true})
	assert_eq(game.bullets.size(), 1, "only the bullet inside the bloom is culled")
	assert_false(game.bomb_ready[0], "the once-per-round charge is spent")
	# A second press with no charge left leaves the field untouched.
	game.bullets.append({"pos": here + Vector2(1.0, 0.0), "vel": Vector2.ZERO})
	game.handle_input(0, {"bomb": true})
	assert_eq(game.bullets.size(), 2, "a spent bomb does nothing")


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
	assert_eq(snapshot.players[0].size(), BulletWaltz.PS_COUNT)
	assert_eq(snapshot.players[0][BulletWaltz.PS_BOMB], 1, "everyone starts holding the Waltz Bomb")
	assert_eq(snapshot.bullets, [[1.0, 2.0]])
	assert_eq(snapshot.out, [])


func _slots(n: int) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		out.append(i)
	return out


## M15 †-cap: Bullet Waltz scales to 24.
func test_scales_to_24_players() -> void:
	assert_eq(BulletWaltz.make_meta().max_players, 24)


## The dodge floor and the range bullets must clear grow with the lobby, and a
## crowd spawns spread out rather than piled on one ring.
func test_arena_and_spawns_scale_with_the_lobby() -> void:
	var big := _game(_slots(24))
	assert_gt(big._play_half, BulletWaltz.ARENA_HALF, "24 players get a bigger arena")
	assert_almost_eq(big._bullet_range, big._play_half * BulletWaltz.BULLET_RANGE_FACTOR, 0.001)
	var placed: Array[Vector2] = []
	for slot: int in big.slots:
		var pos: Vector2 = big.positions[slot]
		assert_lte(pos.length(), big._play_half + 0.001, "everyone spawns in bounds")
		for other: Vector2 in placed:
			assert_gt(
				pos.distance_to(other), BulletWaltz.PLAYER_RADIUS * 2.0, "no overlapping spawns"
			)
		placed.append(pos)


## The tuned <=6-player game is byte-for-byte unchanged.
func test_small_lobbies_keep_the_tuned_arena() -> void:
	var small := _game(_slots(6))
	assert_almost_eq(small._play_half, BulletWaltz.ARENA_HALF, 0.001)
	assert_almost_eq(small._bullet_range, BulletWaltz.BULLET_RANGE, 0.001)
