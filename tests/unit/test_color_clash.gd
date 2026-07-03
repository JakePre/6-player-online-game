extends GutTest
## Color Clash (SPEC $7 #14): tile painting/stealing, FFA at 2-3 players,
## two teams at 4-6 with team_mode routing, timeout ranking, and ties.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> ColorClash:
	var game := ColorClash.new()
	game.meta = ColorClash.make_meta()
	game.setup(player_slots, 42)
	return game


func _tile_at(game: ColorClash, world: Vector2) -> int:
	var col := int(floor((world.x + ColorClash.ARENA_HALF) / ColorClash.TILE_WORLD))
	var row := int(floor((world.y + ColorClash.ARENA_HALF) / ColorClash.TILE_WORLD))
	return game.grid[row * ColorClash.GRID_SIZE + col]


func test_meta() -> void:
	var meta := ColorClash.make_meta()
	assert_eq(meta.id, &"color_clash")
	assert_eq(meta.category, MinigameMeta.Category.TEAM)
	assert_eq(meta.min_players, 2)


func test_registered_in_catalog() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"color_clash") is ColorClash)
	MinigameCatalog.clear()


func test_ffa_below_four_players() -> void:
	for count: int in [2, 3]:
		var player_slots: Array[int] = []
		for slot in count:
			player_slots.append(slot)
		var game := _game(player_slots)
		assert_false(game.team_mode, "%d players is FFA" % count)
		assert_eq(game.teams, [])
		for slot: int in player_slots:
			assert_eq(game.faction_of[slot], slot)


func test_odd_counts_fall_back_to_ffa() -> void:
	var game := _game([0, 1, 2, 3, 4] as Array[int])
	assert_false(game.team_mode, "3v2 paint is never fun (#178)")
	assert_eq(game.teams, [])


func test_teams_at_even_counts_from_four() -> void:
	for count: int in [4, 6]:
		var player_slots: Array[int] = []
		for slot in count:
			player_slots.append(slot)
		var game := _game(player_slots)
		assert_true(game.team_mode, "%d players is teams" % count)
		assert_eq(game.teams.size(), 2)
		assert_eq(game.teams[0].size(), count / 2, "%d players" % count)
		assert_eq(game.teams[1].size(), count / 2, "%d players" % count)


func test_walking_paints_tiles() -> void:
	var game := _game()
	game.positions[0] = Vector2(-5.0, -5.0)
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	game.tick(TICK)
	assert_eq(_tile_at(game, game.positions[0]), 0)


func test_repainting_steals_the_tile() -> void:
	var game := _game()
	var spot := Vector2(3.0, 3.0)
	game.positions[0] = spot
	game.tick(TICK)
	game.positions[0] = Vector2(-8.0, -8.0)
	game.positions[1] = spot
	game.tick(TICK)
	assert_eq(_tile_at(game, spot), 1)


func test_ffa_ranking_by_tile_count() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game.grid.fill(ColorClash.UNPAINTED)
	for i in 5:
		game.grid[i] = 1
	for i in range(5, 8):
		game.grid[i] = 0
	game.grid[9] = 2
	game.duration_override = TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0], [2]])
	assert_false(game.get_results().team_mode)


func test_ffa_ties_grouped() -> void:
	var game := _game()
	game.grid.fill(ColorClash.UNPAINTED)
	game.grid[0] = 0
	game.grid[1] = 1
	game.duration_override = TICK
	game.tick(TICK)
	assert_eq(game.get_results().placements, [[0, 1]])


func test_team_ranking_reports_teams_best_first() -> void:
	var game := _game([0, 1, 2, 3] as Array[int])
	game.grid.fill(ColorClash.UNPAINTED)
	for i in 4:
		game.grid[i] = 1
	game.grid[10] = 0
	game.duration_override = TICK
	game.tick(TICK)
	assert_true(game.finished)
	var results := game.get_results()
	assert_true(results.team_mode)
	assert_eq(results.placements, [game.teams[1], game.teams[0]])


func test_team_dead_heat_is_a_full_tie() -> void:
	var game := _game([0, 1, 2, 3] as Array[int])
	game.grid.fill(ColorClash.UNPAINTED)
	game.grid[0] = 0
	game.grid[1] = 1
	game.duration_override = TICK
	game.tick(TICK)
	assert_eq(game.get_results().placements, [[0, 1, 2, 3]])


func test_spawn_tiles_painted_at_setup() -> void:
	var game := _game()
	var counts := game._tile_counts()
	assert_eq(int(counts.get(0, 0)) + int(counts.get(1, 0)), 2)


func test_snapshot_shape() -> void:
	var game := _game()
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 2)
	assert_eq(snapshot.players[0].size(), 3)
	assert_eq(snapshot.grid.size(), ColorClash.GRID_SIZE * ColorClash.GRID_SIZE)
	assert_eq(snapshot.teams, [])
	assert_true(snapshot.counts.size() >= 1)
