extends GutTest
## Magma Ascent (#936, finale variant build 3): shop loadouts, the rising +
## accelerating magma, shield/extra-life saves vs elimination on a lick,
## crumble ledges + sabotage, height/survival ranking, and last-one-standing.

const TICK := 1.0 / 30.0


func _game(count: int = 3) -> MagmaAscent:
	var game := MagmaAscent.new()
	game.meta = MagmaAscent.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 42)
	return game


func test_meta_and_registry() -> void:
	assert_eq(MagmaAscent.make_meta().id, &"magma_ascent")
	assert_true(FinaleVariants.is_finale(&"magma_ascent"))
	assert_true(FinaleVariants.instantiate(&"magma_ascent") is MagmaAscent)
	assert_eq(FinaleVariants.display_name(&"magma_ascent"), "Magma Ascent")


func test_loadouts_map_to_survival_tools() -> void:
	var game := _game()
	game.apply_loadouts(
		{0: {"items": {&"extra_life": 2, &"shield": 1, &"speed_boost": 1, &"sabotage_token": 1}}}
	)
	assert_eq(game.lives[0], 2, "extra lives = respawns above the magma")
	assert_true(game.shields[0])
	assert_true(game.speed_boosts[0])
	assert_eq(game.sabotage_tokens[0], 1)


func test_magma_rises_and_accelerates() -> void:
	var game := _game()
	var start := game.magma_y
	game.tick(TICK)
	var first_step := game.magma_y - start
	# Jump ahead in time so the accel term dominates, then compare a step.
	game.elapsed = 60.0
	var before := game.magma_y
	game.tick(TICK)
	var late_step := game.magma_y - before
	assert_gt(first_step, 0.0, "the magma rises")
	assert_gt(late_step, first_step, "and rises faster later (accelerating)")


func test_shield_shrugs_a_lick_then_extra_life_then_elimination() -> void:
	var game := _game(2)
	game.apply_loadouts({0: {"items": {&"shield": 1, &"extra_life": 1}}})
	# Drop the climber into the magma repeatedly; each catch consumes a save.
	game.magma_y = 5.0
	game.sim.body_of(0).pos = Vector2(0.0, 0.0)  # well under the magma line
	game._check_magma_catches()
	assert_false(game.shields[0], "the shield took the first lick")
	assert_false(bool(game.eliminated[0]), "survived, lifted above the magma")
	game.sim.body_of(0).pos = Vector2(0.0, 0.0)
	game._check_magma_catches()
	assert_eq(game.lives[0], 0, "the extra life took the second")
	assert_false(bool(game.eliminated[0]))
	game.sim.body_of(0).pos = Vector2(0.0, 0.0)
	game._check_magma_catches()
	assert_true(bool(game.eliminated[0]), "no saves left -> eliminated")


func test_a_lick_lifts_a_survivor_above_the_magma() -> void:
	var game := _game(2)
	game.apply_loadouts({0: {"items": {&"shield": 1}}})
	game.magma_y = 5.0
	game.sim.body_of(0).pos = Vector2(2.0, 0.0)
	game._check_magma_catches()
	assert_gt(
		float(game.sim.body_of(0).pos.y),
		game.magma_y,
		"lifted clear of the magma line, not left to re-touch"
	)


func test_last_climber_standing_wins() -> void:
	var game := _game(2)
	game.eliminated[1] = true
	game.sim.remove_body(1)
	game._pending_elims.append(1)
	game.tick(TICK)
	assert_true(game.finished, "one climber left ends it")
	assert_eq(game.get_results().placements[0], [0], "the survivor wins")
	assert_eq(game.get_results().placements[1], [1], "the fallen rank after")


func test_ranking_orders_survivors_by_height_then_the_fallen() -> void:
	var game := _game(3)
	game.peak_height[0] = 8.0
	game.peak_height[1] = 20.0
	game.eliminated[2] = true
	game.elimination_order = [[2]]
	var placements := game._rank_players()
	assert_eq(placements[0], [1], "higher survivor first")
	assert_eq(placements[1], [0], "then the lower survivor")
	assert_eq(placements[2], [2], "then the eliminated")


func test_sabotage_crumbles_the_target_ledge() -> void:
	var game := _game(2)
	game.sabotage_tokens[0] = 1
	# Park the victim standing on the first crumble ledge.
	var index: int = MagmaAscent._crumble_indices()[0]
	var rect := MagmaAscent.ledges()[index]
	game.sim.body_of(1).pos = Vector2(rect.get_center().x, rect.position.y + rect.size.y + 0.5)
	game.sim.body_of(1).grounded = true
	game.handle_input(0, {"sabotage": 1})
	assert_eq(game.sabotage_tokens[0], 0, "token spent")
	assert_true(game._sabotaged.has(index), "the victim's ledge is forced gone")
	game.tick(TICK)
	assert_false(game.crumble_state[index], "and drops out from under them")


func test_sabotage_needs_the_target_on_a_crumble_ledge() -> void:
	var game := _game(2)
	game.sabotage_tokens[0] = 1
	game.sim.body_of(1).pos = Vector2(0.0, 20.0)  # mid-air, not on any ledge
	game.sim.body_of(1).grounded = false
	game.handle_input(0, {"sabotage": 1})
	assert_eq(game.sabotage_tokens[0], 1, "no ledge under them -> token not spent")


func test_snapshot_shape() -> void:
	var game := _game()
	var snap := game.get_snapshot()
	for key in ["players", "magma_y", "crumble"]:
		assert_true(snap.has(key), "%s replicates" % key)
	assert_eq((snap.players[0] as Array).size(), MagmaAscent.PS_COUNT)
	assert_eq((snap.crumble as Array).size(), MagmaAscent.LEDGE_COUNT)
