extends GutTest
## Snake Chain (PHASE2.md $4 #28): growth, collisions, crash spills,
## team/FFA mode, and ranking.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> SnakeChain:
	var game := SnakeChain.new()
	game.meta = SnakeChain.make_meta()
	game.setup(player_slots, 42)
	return game


func test_meta_and_catalog() -> void:
	var meta := SnakeChain.make_meta()
	assert_eq(meta.id, &"snake_chain")
	assert_eq(meta.category, MinigameMeta.Category.TEAM)
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"snake_chain") is SnakeChain)
	MinigameCatalog.clear()


func test_mode_by_player_count() -> void:
	assert_false(_game([0, 1] as Array[int]).team_mode, "2 players FFA")
	assert_false(_game([0, 1, 2, 3, 4] as Array[int]).team_mode, "odd FFA (#178)")
	var team_game := _game([0, 1, 2, 3] as Array[int])
	assert_true(team_game.team_mode)
	assert_eq(team_game.teams[0].size(), 2)


func test_eating_grows_the_chain() -> void:
	var game := _game()
	game.pellets.clear()
	game.pellets.append(game.positions[0])
	game.tick(TICK)
	assert_eq(game.pellets_eaten[0], 1)
	assert_eq(game._max_segments(0), SnakeChain.BASE_SEGMENTS + 1)


func test_head_into_another_body_crashes_and_spills() -> void:
	var game := _game()
	game.pellets_eaten[0] = 6
	game.pellets.clear()
	game.trails[1] = [game.positions[0] + Vector2(0.1, 0.0)]
	game.tick(TICK)
	assert_eq(game.pellets_eaten[0], 3, "half the pellets spilled")
	assert_gt(game.pellets.size(), 0, "spill lands on the floor")
	assert_gt(float(game.invuln_left[0]), 0.0)
	assert_eq((game.trails[0] as Array).size(), 0, "chain resets")


func test_own_fresh_segments_are_safe_but_old_ones_kill() -> void:
	var game := _game()
	var head: Vector2 = game.positions[0]
	# Fresh segments (inside the grace window) don't kill.
	game.trails[0] = [head, head, head, head]
	game.tick(TICK)
	assert_eq(float(game.invuln_left[0]), 0.0, "grace segments are safe")
	# An old segment at the head does.
	var trail: Array = []
	for i in SnakeChain.SELF_GRACE_SEGMENTS + 1:
		trail.append(head + Vector2(5.0, 5.0))
	trail.append(game.positions[0])
	game.trails[0] = trail
	game.tick(TICK)
	assert_gt(float(game.invuln_left[0]), 0.0, "old own segment crashes")


func test_invulnerable_heads_pass_through() -> void:
	var game := _game()
	game.invuln_left[0] = 1.0
	game.trails[1] = [game.positions[0]]
	game.pellets_eaten[0] = 4
	game.tick(TICK)
	assert_eq(game.pellets_eaten[0], 4, "no crash while shimmering")


func test_ffa_ranking_and_pickup_coins() -> void:
	var game := _game([0, 1, 2] as Array[int])
	game.pellets_eaten = {0: 4, 1: 9, 2: 4}
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0, 2]])
	assert_eq(game.get_results().pickup_coins, {0: 4, 1: 9, 2: 4})


func test_team_totals_decide() -> void:
	var game := _game([0, 1, 2, 3] as Array[int])
	for slot: int in game.teams[0]:
		game.pellets_eaten[slot] = 5
	for slot: int in game.teams[1]:
		game.pellets_eaten[slot] = 2
	game.duration_override = game.elapsed + TICK
	game.tick(TICK)
	var results := game.get_results()
	assert_true(results.team_mode)
	assert_eq(results.placements, [game.teams[0], game.teams[1]])


func test_snapshot_shape() -> void:
	var game := _game()
	game.trails[0] = [Vector2(1.0, 1.0)]
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players[0].size(), 4)
	assert_eq(snapshot.trails[0], [[1.0, 1.0]])
	assert_gt(snapshot.pellets.size(), 0)
	assert_eq(snapshot.teams, [])
