extends GutTest
## Rumble Ring (PHASE2.md $4 #34): swing arcs and cooldowns, guard blocks,
## charge-release smashes, KO scoring with coin scatter and respawn
## invulnerability, and points ranking.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> RumbleRing:
	var game := RumbleRing.new()
	game.meta = RumbleRing.make_meta()
	game.setup(player_slots, 42)
	return game


## Puts `attacker` right next to `victim`, facing them.
func _square_up(game: RumbleRing, attacker: int, victim: int) -> void:
	game.positions[victim] = Vector2(2.0, 0.0)
	game.positions[attacker] = Vector2(1.0, 0.0)
	game.facings[attacker] = Vector2.RIGHT


func test_meta_and_catalog() -> void:
	var meta := RumbleRing.make_meta()
	assert_eq(meta.id, &"rumble_ring")
	assert_eq(meta.category, MinigameMeta.Category.FFA)
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"rumble_ring") is RumbleRing)
	MinigameCatalog.clear()


func test_swing_hits_in_the_facing_arc() -> void:
	var game := _game()
	_square_up(game, 0, 1)
	game.handle_input(0, {"attack": true})
	assert_eq(game.hp[1], RumbleRing.MAX_HP - 1)
	assert_gt((game.positions[1] as Vector2).x, 2.0, "light knockback")


func test_swing_misses_behind_the_back() -> void:
	var game := _game()
	_square_up(game, 0, 1)
	game.facings[0] = Vector2.LEFT
	game.handle_input(0, {"attack": true})
	assert_eq(game.hp[1], RumbleRing.MAX_HP)


func test_swing_cooldown_gates_spam() -> void:
	var game := _game()
	_square_up(game, 0, 1)
	game.handle_input(0, {"attack": true})
	game.handle_input(0, {"attack": true})
	assert_eq(game.hp[1], RumbleRing.MAX_HP - 1, "second swing still cooling")


func test_guard_blocks_damage_and_slows() -> void:
	var game := _game()
	_square_up(game, 0, 1)
	game.handle_input(1, {"guard": true})
	game.handle_input(0, {"attack": true})
	assert_eq(game.hp[1], RumbleRing.MAX_HP, "guarded")
	game.handle_input(1, {"mx": 1.0, "my": 0.0})
	var before: float = (game.positions[1] as Vector2).x
	game.tick(TICK)
	var moved := (game.positions[1] as Vector2).x - before
	assert_lt(moved, RumbleRing.MOVE_SPEED * TICK * 0.5, "guarding crawls")


func test_full_charge_release_smashes() -> void:
	var game := _game()
	_square_up(game, 0, 1)
	game.handle_input(0, {"guard": true})
	var ticks := int(ceil(RumbleRing.SMASH_CHARGE_SEC / TICK)) + 1
	for _i in ticks:
		game.tick(TICK)
	game.handle_input(0, {"guard": false})
	assert_eq(game.hp[1], RumbleRing.MAX_HP - 2, "smash deals 2")
	assert_gt((game.positions[1] as Vector2).x, 3.0, "big knockback")


func test_short_guard_release_does_not_smash() -> void:
	var game := _game()
	_square_up(game, 0, 1)
	game.handle_input(0, {"guard": true})
	game.tick(TICK)
	game.handle_input(0, {"guard": false})
	assert_eq(game.hp[1], RumbleRing.MAX_HP)


func test_ko_scores_scatters_coins_and_respawns_with_invuln() -> void:
	var game := _game()
	game.hp[1] = 1
	_square_up(game, 0, 1)
	game.handle_input(0, {"attack": true})
	assert_eq(game.points[0], RumbleRing.KO_POINTS)
	assert_eq(game.coins.size(), RumbleRing.KO_COIN_SCATTER)
	assert_eq(game.hp[1], RumbleRing.MAX_HP, "respawns at full HP")
	assert_eq(game.positions[1], Vector2.ZERO)
	assert_gt(float(game.invuln_left[1]), 0.0)
	# Invulnerable players cannot be re-KO'd immediately.
	game.swing_cooldown[0] = 0.0
	game.positions[0] = Vector2(-1.0, 0.0)
	game.facings[0] = Vector2.RIGHT
	game.positions[1] = Vector2(0.0, 0.0)
	game.handle_input(0, {"attack": true})
	assert_eq(game.hp[1], RumbleRing.MAX_HP, "spawn protection")


func test_scattered_coins_are_collectable_and_become_pickup_coins() -> void:
	var game := _game()
	game.coins.append(Vector2(0.0, 0.0))
	game.positions[0] = Vector2(0.1, 0.0)
	game.tick(TICK)
	assert_eq(game.collected[0], 1)
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().pickup_coins[0], 1)


func test_most_ko_points_wins_ties_grouped() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game.points = {0: 3, 1: 6, 2: 3}
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_eq(game.get_results().placements, [[1], [0, 2]])


func test_snapshot_shape_and_events() -> void:
	var game := _game()
	_square_up(game, 0, 1)
	game.handle_input(0, {"attack": true})
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players[0].size(), 8)
	var types: Array = snapshot.events.map(func(e: Dictionary) -> String: return e.type)
	assert_has(types, "swing")
	assert_has(types, "hit")
	game.tick(TICK)
	assert_eq(game.get_snapshot().events, [], "events last one tick")
