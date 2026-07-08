extends GutTest
## Knock-Off (M14-03): platform fighter on the side-scroll bones — two jumps,
## jab/smash melee, percent-scaled knockback, single-stock ring-out, and
## last-duck-standing placement.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> KnockOff:
	var game := KnockOff.new()
	game.meta = KnockOff.make_meta()
	game.setup(player_slots, 42)
	return game


func _to_fight(game: KnockOff) -> void:
	while game.phase == KnockOff.Phase.COUNTDOWN and not game.finished:
		game.tick(TICK)


func test_meta_and_catalog() -> void:
	var meta := KnockOff.make_meta()
	assert_eq(meta.id, &"knock_off")
	assert_eq(meta.max_players, 8)
	assert_false(meta.controls_text.is_empty())
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"knock_off") is KnockOff)
	MinigameCatalog.clear()


func test_setup_spawns_on_the_stage_with_two_jumps() -> void:
	var game := _game([0, 1, 2] as Array[int])
	assert_eq(game.fighters.size(), 3)
	assert_eq(game.sim.max_air_jumps, KnockOff.AIR_JUMPS, "one air jump = two total")
	for slot in [0, 1, 2]:
		assert_true(bool(game.fighters[slot].alive))
		assert_almost_eq(float(game.fighters[slot].percent), 0.0, 0.001, "fresh at 0%")


func test_countdown_freezes_attacks_then_fight_frees_them() -> void:
	var game := _game()
	game.sim.body_of(0).pos = Vector2(0.0, 0.5)
	game.sim.body_of(1).pos = Vector2(1.0, 0.5)
	game.handle_input(0, {"jab": true})
	assert_almost_eq(float(game.fighters[1].percent), 0.0, 0.001, "no jabbing mid-countdown")
	_to_fight(game)
	game.sim.body_of(0).pos = Vector2(0.0, 0.5)
	game.sim.body_of(0).facing = 1
	game.sim.body_of(1).pos = Vector2(1.0, 0.5)
	game.handle_input(0, {"jab": true})
	assert_gt(float(game.fighters[1].percent), 0.0, "FIGHT frees the jab")


func test_jab_hits_in_front_not_behind() -> void:
	var game := _game([0, 1, 2] as Array[int])
	_to_fight(game)
	game.sim.body_of(0).pos = Vector2(0.0, 0.5)
	game.sim.body_of(0).facing = 1
	game.sim.body_of(1).pos = Vector2(1.0, 0.5)  # in front
	game.sim.body_of(2).pos = Vector2(-1.0, 0.5)  # behind
	game.handle_input(0, {"jab": true})
	assert_gt(float(game.fighters[1].percent), 0.0, "the duck in front takes damage")
	assert_almost_eq(float(game.fighters[2].percent), 0.0, 0.001, "the one behind is untouched")


func test_knockback_grows_with_the_victims_percent() -> void:
	var game := _game()
	_to_fight(game)
	game.sim.body_of(1).pos = Vector2(2.0, 0.5)
	game._land_hit(1, game.fighters[1], 1.0, 0.0, KnockOff.JAB_BASE_KB)
	var fresh_kick := float(game.sim.body_of(1).vel.x)
	game.fighters[1].percent = 120.0
	game.sim.body_of(1).vel = Vector2.ZERO
	game._land_hit(1, game.fighters[1], 1.0, 0.0, KnockOff.JAB_BASE_KB)
	var battered_kick := float(game.sim.body_of(1).vel.x)
	assert_gt(battered_kick, fresh_kick, "a battered duck flies further")


func test_smash_launches_harder_than_a_jab() -> void:
	var game := _game([0, 1] as Array[int])
	_to_fight(game)
	game.sim.body_of(0).pos = Vector2(0.0, 0.5)
	game.sim.body_of(0).facing = 1
	game.sim.body_of(1).pos = Vector2(1.0, 0.5)
	game.handle_input(0, {"smash": true})
	var smash_kick := float(game.sim.body_of(1).vel.x)
	assert_gt(smash_kick, KnockOff.JAB_BASE_KB, "smash beats a bare jab's base")
	assert_gt(float(game.fighters[1].percent), KnockOff.JAB_DAMAGE, "and adds more damage")


func test_attacks_respect_a_cooldown() -> void:
	var game := _game()
	_to_fight(game)
	game.sim.body_of(0).pos = Vector2(0.0, 0.5)
	game.sim.body_of(0).facing = 1
	game.sim.body_of(1).pos = Vector2(1.0, 0.5)
	game.handle_input(0, {"jab": true})
	var after_one := float(game.fighters[1].percent)
	game.handle_input(0, {"jab": true})  # same tick, still cooling
	assert_almost_eq(float(game.fighters[1].percent), after_one, 0.001, "no double-tap")


func test_falling_off_the_stage_is_a_ko() -> void:
	var game := _game()
	_to_fight(game)
	game.sim.body_of(0).pos = Vector2(0.0, -20.0)  # into the void
	game.tick(TICK)
	assert_false(bool(game.fighters[0].alive), "off the bottom is out")
	assert_false(game.sim.has_body(0), "the body leaves the stage")


func test_last_duck_standing_wins() -> void:
	var game := _game([0, 1, 2] as Array[int])
	_to_fight(game)
	game.sim.body_of(1).pos = Vector2(0.0, -20.0)
	game.sim.body_of(2).pos = Vector2(0.0, -20.0)
	game.tick(TICK)
	assert_true(game.finished, "one left ends the round")
	var placements: Array = game.get_results().placements
	assert_eq(placements[0], [0], "the survivor wins")
	assert_eq(placements[-1], [1], "the first off the stage places last")


func test_timeout_ranks_survivors_by_least_damage() -> void:
	var game := _game([0, 1] as Array[int])
	_to_fight(game)
	game.fighters[0].percent = 90.0
	game.fighters[1].percent = 20.0
	game.phase_left = 0.0
	game.tick(TICK)
	assert_true(game.finished, "the clock ran out")
	assert_eq(game.get_results().placements[0], [1], "the cleaner duck ranks first")


func test_snapshot_shape_and_junk_input() -> void:
	var game := _game()
	_to_fight(game)
	game.handle_input(0, {"bogus": true})
	game.handle_input(9, {"smash": true})
	game.tick(TICK)
	var snap := game.get_snapshot()
	assert_true(snap.has("players") and snap.has("phase") and snap.has("phase_left"))
	assert_eq((snap.players[0] as Array).size(), KnockOff.PS_COUNT)
	assert_true(int(snap.players[0][KnockOff.PS_ALIVE]) == 1, "alive bit set")
