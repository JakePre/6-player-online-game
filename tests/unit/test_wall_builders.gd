extends GutTest
## Wall Builders (PHASE2.md $4 #27): carry/deliver stacking, wall raids,
## carrier bumps, win/timeout ranking, and the even-players rule.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2, 3]) -> WallBuilders:
	var game := WallBuilders.new()
	game.meta = WallBuilders.make_meta()
	game.setup(player_slots, 42)
	return game


func test_meta_catalog_and_even_rule() -> void:
	var meta := WallBuilders.make_meta()
	assert_eq(meta.id, &"wall_builders")
	assert_true(meta.even_players, "never drafted at 3 or 5 (#178)")
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"wall_builders") is WallBuilders)
	MinigameCatalog.clear()


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
	game.wall_heights[1] = WallBuilders.WIN_HEIGHT
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
