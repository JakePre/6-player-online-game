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
	assert_eq(meta.max_players, 8, "M15: 8 by design, not scaled further")
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"rumble_ring") is RumbleRing)
	MinigameCatalog.clear()


## M15: the ring itself is unscaled by design, but the starting spread must
## still keep 8 fighters clear of each other's melee range.
func test_eight_players_spawn_without_overlap() -> void:
	var player_slots: Array[int] = []
	for slot in 8:
		player_slots.append(slot)
	var game := _game(player_slots)
	assert_eq(game.positions.size(), 8)
	for i in player_slots.size():
		for j in range(i + 1, player_slots.size()):
			var apart: float = game.positions[player_slots[i]].distance_to(
				game.positions[player_slots[j]]
			)
			assert_gt(apart, RumbleRing.PLAYER_RADIUS * 2.0, "no two spawns overlap at 8")


## M15: a fuller ring KOs more often, so several respawns can land the same
## tick — jittering must actually spread them, not just theoretically allow it.
func test_simultaneous_respawns_do_not_stack() -> void:
	var game := _game([0, 1, 2] as Array[int])
	for slot in [0, 1, 2]:
		game.hp[slot] = 1
		game.invuln_left[slot] = 0.0
		game._damage(slot, (slot + 1) % 3, 1, Vector2.ZERO)
	var a: Vector2 = game.positions[0]
	var b: Vector2 = game.positions[1]
	var c: Vector2 = game.positions[2]
	assert_true(a != b or b != c or a != c, "three same-tick respawns do not all land on one point")


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


func test_swing_connects_at_the_side_of_the_arc() -> void:
	# #257: the arc is a full frontal 180 — perpendicular still counts.
	var game := _game()
	game.positions[0] = Vector2(1.0, 0.0)
	game.positions[1] = Vector2(1.0, 1.2)
	game.facings[0] = Vector2.RIGHT
	game.handle_input(0, {"attack": true})
	assert_eq(game.hp[1], RumbleRing.MAX_HP - 1, "perpendicular is inside the 180° arc")
	game.swing_cooldown[0] = 0.0
	game.positions[1] = Vector2(0.4, 1.0)
	game.handle_input(0, {"attack": true})
	assert_eq(game.hp[1], RumbleRing.MAX_HP - 1, "behind the shoulder still whiffs")


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


## #1066 (owner-approved: stamina + chip): a guarded hit still leaks a
## quarter of its shove and bites the meter — beating on a turtle cracks it.
func test_guarded_hit_chips_knockback_and_stamina() -> void:
	var game := _game()
	_square_up(game, 0, 1)
	game.handle_input(1, {"guard": true})
	var pos_before: float = (game.positions[1] as Vector2).x
	var stamina_before: float = game.stamina[1]
	game.handle_input(0, {"attack": true})
	assert_eq(game.hp[1], RumbleRing.MAX_HP, "still no HP through the guard")
	assert_almost_eq(
		(game.positions[1] as Vector2).x - pos_before,
		RumbleRing.SWING_KNOCKBACK * RumbleRing.CHIP_KNOCKBACK_MULT,
		0.001,
		"a quarter of the shove leaks through"
	)
	assert_almost_eq(
		float(game.stamina[1]),
		stamina_before - RumbleRing.CHIP_STAMINA_PER_HP,
		0.001,
		"the block bites the meter"
	)


## #1066: holding guard drains stamina; empty = guard break + a stagger that
## swallows swings and re-guards, and full damage lands while broken.
func test_guard_drains_to_a_break_and_stagger() -> void:
	var game := _game()
	_square_up(game, 0, 1)
	game.handle_input(1, {"guard": true})
	var ticks := int(RumbleRing.GUARD_STAMINA_SEC / TICK) + 2
	for _i in ticks:
		game.tick(TICK)
	assert_false(bool(game.guarding[1]), "empty meter drops the guard")
	assert_gt(float(game.stagger[1]), 0.0, "and staggers")
	game.handle_input(1, {"attack": true})
	assert_eq(game.swing_cooldown[1], 0.0, "staggered swings are swallowed")
	game.handle_input(1, {"guard": true})
	assert_false(bool(game.guarding[1]), "staggered re-guard is swallowed")
	game.handle_input(0, {"attack": true})
	assert_eq(game.hp[1], RumbleRing.MAX_HP - 1, "full damage lands while broken")


## #1066: the meter refills while not guarding, at the regen rate.
func test_stamina_regenerates_when_not_guarding() -> void:
	var game := _game()
	game.stamina[0] = 0.0
	game.stagger[0] = 0.0
	for _i in 30:
		game.tick(TICK)
	assert_almost_eq(
		float(game.stamina[0]), RumbleRing.GUARD_REGEN_MULT * 30.0 * TICK, 0.02, "regen rate"
	)


## #1066: a break is not a release — no free smash on the way down, even at
## a full charge.
func test_guard_break_does_not_fire_the_smash() -> void:
	var game := _game()
	_square_up(game, 1, 0)
	game.handle_input(1, {"guard": true})
	game.stamina[1] = TICK * 0.5  # about to run dry, well past SMASH_CHARGE_SEC
	game._guard_held_sec[1] = RumbleRing.SMASH_CHARGE_SEC + 1.0
	game.tick(TICK)
	assert_false(bool(game.guarding[1]), "broke")
	assert_eq(game.hp[0], RumbleRing.MAX_HP, "no smash fired at the neighbor")


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
	assert_lte(
		(game.positions[1] as Vector2).length(),
		RumbleRing.RESPAWN_JITTER_RADIUS,
		"respawns near center (M15: jittered so simultaneous respawns don't stack)"
	)
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
	assert_eq(snapshot.players[0].size(), RumbleRing.PS_COUNT)
	var types: Array = snapshot.events.map(func(e: Dictionary) -> String: return e.type)
	assert_has(types, "swing")
	assert_has(types, "hit")
	game.tick(TICK)
	assert_eq(game.get_snapshot().events, [], "events last one tick")
