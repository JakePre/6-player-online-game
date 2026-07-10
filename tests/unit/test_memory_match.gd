extends GutTest
## Memory Match sim (M10-05): show/dark phases, the safe-tile check, pattern
## shrink, and anti-peek replication. Server-side logic only.

const TICK := 1.0 / 30.0


func _game_with(count: int) -> MemoryMatch:
	var game := MemoryMatch.new()
	game.meta = MemoryMatch.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 7)
	return game


func _tile_center(index: int) -> Vector2:
	var col := index % MemoryMatch.GRID_SIZE
	var row := int(floorf(float(index) / MemoryMatch.GRID_SIZE))
	return Vector2(
		-MemoryMatch.HALF_EXTENT + (col + 0.5) * MemoryMatch.TILE_SIZE,
		-MemoryMatch.HALF_EXTENT + (row + 0.5) * MemoryMatch.TILE_SIZE
	)


func _unsafe_tile(game: MemoryMatch) -> int:
	for i in MemoryMatch.GRID_SIZE * MemoryMatch.GRID_SIZE:
		if i not in game.safe_tiles:
			return i
	return -1


## Runs the current phase out so the next one begins.
func _end_phase(game: MemoryMatch) -> void:
	game._phase_left = 0.0
	game.tick(TICK)


func test_setup_deals_a_pattern_and_shows_it() -> void:
	var game := _game_with(3)
	assert_eq(game.phase, MemoryMatch.Phase.SHOW)
	var expected := int(
		roundf(MemoryMatch.GRID_SIZE * MemoryMatch.GRID_SIZE * MemoryMatch.SAFE_START_FRACTION)
	)
	assert_eq(game.safe_tiles.size(), expected)


func test_safe_tiles_hidden_from_snapshots_in_the_dark() -> void:
	var game := _game_with(2)
	assert_false(game.get_snapshot().safe_tiles.is_empty(), "pattern visible while showing")
	_end_phase(game)
	assert_eq(game.phase, MemoryMatch.Phase.DARK)
	assert_eq(game.get_snapshot().safe_tiles, [], "dark clients cannot peek")


func test_check_downs_players_off_the_pattern() -> void:
	var game := _game_with(3)
	game.positions[0] = _tile_center(game.safe_tiles[0])
	game.positions[1] = _tile_center(game.safe_tiles[1 % game.safe_tiles.size()])
	game.positions[2] = _tile_center(_unsafe_tile(game))
	_end_phase(game)
	_end_phase(game)
	assert_eq(game.down_order, [[2]], "only the player off the pattern drops")
	assert_eq(game.phase, MemoryMatch.Phase.SHOW, "a fresh pattern shows next")
	assert_eq(game.round_number, 1)


func test_pattern_shrinks_each_round() -> void:
	var game := _game_with(2)
	var first := game.safe_tiles.size()
	game.round_number = 3
	game._deal_pattern()
	assert_lt(game.safe_tiles.size(), first)
	game.round_number = 99
	game._deal_pattern()
	assert_eq(game.safe_tiles.size(), MemoryMatch.SAFE_MIN, "never below the floor")


func test_survival_runs_to_a_winner() -> void:
	var game := _game_with(3)
	game.positions[0] = _tile_center(game.safe_tiles[0])
	game.positions[1] = _tile_center(_unsafe_tile(game))
	game.positions[2] = _tile_center(_unsafe_tile(game))
	_end_phase(game)
	_end_phase(game)
	assert_true(game.finished, "one survivor ends it")
	assert_eq(game.get_results().placements, [[0], [1, 2]], "simultaneous drops tie")


func test_timeout_ranks_survivors_ahead_of_the_fallen() -> void:
	var game := _game_with(2)
	game.duration_override = TICK
	game.tick(TICK)
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0, 1]])


func test_max_players_raised_to_twenty_four() -> void:
	assert_eq(MemoryMatch.make_meta().max_players, 24)


func test_control_spec_present() -> void:
	assert_false(
		MemoryMatch.make_meta().control_spec.is_empty(), "ships a #832 structured control spec"
	)


## A 24-player match tracks 24 independent positions. Soft body separation
## (#784) now keeps players from stacking, so survivors are spread ≤2 to a safe
## tile — a full pass through the check leaves everyone on a safe tile standing.
func test_setup_handles_twenty_four_players() -> void:
	var game := _game_with(24)
	assert_eq(game.positions.size(), 24)
	assert_eq(game._in_slots().size(), 24)
	# Two per safe tile, 1.0u apart inside the 2.0u tile (> the 0.9u separation
	# gap, so nobody gets shoved off) — all genuinely on safe ground.
	for slot in 24:
		var center := _tile_center(game.safe_tiles[(slot / 2) % game.safe_tiles.size()])
		game.positions[slot] = center + (Vector2(0.5, 0.0) if slot % 2 == 0 else Vector2(-0.5, 0.0))
	_end_phase(game)
	_end_phase(game)
	assert_eq(game._in_slots().size(), 24, "everyone standing on a safe tile survives")


## Shove (#784): action_primary knocks a nearby rival away, starts the cooldown,
## and ticks the swing counter — and a second press while cooling is a no-op.
func test_shove_knocks_a_nearby_rival_and_then_cools_down() -> void:
	var game := _game_with(2)
	game.positions[0] = Vector2(0.0, 0.0)
	game.positions[1] = Vector2(0.6, 0.0)  # within SHOVE_RADIUS (1.2)
	var seq_before: int = game.act_seq[0]
	game.handle_input(0, {"shove": true})
	assert_gt(game.knocks[1].x, 0.0, "rival knocked away (+x)")
	assert_almost_eq(
		float(game.shove_cd[0]), MemoryMatch.SHOVE_COOLDOWN_SEC, 0.001, "cooldown armed"
	)
	assert_eq(game.act_seq[0], seq_before + 1, "the swing counter ticks once")
	game.knocks[1] = Vector2.ZERO
	game.handle_input(0, {"shove": true})  # still cooling
	assert_eq(game.knocks[1], Vector2.ZERO, "a shove on cooldown does nothing")


## Out-of-range rivals are untouched by a shove.
func test_shove_spares_distant_rivals() -> void:
	var game := _game_with(2)
	game.positions[0] = Vector2(0.0, 0.0)
	game.positions[1] = Vector2(3.0, 0.0)  # beyond SHOVE_RADIUS
	game.handle_input(0, {"shove": true})
	assert_eq(game.knocks[1], Vector2.ZERO, "too far to shove")


## Soft separation (#784): two players driven onto the same spot are pushed
## apart to at least the min gap, so nobody can hide-stack on one safe tile.
func test_soft_separation_prevents_stacking() -> void:
	var game := _game_with(2)
	game.positions[0] = Vector2(0.0, 0.0)
	game.positions[1] = Vector2(0.0, 0.0)
	game.tick(TICK)
	assert_gte(
		game.positions[0].distance_to(game.positions[1]),
		MemoryMatch.PLAYER_RADIUS * 2.0 - 0.001,
		"overlapping players are separated"
	)


## Wire shape stays append-only (#708/#784): x/y keep their indices, with
## act_seq and shove-cooldown appended.
func test_snapshot_appends_act_seq_and_cooldown() -> void:
	var game := _game_with(2)
	var row: Array = game.get_snapshot().players[0]
	assert_eq(row.size(), 4, "[x, y, act_seq, shove_cd]")
	assert_almost_eq(float(row[MemoryMatch.PS_SHOVE_CD]), 0.0, 0.001, "starts ready")


func test_tile_of_maps_positions_to_indices() -> void:
	var game := _game_with(2)
	assert_eq(
		game.tile_of(Vector2(-MemoryMatch.HALF_EXTENT + 0.1, -MemoryMatch.HALF_EXTENT + 0.1)), 0
	)
	var last := MemoryMatch.GRID_SIZE * MemoryMatch.GRID_SIZE - 1
	assert_eq(
		game.tile_of(Vector2(MemoryMatch.HALF_EXTENT - 0.1, MemoryMatch.HALF_EXTENT - 0.1)), last
	)
