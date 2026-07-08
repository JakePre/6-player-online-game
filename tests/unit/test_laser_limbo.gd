extends GutTest
## Laser Limbo sim (M10-06): stance checks per wall kind, lives, invulnerable
## windows, and lives-then-fallen ranking. Server-side logic only.

const TICK := 1.0 / 30.0


func _game_with(count: int) -> LaserLimbo:
	var game := LaserLimbo.new()
	game.meta = LaserLimbo.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 7)
	game._spawn_left = 999.0  # hand-built walls only; no seeded spawns
	return game


func _wall(kind: int, x: float, gap_y: float = 0.0) -> Dictionary:
	return {"x": x, "dir": 1, "kind": kind, "gap_y": gap_y, "speed": 6.0}


## Parks everyone away from the sweep line so only slot 0 is in play.
func _isolate(game: LaserLimbo) -> void:
	for slot: int in game.slots:
		game.positions[slot] = Vector2(0.0, 7.5)
	game.positions[0] = Vector2(0.0, 0.0)


func test_low_wall_hits_grounded_players_only() -> void:
	var game := _game_with(2)
	_isolate(game)
	game.walls = [_wall(LaserLimbo.WallKind.LOW, -0.1)]
	game.tick(TICK)
	assert_eq(game.lives[0], LaserLimbo.LIVES - 1, "grounded = hit")
	game.walls = [_wall(LaserLimbo.WallKind.LOW, -0.1)]
	game.invuln[0] = 0.0
	game.airborne[0] = LaserLimbo.JUMP_SEC
	game.tick(TICK)
	assert_eq(game.lives[0], LaserLimbo.LIVES - 1, "airborne clears it")


func test_high_wall_requires_ducking() -> void:
	var game := _game_with(2)
	_isolate(game)
	game.ducking[0] = true
	game.walls = [_wall(LaserLimbo.WallKind.HIGH, -0.1)]
	game.tick(TICK)
	assert_eq(game.lives[0], LaserLimbo.LIVES, "ducked under it")
	game.ducking[0] = false
	game.walls = [_wall(LaserLimbo.WallKind.HIGH, -0.1)]
	game.tick(TICK)
	assert_eq(game.lives[0], LaserLimbo.LIVES - 1, "standing tall = hit")


func test_gap_wall_spares_players_in_the_opening() -> void:
	var game := _game_with(2)
	_isolate(game)
	game.positions[0] = Vector2(0.0, 3.0)
	game.walls = [_wall(LaserLimbo.WallKind.GAP, -0.1, 3.0)]
	game.tick(TICK)
	assert_eq(game.lives[0], LaserLimbo.LIVES, "inside the gap")
	game.positions[0] = Vector2(0.0, -3.0)
	game.walls = [_wall(LaserLimbo.WallKind.GAP, -0.1, 3.0)]
	game.tick(TICK)
	assert_eq(game.lives[0], LaserLimbo.LIVES - 1, "outside the gap = hit")


func test_invuln_blocks_double_hits() -> void:
	var game := _game_with(2)
	_isolate(game)
	game.walls = [_wall(LaserLimbo.WallKind.LOW, -0.1), _wall(LaserLimbo.WallKind.HIGH, -0.05)]
	game.tick(TICK)
	assert_eq(game.lives[0], LaserLimbo.LIVES - 1, "two walls, one tick, one hit")


func test_out_of_lives_goes_down_and_game_ends() -> void:
	var game := _game_with(2)
	_isolate(game)
	game.lives[0] = 1
	game.walls = [_wall(LaserLimbo.WallKind.LOW, -0.1)]
	game.tick(TICK)
	assert_true(game.finished, "one player left ends it")
	assert_eq(game.get_results().placements, [[1], [0]])


func test_jump_needs_cooldown_and_blocks_while_ducking() -> void:
	var game := _game_with(2)
	game.ducking[0] = true
	game.handle_input(0, {"jump": true})
	assert_eq(game.airborne[0], 0.0, "cannot jump out of a duck")
	game.ducking[0] = false
	game.handle_input(0, {"jump": true})
	assert_gt(game.airborne[0], 0.0)
	var first_air: float = game.airborne[0]
	game.handle_input(0, {"jump": true})
	assert_eq(game.airborne[0], first_air, "cooldown swallows the second press")


func test_walls_spawn_and_despawn() -> void:
	var game := _game_with(2)
	game._spawn_left = 0.0
	game.tick(TICK)
	assert_eq(game.walls.size(), 1, "cadence spawns a wall")
	game.walls = [_wall(LaserLimbo.WallKind.LOW, LaserLimbo.ARENA_HALF + 2.0)]
	game._spawn_left = 999.0
	game.tick(TICK)
	assert_eq(game.walls.size(), 0, "walls past the arena despawn")


func test_timeout_ranks_by_lives_then_fallen() -> void:
	var game := _game_with(3)
	_isolate(game)
	game.lives = {0: 3, 1: 1, 2: 1}
	game.down_order = []
	game.duration_override = TICK
	game.tick(TICK)
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0], [1, 2]], "lives break the timeout tie")


func test_snapshot_shape() -> void:
	var game := _game_with(2)
	game.walls = [_wall(LaserLimbo.WallKind.GAP, 1.0, -2.0)]
	var snapshot := game.get_snapshot()
	assert_eq(
		(snapshot.players[0] as Array).size(),
		LaserLimbo.PS_COUNT,
		"[x, y, lives, airborne, ducking]"
	)
	assert_eq(snapshot.walls, [[1.0, 1, LaserLimbo.WallKind.GAP, -2.0]])
	assert_eq(snapshot.fallen, [])


func test_max_players_raised_to_twenty_four() -> void:
	assert_eq(LaserLimbo.make_meta().max_players, 24)


## M15: at 24 players the arena, gap, and wall speed all grow.
func test_arena_gap_and_speed_scale_at_twenty_four() -> void:
	var game := _game_with(24)
	assert_gt(game._play_half, LaserLimbo.ARENA_HALF, "bigger arena")
	assert_gt(game._gap_half, LaserLimbo.GAP_HALF_WIDTH, "wider gap")
	assert_gt(game._speed_scale, 1.0, "faster walls to keep the cadence")


## The fairness invariant: the gap is the same fraction of the arena at any
## count, so slipping through a GAP wall is no harder at 24 than at 6.
func test_gap_stays_the_same_fraction_of_the_arena() -> void:
	var base_ratio := LaserLimbo.GAP_HALF_WIDTH / LaserLimbo.ARENA_HALF
	for count in [6, 12, 24]:
		var game := _game_with(count)
		assert_almost_eq(game._gap_half / game._play_half, base_ratio, 0.0001)


## Backward compatibility: at the 6-player baseline nothing scales.
func test_six_players_unchanged() -> void:
	var game := _game_with(6)
	assert_almost_eq(game._play_half, LaserLimbo.ARENA_HALF, 0.001)
	assert_almost_eq(game._gap_half, LaserLimbo.GAP_HALF_WIDTH, 0.001)
	assert_almost_eq(game._speed_scale, 1.0, 0.001)


## A wall spawned at 24 players carries the scaled speed.
func test_spawned_walls_carry_scaled_speed_at_twenty_four() -> void:
	var game := _game_with(24)
	game._spawn_left = 0.0
	game._spawn_walls(0.0)
	assert_eq(game.walls.size(), 1)
	assert_almost_eq(
		float((game.walls[0] as Dictionary).speed),
		LaserLimbo.WALL_SPEED_START * game._speed_scale,
		0.001
	)


## Spawns fan out over rings (no overlap) and stay inside the scaled arena.
func test_spawns_distinct_and_within_arena_at_twenty_four() -> void:
	var game := _game_with(24)
	var seen := {}
	for slot in 24:
		var pos: Vector2 = game.positions[slot]
		assert_lte(pos.length(), game._play_half, "spawn inside the scaled arena")
		seen[pos] = true
	assert_eq(seen.size(), 24, "every player gets a distinct spawn")
