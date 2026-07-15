extends GutTest
## Wall Builders (PHASE2.md $4 #27): carry/deliver stacking, wall raids,
## carrier bumps, win/timeout ranking, and the even-players rule.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2, 3]) -> WallBuilders:
	var game := WallBuilders.new()
	game.meta = WallBuilders.make_meta()
	game.setup(player_slots, 42)
	return game


func _run_bot_round(count: int, seed_value: int) -> float:
	var game := WallBuilders.new()
	game.meta = WallBuilders.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, seed_value)
	var brains := {}
	for slot: int in game.slots:
		brains[slot] = BotBrains.brain_for(&"wall_builders", slot, seed_value)
	var t := 0.0
	while not game.finished and t < game.meta.duration_sec:
		var match_state := {"game": game.get_snapshot()}
		for slot: int in game.slots:
			game.handle_input(slot, brains[slot].think(match_state, {}))
		game.tick(TICK)
		t += TICK
	return t


## #961: the win target scales with builders-per-team so a bigger crew doesn't
## blitz a fixed target — per-builder work stays constant.
func test_win_target_scales_with_team_size() -> void:
	assert_eq(_game([0, 1, 2, 3] as Array[int]).win_height, WallBuilders.WIN_PER_BUILDER * 2)
	assert_eq(
		_game([0, 1, 2, 3, 4, 5, 6, 7] as Array[int]).win_height, WallBuilders.WIN_PER_BUILDER * 4
	)


## #961: bot rounds no longer collapse — the scaled target keeps the race a real
## length (≥40% of meta, the #933 bar) and count-independent instead of shrinking
## as the crew grows (was ~13s at 2v2 down to ~9s at 4v4).
func test_bot_rounds_are_a_real_length_across_crew_sizes() -> void:
	var floor_sec := WallBuilders.make_meta().duration_sec * 0.4
	for count: int in [4, 6, 8]:
		var lens: Array[float] = []
		for s in range(1, 6):
			lens.append(_run_bot_round(count, s))
		lens.sort()
		assert_gt(lens[2], floor_sec, "%d-bot median round clears the 40%%-of-meta floor" % count)


func test_meta_catalog_and_even_rule() -> void:
	var meta := WallBuilders.make_meta()
	assert_eq(meta.id, &"wall_builders")
	assert_eq(meta.max_players, 8)
	assert_true(meta.even_players, "never drafted at 3 or 5 (#178)")
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"wall_builders") is WallBuilders)
	MinigameCatalog.clear()


## No-crowd fairness (M15 8-cap): 4v4 splits evenly and every spawn stays
## within the arena.
func test_setup_splits_four_v_four_within_arena_at_eight_players() -> void:
	var player_slots: Array[int] = []
	for i in 8:
		player_slots.append(i)
	var game := _game(player_slots)
	assert_eq((game.teams[0] as Array).size(), 4)
	assert_eq((game.teams[1] as Array).size(), 4)
	for slot in 8:
		var pos: Vector2 = game.positions[slot]
		assert_lt(absf(pos.y), WallBuilders.ARENA_HALF, "spawn row stays inside the arena")
		assert_false(game.carrying[slot])


func test_grab_slows_and_delivery_stacks() -> void:
	var game := _game()
	var slot: int = game.teams[0][0]
	game.blocks.clear()
	game.blocks.append(game.positions[slot])
	game.tick(TICK)
	assert_true(game.carrying[slot])
	# Carriers crawl.
	game.positions[slot] = Vector2(0.0, 0.0)
	game.handle_input(slot, {"mx": 1.0, "my": 0.0})
	game.tick(TICK)
	assert_lt(
		(game.positions[slot] as Vector2).x,
		WallBuilders.MOVE_SPEED * TICK * 0.8,
		"carrying is slower"
	)
	# Delivering at the own wall stacks it.
	game.positions[slot] = game._own_wall_pos(slot)
	game.tick(TICK)
	assert_false(game.carrying[slot])
	assert_eq(int(game.wall_heights[0]), 1)


func test_raid_pries_a_block_after_contact_time() -> void:
	var game := _game()
	var raider: int = game.teams[1][0]
	game.wall_heights[0] = 3
	game.positions[raider] = game._enemy_wall_pos(raider)
	game.handle_input(raider, {"mx": 0.0, "my": 0.0})
	var ticks := int(ceil(WallBuilders.STEAL_SEC / TICK)) + 1
	for _i in ticks:
		game.positions[raider] = game._enemy_wall_pos(raider)
		game.tick(TICK)
	assert_eq(int(game.wall_heights[0]), 2, "one block pried off")
	assert_true(game.carrying[raider], "and hauled")


func test_bumping_a_carrier_drops_the_block() -> void:
	var game := _game()
	var carrier: int = game.teams[0][0]
	var bumper: int = game.teams[1][0]
	game.carrying[carrier] = true
	game.blocks.clear()
	game.positions[carrier] = Vector2(0.0, 0.0)
	game.positions[bumper] = Vector2(0.5, 0.0)
	game.tick(TICK)
	assert_false(game.carrying[carrier])
	assert_gt(game.blocks.size(), 0, "block hits the floor")


func test_teammate_contact_is_safe() -> void:
	var game := _game()
	var carrier: int = game.teams[0][0]
	var friend: int = game.teams[0][1]
	game.carrying[carrier] = true
	game.blocks.clear()
	game.positions[carrier] = Vector2(0.0, 0.0)
	game.positions[friend] = Vector2(0.5, 0.0)
	game.tick(TICK)
	assert_true(game.carrying[carrier], "friends don't strip your block")


func test_win_at_target_height() -> void:
	var game := _game()
	game.wall_heights[1] = game.win_height
	game.tick(TICK)
	assert_true(game.finished)
	var results := game.get_results()
	assert_true(results.team_mode)
	assert_eq(results.placements, [game.teams[1], game.teams[0]])


func test_timeout_compares_heights_dead_heat_ties() -> void:
	var game := _game()
	game.wall_heights = [4, 4]
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements.size(), 1, "dead heat is a full tie")


func test_snapshot_shape() -> void:
	var game := _game()
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 4)
	assert_eq(snapshot.walls, [0, 0])
	assert_gt(snapshot.blocks.size(), 0)
	assert_eq(snapshot.teams.size(), 2)
