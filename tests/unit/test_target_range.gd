extends GutTest
## Target Range server simulation (M4-08, SPEC $7 #9): target spawning and
## drift, aim clamping, fire cooldown, hit scoring, and score ranking.


func _make_game(player_count: int) -> TargetRange:
	var game := TargetRange.new()
	game.meta = TargetRange.make_meta()
	var slots: Array[int] = []
	for i in player_count:
		slots.append(i)
	game.setup(slots, 42)
	return game


## Aims slot 0 dead-center on the first live target and returns its value.
func _aim_at_first_target(game: TargetRange) -> int:
	var target: Dictionary = game.targets[0]
	var pos: Vector2 = target.pos
	game.handle_input(0, {"ax": pos.x, "ay": pos.y})
	return int(target.value)


func test_setup_spawns_targets_and_zero_scores() -> void:
	var game := _make_game(4)
	assert_eq(game.targets.size(), game._alive_target_count())
	for slot in 4:
		assert_eq(game.scores[slot], 0)
		assert_eq(game.aims[slot], Vector2.ZERO)


func test_target_count_scales_with_players() -> void:
	assert_eq(_make_game(2).targets.size(), 4)
	assert_eq(_make_game(4).targets.size(), 5)
	assert_eq(_make_game(6).targets.size(), 6)


func test_aim_is_clamped_to_the_arena() -> void:
	var game := _make_game(2)
	game.handle_input(0, {"ax": 999.0, "ay": -999.0})
	assert_eq(game.aims[0], Vector2(TargetRange.ARENA_HALF, -TargetRange.ARENA_HALF))


func test_hit_awards_the_target_value_and_replaces_it() -> void:
	var game := _make_game(2)
	var old_id: int = game.targets[0].id
	var value := _aim_at_first_target(game)
	game.handle_input(0, {"fire": true})
	assert_eq(game.scores[0], value)
	assert_ne(int(game.targets[0].id), old_id)
	assert_eq(game.targets.size(), game._alive_target_count())


func test_miss_scores_nothing_but_starts_the_cooldown() -> void:
	var game := _make_game(2)
	# Dead center is inside the empty near half — every target spawns in the
	# far band at |x| beyond the arena edge.
	game.handle_input(0, {"ax": 0.0, "ay": TargetRange.ARENA_HALF})
	game.handle_input(0, {"fire": true})
	assert_eq(game.scores[0], 0)
	assert_gt(float(game.cooldowns[0]), 0.0)


func test_cooldown_blocks_rapid_fire_and_recovers() -> void:
	var game := _make_game(2)
	var value := _aim_at_first_target(game)
	game.handle_input(0, {"fire": true})
	_aim_at_first_target(game)
	game.handle_input(0, {"fire": true})
	assert_eq(game.scores[0], value)

	game.tick(TargetRange.FIRE_COOLDOWN_SEC + 0.05)
	var second := _aim_at_first_target(game)
	game.handle_input(0, {"fire": true})
	assert_eq(game.scores[0], value + second)


func test_targets_drift_horizontally_on_tick() -> void:
	var game := _make_game(2)
	var before: Vector2 = game.targets[0].pos
	game.tick(0.5)
	var after: Vector2 = game.targets[0].pos
	assert_ne(after.x, before.x)
	assert_eq(after.y, before.y)


func test_ranking_orders_by_score_with_ties_grouped() -> void:
	var game := _make_game(3)
	game.scores[0] = 5
	game.scores[1] = 9
	game.scores[2] = 5
	var placements := game._rank_players()
	assert_eq(placements[0], [1])
	assert_eq(placements[1], [0, 2])


func test_finishes_at_duration_with_score_ranking() -> void:
	var game := _make_game(2)
	game.duration_override = 1.0
	game.scores[1] = 3
	game.tick(1.1)
	assert_true(game.finished)
	assert_eq(game.get_results().placements[0], [1])
