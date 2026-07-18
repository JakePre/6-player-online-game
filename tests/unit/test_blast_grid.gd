extends GutTest
## Blast Grid server simulation (M14-06): grid construction, wall collision,
## bomb fuse + cross blast, soft-wall destruction, power-ups, chain
## detonation, KO / last-standing ranking.

const TICK := 1.0 / 30.0
const G := BlastGrid.GRID
## #961 anti-collapse floor: a fresh bot field must outlast the opening bomb
## fuse (BOMB_FUSE 2.5s + flame), not wipe in ~3s. See the guard test below.
const OPENING_SURVIVAL_SEC := 6.0


func _game(count: int = 2) -> BlastGrid:
	var game := BlastGrid.new()
	game.meta = BlastGrid.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 42)
	return game


func _run_bot_round(count: int, seed_value: int) -> float:
	var game := BlastGrid.new()
	game.meta = BlastGrid.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, seed_value)
	var brains := {}
	for slot: int in game.slots:
		brains[slot] = BotBrains.brain_for(&"blast_grid", slot, seed_value)
	var t := 0.0
	while not game.finished and t < game.meta.duration_sec:
		var match_state := {"game": game.get_snapshot()}
		for slot: int in game.slots:
			if game._is_in(slot):
				game.handle_input(slot, brains[slot].think(match_state, {}))
		game.tick(TICK)
		t += TICK
	return t


## #961: blast_grid's telemetry collapse (median 3s vs 75s) was the brains
## mass-suiciding on the opening bomb wave — they froze on their own live bomb
## (a bomb's cross covers all four neighbours, so a single-hop escape check found
## nowhere safe) and detonated at the ~2.5s fuse. The escape-step BFS in
## blast_grid_brain fixed it: the bot now steps ALONG the blast line and turns
## the corner out. This locks that in — a fresh bot field must survive well past
## the opening fuse instead of wiping in ~3s.
##
## (The residual — near-perfect survival tips most rounds to a timeout all-tie,
## since MOVE_SPEED easily outruns the fuse on open ground — is bot passivity, a
## separate degeneracy tracked under #926, not this length collapse.)
func test_bot_rounds_survive_the_opening_bomb_wave() -> void:
	for count: int in [2, 4, 6]:
		for seed_value: int in [1, 2, 42]:
			var duration := _run_bot_round(count, seed_value)
			assert_gt(
				duration,
				OPENING_SURVIVAL_SEC,
				"%d bots (seed %d) do not mass-suicide on the opening fuse" % [count, seed_value]
			)


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


# --- #949 homage: bomb kick, cursed skull, border revenge ---------------------


## Walking into your own resting bomb kicks it; it slides down the cleared
## corridor and stops at the far wall (fuse held long so it can't detonate).
func test_kick_slides_own_bomb_until_a_wall() -> void:
	var game := _game()
	_clear_row(game, 1)
	_place(game, 1, _cell(9, 9))  # keep the rival out of the corridor
	_place(game, 0, _cell(1, 2))
	game._spawn_bomb(_cell(1, 3), 99.0, 2, 0)
	# Push right just enough to step onto the bomb and kick it, then release so
	# the (faster) player doesn't chase and block the slide.
	for _i in 8:
		game.handle_input(0, {"mx": 1.0, "my": 0.0})
		game.tick(TICK)
	assert_ne(game.bombs[0].slide as Vector2i, Vector2i.ZERO, "the kick set the bomb sliding")
	for _i in 90:
		game.handle_input(0, {"mx": 0.0, "my": 0.0})
		game.tick(TICK)
	assert_eq(int(game.bombs[0].cell), _cell(1, 9), "slid to the cell before the border wall")
	assert_eq(game.bombs[0].slide as Vector2i, Vector2i.ZERO, "and came to rest")


## You can only kick a bomb you own — a rival's bomb ignores your push.
func test_kick_only_moves_your_own_bomb() -> void:
	var game := _game()
	_clear_row(game, 1)
	_place(game, 1, _cell(9, 9))
	_place(game, 0, _cell(1, 2))
	game._spawn_bomb(_cell(1, 3), 99.0, 2, 1)  # owned by slot 1
	for _i in 20:
		game.handle_input(0, {"mx": 1.0, "my": 0.0})
		game.tick(TICK)
	assert_eq(int(game.bombs[0].cell), _cell(1, 3), "someone else's bomb doesn't kick")
	assert_eq(game.bombs[0].slide as Vector2i, Vector2i.ZERO)


## A kicked bomb stops the moment the next cell is blocked by a crate.
func test_kick_stops_at_a_crate() -> void:
	var game := _game()
	_clear_row(game, 1)
	_place(game, 1, _cell(9, 9))
	game.grid[_cell(1, 5)] = BlastGrid.Cell.SOFT  # a crate two cells past the bomb
	_place(game, 0, _cell(1, 2))
	game._spawn_bomb(_cell(1, 3), 99.0, 2, 0)
	for _i in 8:
		game.handle_input(0, {"mx": 1.0, "my": 0.0})
		game.tick(TICK)
	for _i in 60:
		game.handle_input(0, {"mx": 0.0, "my": 0.0})
		game.tick(TICK)
	assert_eq(int(game.bombs[0].cell), _cell(1, 4), "stopped in the cell before the crate")


## The cursed skull is a 50/50 gamble: MEGA (+3 range) or CURSED (reversed
## movement) — deterministic from the sim rng, exactly one outcome per grab.
func test_cursed_skull_is_5050_mega_or_curse() -> void:
	var game := _game()
	var megas := 0
	var curse_count := 0
	for _i in 40:
		game.ranges[0] = BlastGrid.START_RANGE
		game.curses[0] = 0.0
		game._grab_skull(0)
		if int(game.ranges[0]) > BlastGrid.START_RANGE:
			megas += 1
		elif float(game.curses[0]) > 0.0:
			curse_count += 1
	assert_eq(megas + curse_count, 40, "every grab is exactly one of the two outcomes")
	assert_gt(megas, 0, "mega grabs happen")
	assert_gt(curse_count, 0, "cursed grabs happen")


## While cursed, movement input is reversed — pushing right carries you left.
func test_curse_reverses_movement() -> void:
	var game := _game()
	_clear_row(game, 1)
	_place(game, 0, _cell(1, 5))
	game.curses[0] = BlastGrid.CURSE_SEC
	var start_x: float = game.positions[0].x
	for _i in 10:
		game.handle_input(0, {"mx": 1.0, "my": 0.0})
		game.tick(TICK)
	assert_lt(game.positions[0].x, start_x - 0.2, "cursed: pushing right moves you left")


func test_curse_expires_after_its_timer() -> void:
	var game := _game()
	game.curses[0] = 2.0 * TICK
	game.tick(TICK)
	game.tick(TICK)
	game.tick(TICK)
	assert_eq(float(game.curses[0]), 0.0, "curse timer bleeds to zero")


## Over many soft-wall breaks a cursed skull eventually drops (its own slice of
## the power-up roll).
func test_soft_walls_can_drop_a_cursed_skull() -> void:
	var game := _game()
	var saw_skull := false
	for _i in 400:
		game.powerups.clear()
		game.grid[_cell(1, 5)] = BlastGrid.Cell.SOFT
		game._destroy_soft(_cell(1, 5))
		if game.powerups.values().has(BlastGrid.Power.SKULL):
			saw_skull = true
			break
	assert_true(saw_skull, "skulls are among the drops")


## An eliminated player lobs a revenge bomb (owner sentinel) after the cooldown.
func test_border_revenge_lobs_on_cooldown() -> void:
	var game := _game(3)
	game._pending_downs.append(2)
	game._flush_downs()
	assert_true(game.bombs.is_empty(), "no revenge bomb before the cooldown")
	for _i in int(BlastGrid.REVENGE_COOLDOWN / TICK) + 2:
		game.tick(TICK)
	var revenge := game.bombs.filter(
		func(b: Dictionary) -> bool: return int(b.owner) == BlastGrid.REVENGE_OWNER
	)
	assert_gt(revenge.size(), 0, "a revenge bomb was lobbed ~8s after elimination")


## The snapshot exposes the new #949 state: border riders and the cursed flag.
func test_snapshot_exposes_riders_and_cursed_flag() -> void:
	var game := _game()
	game._pending_downs.append(1)
	game._flush_downs()
	var snap := game.get_snapshot()
	assert_eq(snap.revenge.size(), 1, "one eliminated rider on the border")
	assert_eq(int(snap.revenge[0][BlastGrid.RV_SLOT]), 1)
	game.curses[0] = BlastGrid.CURSE_SEC
	assert_eq(
		int(game.get_snapshot().players[0][BlastGrid.PS_CURSED]), 1, "cursed flag on the wire"
	)
