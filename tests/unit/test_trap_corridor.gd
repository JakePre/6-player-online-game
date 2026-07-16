extends GutTest
## Trap Corridor (SPEC $7 #16): rotating trapper role, trap budget, hidden
## traps, catch/finish scoring, and cumulative ranking.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2]) -> TrapCorridor:
	var game := TrapCorridor.new()
	game.meta = TrapCorridor.make_meta()
	game.setup(player_slots, 42)
	return game


func _skip_trap_phase(game: TrapCorridor) -> void:
	game.phase_left = 0.001
	game.tick(TICK)


## Runs `slot` to the finish line along its lane, teleport-style per tick.
func _finish_runner(game: TrapCorridor, slot: int) -> void:
	game.positions[slot] = Vector2(TrapCorridor.CORRIDOR_LEN - 0.05, 0.0)
	game.handle_input(slot, {"mx": 1.0, "my": 0.0})
	game.tick(TICK)


func test_meta() -> void:
	var meta := TrapCorridor.make_meta()
	assert_eq(meta.id, &"trap_corridor")
	assert_eq(meta.category, MinigameMeta.Category.SABOTAGE)
	assert_eq(meta.min_players, 3)
	assert_eq(meta.max_players, 8, "M15: 8 by design, not scaled further")
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")


func test_registered_in_catalog() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"trap_corridor") is TrapCorridor)
	MinigameCatalog.clear()


## M15: the start line spreads runners by headcount, not the fixed 5-lane
## TILE_WIDTH — that formula alone spills outside the corridor past 5 players
## (a pre-existing gap this exposed, worse at the new 8-player cap).
func test_start_line_stays_within_the_corridor_at_eight() -> void:
	var player_slots: Array[int] = []
	for slot in 8:
		player_slots.append(slot)
	var game := _game(player_slots)
	for slot: int in player_slots:
		var pos: Vector2 = game.positions[slot]
		assert_between(
			pos.y,
			-TrapCorridor.CORRIDOR_HALF_WIDTH,
			TrapCorridor.CORRIDOR_HALF_WIDTH,
			"every start position stays inside the corridor width"
		)


func test_start_line_positions_are_distinct_at_eight() -> void:
	var player_slots: Array[int] = []
	for slot in 8:
		player_slots.append(slot)
	var game := _game(player_slots)
	var seen := {}
	for slot: int in player_slots:
		seen[game.positions[slot]] = true
	assert_eq(seen.size(), 8, "every player gets a distinct start position")


func test_starts_in_trap_phase_with_first_slot_trapping() -> void:
	var game := _game()
	assert_eq(game.phase, TrapCorridor.Phase.TRAPPING)
	assert_eq(game.trapper(), 0)


## #1042/#1030: the real net path runs every payload through SafeInput.sanitize,
## which the other trap tests skip by calling handle_input directly. The #970
## sanitizer dropped the `trap` array whole, so live placement silently no-oped
## even though these direct-call tests stayed green. Guard the end-to-end path.
func test_trap_placement_survives_the_net_sanitizer() -> void:
	var game := _game()
	game.handle_input(0, SafeInput.sanitize({"trap": [3, 1]}))
	assert_eq(game.hidden_traps.size(), 1, "a sanitized trap payload still places a trap")


func test_only_the_trapper_may_place_traps_and_only_in_phase() -> void:
	var game := _game()
	game.handle_input(1, {"trap": [3, 1]})
	assert_eq(game.hidden_traps.size(), 0, "runners cannot trap")
	game.handle_input(0, {"trap": [3, 1]})
	assert_eq(game.hidden_traps.size(), 1)
	_skip_trap_phase(game)
	game.handle_input(0, {"trap": [4, 1]})
	assert_eq(game.hidden_traps.size(), 1, "no trapping once the run starts")


func test_trap_budget_and_duplicates() -> void:
	var game := _game()
	for col in range(1, TrapCorridor.COLS - 1):
		game.handle_input(0, {"trap": [col, 0]})
	assert_eq(game.hidden_traps.size(), TrapCorridor.TRAP_BUDGET)
	var game2 := _game()
	game2.handle_input(0, {"trap": [3, 1]})
	game2.handle_input(0, {"trap": [3, 1]})
	assert_eq(game2.hidden_traps.size(), 1, "duplicate tile counts once")


func test_start_and_finish_columns_are_safe() -> void:
	var game := _game()
	game.handle_input(0, {"trap": [0, 2]})
	game.handle_input(0, {"trap": [TrapCorridor.COLS - 1, 2]})
	for index: int in game.hidden_traps:
		var col: int = index / TrapCorridor.ROWS
		assert_between(col, 1, TrapCorridor.COLS - 2)


func test_hidden_traps_never_in_snapshot_until_triggered() -> void:
	var game := _game()
	game.handle_input(0, {"trap": [3, 2]})
	var snapshot := game.get_snapshot()
	assert_false(snapshot.has("hidden"), "no hidden-trap key at all")
	assert_eq(snapshot.revealed, [])
	assert_eq(snapshot.traps_left, TrapCorridor.TRAP_BUDGET - 1)
	_skip_trap_phase(game)
	# Runner 1 walks onto the trapped tile.
	game.positions[1] = Vector2(3.5 * TrapCorridor.TILE_LEN, 0.01)
	game.handle_input(1, {"mx": 0.0, "my": 0.0})
	game.positions[1] = Vector2(
		3.0 * TrapCorridor.TILE_LEN + 0.1,
		-TrapCorridor.CORRIDOR_HALF_WIDTH + 2.5 * TrapCorridor.TILE_WIDTH
	)
	game.tick(TICK)
	assert_eq(game.get_snapshot().revealed.size(), 1, "triggered trap is revealed")
	assert_true(1 in game.caught)
	assert_eq(game.scores[0], TrapCorridor.CATCH_POINTS)


func test_finish_order_scores() -> void:
	var game := _game([0, 1, 2, 3] as Array[int])
	_skip_trap_phase(game)
	_finish_runner(game, 1)
	_finish_runner(game, 2)
	assert_eq(game.scores[1], TrapCorridor.FINISH_POINTS[0])
	assert_eq(game.scores[2], TrapCorridor.FINISH_POINTS[1])


func test_roles_rotate_and_game_ends_after_everyone_trapped() -> void:
	var game := _game()
	for sub_round in 3:
		assert_eq(game.trapper(), sub_round)
		_skip_trap_phase(game)
		game.phase_left = 0.001
		game.tick(TICK)
	assert_true(game.finished)


func test_caught_runners_sit_out_the_sub_round() -> void:
	var game := _game()
	game.handle_input(0, {"trap": [3, 2]})
	_skip_trap_phase(game)
	game.positions[1] = Vector2(
		3.0 * TrapCorridor.TILE_LEN + 0.1,
		-TrapCorridor.CORRIDOR_HALF_WIDTH + 2.5 * TrapCorridor.TILE_WIDTH
	)
	game.tick(TICK)
	assert_true(1 in game.caught)
	var before: Vector2 = game.positions[1]
	game.handle_input(1, {"mx": 1.0, "my": 0.0})
	game.tick(TICK)
	assert_eq(game.positions[1], before, "caught runners cannot move")
	assert_false(game.get_snapshot().players.has(1), "caught runners leave the corridor")


func test_cumulative_scores_rank_players() -> void:
	var game := _game()
	game.scores = {0: 4, 1: 6, 2: 4}
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0, 2]])
	assert_eq(game.get_results().pickup_coins, {})


func test_sub_round_ends_early_when_all_runners_settled() -> void:
	var game := _game()
	_skip_trap_phase(game)
	_finish_runner(game, 1)
	_finish_runner(game, 2)
	game.tick(TICK)
	assert_eq(game.trapper(), 1, "next trapper takes over immediately")
	assert_eq(game.phase, TrapCorridor.Phase.TRAPPING)
