extends GutTest
## Blast Grid server simulation (M14-06): grid construction, wall collision,
## bomb fuse + cross blast, soft-wall destruction, power-ups, chain
## detonation, KO / last-standing ranking.

const TICK := 1.0 / 30.0
const G := BlastGrid.GRID


func _game(count: int = 2) -> BlastGrid:
	var game := BlastGrid.new()
	game.meta = BlastGrid.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 42)
	return game


func _cell(r: int, c: int) -> int:
	return r * G + c


## Clears soft walls off a row so a blast test controls its own corridor.
func _clear_row(game: BlastGrid, r: int) -> void:
	for c in range(1, G - 1):
		if game.grid[_cell(r, c)] == BlastGrid.Cell.SOFT:
			game.grid[_cell(r, c)] = BlastGrid.Cell.EMPTY


func _place(game: BlastGrid, slot: int, cell: int) -> void:
	game.positions[slot] = game._cell_center(cell)


func test_meta_and_catalog() -> void:
	var meta := BlastGrid.make_meta()
	assert_eq(meta.id, &"blast_grid")
	assert_eq(meta.category, MinigameMeta.Category.FFA)
	assert_eq(meta.min_players, 2)
	assert_eq(meta.max_players, 8)
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"blast_grid") is BlastGrid)
	MinigameCatalog.clear()


func test_grid_has_solid_border_and_open_spawns() -> void:
	var game := _game(4)
	# Border ring is solid.
	for c in G:
		assert_eq(game.grid[_cell(0, c)], BlastGrid.Cell.SOLID, "top border solid")
		assert_eq(game.grid[_cell(G - 1, c)], BlastGrid.Cell.SOLID, "bottom border solid")
	# An interior even/even cell is a pillar.
	assert_eq(game.grid[_cell(2, 2)], BlastGrid.Cell.SOLID, "interior pillar")
	# Spawn corners are open, and each player stands on an EMPTY cell.
	for slot in 4:
		assert_eq(
			game.grid[game._cell_at(game.positions[slot])],
			BlastGrid.Cell.EMPTY,
			"player %d spawns on an open cell" % slot
		)


func test_walls_block_movement() -> void:
	var game := _game()
	# Sit just left of the (2,2) pillar and push right into it.
	_place(game, 0, _cell(2, 1))
	game.handle_input(0, {"mx": 1.0, "my": 0.0})
	var start_x: float = game.positions[0].x
	for _i in 20:
		game.handle_input(0, {"mx": 1.0, "my": 0.0})
		game.tick(TICK)
	assert_lt(game._cell_at(game.positions[0]), _cell(2, 2), "cannot walk into the pillar")
	assert_ne(game.grid[game._cell_at(game.positions[0])], BlastGrid.Cell.SOLID)


func test_bomb_detonates_after_fuse_and_flames_the_cross() -> void:
	var game := _game()
	_clear_row(game, 1)
	_place(game, 0, _cell(1, 1))
	_place(game, 1, _cell(1, 9))  # far and safe
	game.handle_input(0, {"bomb": true})
	assert_eq(game.bombs.size(), 1, "bomb dropped")
	# Not yet.
	game.tick(TICK)
	assert_true(game.flames.is_empty(), "no flame before the fuse ends")
	# Run out the fuse.
	for _i in int(BlastGrid.BOMB_FUSE / TICK) + 2:
		game.tick(TICK)
	assert_eq(game.bombs.size(), 0, "bomb consumed")
	assert_true(game.flames.has(_cell(1, 1)), "flame at the bomb")
	assert_true(game.flames.has(_cell(1, 2)), "flame reaches one cell out")
	assert_true(game.flames.has(_cell(1, 3)), "flame reaches range 2")
	assert_false(game.flames.has(_cell(1, 4)), "but not beyond the range")


func test_blast_destroys_a_soft_wall_and_stops() -> void:
	var game := _game()
	_clear_row(game, 1)
	game.grid[_cell(1, 3)] = BlastGrid.Cell.SOFT
	_place(game, 0, _cell(1, 1))
	_place(game, 1, _cell(9, 9))
	game.handle_input(0, {"bomb": true})
	for _i in int(BlastGrid.BOMB_FUSE / TICK) + 2:
		game.tick(TICK)
	assert_eq(game.grid[_cell(1, 3)], BlastGrid.Cell.EMPTY, "the soft wall is destroyed")


func test_blast_kos_a_player_in_the_cross() -> void:
	var game := _game()
	_clear_row(game, 1)
	_place(game, 0, _cell(1, 9))  # bomber, then flees
	_place(game, 1, _cell(1, 3))  # caught in the cross of a bomb at (1,1)
	# Drop the bomb at (1,1): move slot 0 there, drop, then send it home.
	_place(game, 0, _cell(1, 1))
	game.handle_input(0, {"bomb": true})
	_place(game, 0, _cell(9, 9))
	for _i in int(BlastGrid.BOMB_FUSE / TICK) + 2:
		game.tick(TICK)
	assert_true(game.finished, "one survivor ends the round")
	var placements: Array = game.get_results().placements
	assert_eq(placements, [[0], [1]], "the bomber wins, the caught player is out")


func test_active_bomb_limit() -> void:
	var game := _game()
	_clear_row(game, 1)
	_place(game, 0, _cell(1, 1))
	game.handle_input(0, {"bomb": true})
	_place(game, 0, _cell(1, 3))
	game.handle_input(0, {"bomb": true})
	assert_eq(game.bombs.size(), 1, "only one active bomb at the start (START_BOMBS)")


func test_range_powerup_extends_the_blast() -> void:
	var game := _game()
	_clear_row(game, 1)
	game.powerups[_cell(1, 1)] = BlastGrid.Power.RANGE
	_place(game, 0, _cell(1, 1))
	_place(game, 1, _cell(9, 9))
	game.tick(TICK)  # collect the power-up under our feet
	assert_eq(int(game.ranges[0]), BlastGrid.START_RANGE + 1, "range up")
	game.handle_input(0, {"bomb": true})
	for _i in int(BlastGrid.BOMB_FUSE / TICK) + 2:
		game.tick(TICK)
	assert_true(game.flames.has(_cell(1, 4)), "the longer blast reaches range 3")


func test_bomb_powerup_raises_the_active_limit() -> void:
	var game := _game()
	_clear_row(game, 1)
	game.powerups[_cell(1, 1)] = BlastGrid.Power.BOMB
	_place(game, 0, _cell(1, 1))
	game.tick(TICK)
	assert_eq(int(game.max_bombs[0]), BlastGrid.START_BOMBS + 1)
	game.handle_input(0, {"bomb": true})
	_place(game, 0, _cell(1, 3))
	game.handle_input(0, {"bomb": true})
	assert_eq(game.bombs.size(), 2, "two bombs now allowed")


func test_chain_detonation() -> void:
	var game := _game()
	_clear_row(game, 1)
	game.max_bombs[0] = 2
	_place(game, 1, _cell(9, 9))
	# Bomb A at (1,1); bomb B at (1,3) sits in A's cross and must chain.
	_place(game, 0, _cell(1, 1))
	game.handle_input(0, {"bomb": true})
	_place(game, 0, _cell(1, 3))
	game.handle_input(0, {"bomb": true})
	_place(game, 0, _cell(9, 1))
	# Give B a longer fuse so only A's blast can trigger it.
	for bomb in game.bombs:
		if int(bomb.cell) == _cell(1, 3):
			bomb.fuse = BlastGrid.BOMB_FUSE * 4.0
	for _i in int(BlastGrid.BOMB_FUSE / TICK) + 2:
		game.tick(TICK)
	assert_eq(game.bombs.size(), 0, "A's blast chained B before its own fuse")
	assert_true(game.flames.has(_cell(1, 5)), "B blasted from its own cell (range 2)")


func test_timeout_survivors_tie_ahead_of_the_fallen() -> void:
	var game := _game(3)
	# Knock slot 2 out, leave 0 and 1 standing, then time out.
	game._pending_downs.append(2)
	game._flush_downs()
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	var placements: Array = game.get_results().placements
	assert_eq(placements[0].size(), 2, "the two survivors tie for first")
	assert_eq(placements[1], [2], "the fallen player trails")
