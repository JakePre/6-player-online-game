extends GutTest
## Thin Ice (SPEC $7 #4): tile damage progression, falling through gone
## tiles, fall ordering with ties, timeout ranking, and 2/4/6-player setup.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> ThinIce:
	var game := ThinIce.new()
	game.meta = ThinIce.make_meta()
	game.setup(player_slots, 42)
	return game


func test_meta() -> void:
	var meta := ThinIce.make_meta()
	assert_eq(meta.id, &"thin_ice")
	assert_eq(meta.category, MinigameMeta.Category.FFA)
	assert_eq(meta.min_players, 2)
	assert_eq(meta.max_players, 12)


func test_registered_in_catalog() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	var game := MinigameCatalog.instantiate(&"thin_ice")
	assert_true(game is ThinIce)
	assert_eq(game.meta.id, &"thin_ice")


func test_spawns_scale_with_player_count() -> void:
	for count: int in [2, 4, 6]:
		var player_slots: Array[int] = []
		for slot in count:
			player_slots.append(slot)
		var game := _game(player_slots)
		assert_eq(game.positions.size(), count)
		# <=6 players is the baseline: the grid stays at ThinIce.GRID_SIZE.
		assert_eq(game.tiles.size(), ThinIce.GRID_SIZE * ThinIce.GRID_SIZE)
		for slot: int in player_slots:
			var pos: Vector2 = game.positions[slot]
			assert_almost_eq(pos.length(), game._half_extent * 0.6, 0.001, "%d players" % count)


## M15: grid area scales with player count (sqrt of MinigameScaling.growth),
## so tiles-per-player density stays close to the 6-player baseline instead
## of the destruction rate spiking with more feet on a fixed-size grid.
func test_grid_scales_at_twelve_players_and_density_holds() -> void:
	var baseline := _game([0, 1, 2, 3, 4, 5] as Array[int])
	var baseline_density := float(baseline.tiles.size()) / 6.0

	var player_slots: Array[int] = []
	for i in 12:
		player_slots.append(i)
	var game := _game(player_slots)
	assert_gt(game._grid_size, ThinIce.GRID_SIZE, "the grid grows for a crowd")
	assert_eq(game.tiles.size(), game._grid_size * game._grid_size)
	var density := float(game.tiles.size()) / 12.0
	assert_almost_eq(density, baseline_density, 1.0, "tiles-per-player density holds steady")
	for slot in 12:
		var pos: Vector2 = game.positions[slot]
		assert_lte(pos.length(), game._half_extent, "spawn stays inside the scaled arena")


func test_max_players_raised_to_twelve() -> void:
	assert_eq(ThinIce.make_meta().max_players, 12)


func test_starting_tiles_are_intact() -> void:
	var game := _game()
	for state: int in game.tiles:
		assert_eq(state, ThinIce.TileState.INTACT)


func test_movement() -> void:
	var game := _game()
	game.positions[0] = Vector2.ZERO
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	game.tick(1.0)
	assert_almost_eq(game.positions[0].x, ThinIce.MOVE_SPEED, 0.2)


func test_entering_a_tile_cracks_it() -> void:
	var game := _game()
	game.positions[0] = Vector2.ZERO
	game.last_tile[0] = Vector2i(-1, -1)
	game.tick(TICK)
	var idx: int = game._tile_index(game._tile_of(Vector2.ZERO))
	assert_eq(game.tiles[idx], ThinIce.TileState.CRACKED)


func test_entering_a_cracked_tile_starts_a_telegraphed_collapse() -> void:
	var game := _game([0, 1] as Array[int])
	var idx: int = game._tile_index(game._tile_of(Vector2.ZERO))
	game.tiles[idx] = ThinIce.TileState.CRACKED
	game.positions[0] = Vector2.ZERO
	game.last_tile[0] = Vector2i(-1, -1)
	game.tick(TICK)
	assert_eq(game.tiles[idx], ThinIce.TileState.BREAKING, "flashes first (#138)")
	assert_true(game._is_in(0), "the escape window is real")
	# Staying put through the collapse is what drops you.
	var ticks := int(ceil(ThinIce.COLLAPSE_SEC / TICK)) + 1
	for _i in ticks:
		game.tick(TICK)
	assert_eq(game.tiles[idx], ThinIce.TileState.GONE)
	assert_false(game._is_in(0), "stood on it to the end")


func test_escaping_a_breaking_tile_survives() -> void:
	var game := _game([0, 1] as Array[int])
	var idx: int = game._tile_index(game._tile_of(Vector2.ZERO))
	game.tiles[idx] = ThinIce.TileState.BREAKING
	game._collapse_left[idx] = ThinIce.COLLAPSE_SEC
	game.positions[0] = Vector2(ThinIce.TILE_SIZE * 1.6, 0.0)
	game.last_tile[0] = game._tile_of(game.positions[0])
	var ticks := int(ceil(ThinIce.COLLAPSE_SEC / TICK)) + 1
	for _i in ticks:
		game.tick(TICK)
	assert_eq(game.tiles[idx], ThinIce.TileState.GONE)
	assert_true(game._is_in(0), "moved off in time")


func test_standing_on_a_tile_that_gives_way_drops_you_too() -> void:
	var game := _game([0, 1, 2] as Array[int])
	var tile := game._tile_of(Vector2.ZERO)
	var idx: int = game._tile_index(tile)
	game.tiles[idx] = ThinIce.TileState.CRACKED
	# Both 0 and 1 stand on the doomed tile; 1 steps onto it fresh, starting
	# the collapse — after it expires, 0 (who never moved) falls too.
	game.positions[0] = Vector2.ZERO
	game.last_tile[0] = tile
	game.positions[1] = Vector2.ZERO
	game.last_tile[1] = Vector2i(-1, -1)
	for _i in int(ceil(ThinIce.COLLAPSE_SEC / TICK)) + 2:
		game.tick(TICK)
	assert_false(game._is_in(0))
	assert_false(game._is_in(1))
	assert_true(game.finished, "only slot 2 remains standing")
	assert_eq(game.get_results().placements, [[2], [0, 1]])
	assert_eq(game.fall_order, [[0, 1]])


func test_fall_order_becomes_placements() -> void:
	var game := _game([0, 1, 2] as Array[int])
	for slot: Variant in [2, 0]:
		var idx: int = game._tile_index(game._tile_of(game.positions[slot]))
		game.tiles[idx] = ThinIce.TileState.GONE
		game.last_tile[slot] = Vector2i(-1, -1)
		game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0], [2]])
	assert_eq(game.get_results().pickup_coins, {})


func test_fallen_players_ignore_input_and_snapshot() -> void:
	var game := _game([0, 1, 2] as Array[int])
	var idx: int = game._tile_index(game._tile_of(game.positions[0]))
	game.tiles[idx] = ThinIce.TileState.GONE
	game.last_tile[0] = Vector2i(-1, -1)
	game.tick(TICK)
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	assert_eq(game.move_dirs[0], Vector2.ZERO, "fallen players cannot steer")
	var snapshot := game.get_snapshot()
	assert_false(snapshot.players.has(0))
	assert_eq(snapshot.fallen, [[0]])


func test_timeout_survivors_tie_ahead_of_fallen() -> void:
	var game := _game([0, 1, 2] as Array[int])
	var idx: int = game._tile_index(game._tile_of(game.positions[2]))
	game.tiles[idx] = ThinIce.TileState.GONE
	game.last_tile[2] = Vector2i(-1, -1)
	game.tick(TICK)
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0, 1], [2]])


func test_last_one_standing_ends_the_round_early() -> void:
	var game := _game([0, 1] as Array[int])
	var idx: int = game._tile_index(game._tile_of(game.positions[0]))
	game.tiles[idx] = ThinIce.TileState.GONE
	game.last_tile[0] = Vector2i(-1, -1)
	game.tick(TICK)
	assert_true(game.finished)
	assert_lt(game.elapsed, game.meta.duration_sec)


func test_snapshot_shape() -> void:
	var game := _game()
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.grid_size, ThinIce.GRID_SIZE)
	assert_eq(snapshot.tile_size, ThinIce.TILE_SIZE)
	assert_eq(snapshot.tiles.size(), ThinIce.GRID_SIZE * ThinIce.GRID_SIZE)
	assert_eq(snapshot.players.size(), 2)
	assert_eq(snapshot.players[0].size(), ThinIce.PS_COUNT)
	assert_eq(snapshot.fallen, [])


func test_standing_still_damages_the_tile_underfoot() -> void:
	var game := _game()
	var idx: int = game._tile_index(game._tile_of(game.positions[0]))
	# Entry cracked it on the first resolve; camping walks it to BREAKING
	# and then GONE without the player ever moving (#167).
	var ticks := int(ceil(ThinIce.STAND_DAMAGE_SEC / TICK)) + 2
	for _i in ticks:
		game.tick(TICK)
	assert_eq(game.tiles[idx], ThinIce.TileState.CRACKED, "entry damage on setup resolve")
	for _i in ticks:
		game.tick(TICK)
	assert_true(game.tiles[idx] >= ThinIce.TileState.BREAKING, "camping breaks the ice under you")


func test_moving_resets_the_standing_clock() -> void:
	var game := _game()
	var half := int(ThinIce.STAND_DAMAGE_SEC / TICK / 2.0)
	for _i in half:
		game.tick(TICK)
	# Step to a fresh tile: its damage is the entry crack only.
	game.positions[0] = game.positions[0] + Vector2(ThinIce.TILE_SIZE, 0.0)
	game.tick(TICK)
	var idx: int = game._tile_index(game.last_tile[0])
	for _i in half:
		game.tick(TICK)
	assert_eq(game.tiles[idx], ThinIce.TileState.CRACKED, "clock restarted on the new tile")
