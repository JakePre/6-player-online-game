extends GutTest
## Tug of War (SPEC $7 #11): alternating-pull gating, rope math, line-cross
## wins, timeout advantage, and team_mode award routing.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1]) -> TugOfWar:
	var game := TugOfWar.new()
	game.meta = TugOfWar.make_meta()
	game.setup(player_slots, 42)
	return game


## One valid alternated pull for `slot` (phase 0 then 1 counts as two).
func _pull(game: TugOfWar, slot: int, times: int) -> void:
	for i in times:
		game.handle_input(slot, {"pull": i % 2})


func test_meta() -> void:
	var meta := TugOfWar.make_meta()
	assert_eq(meta.id, &"tug_of_war")
	assert_eq(meta.category, MinigameMeta.Category.TEAM)
	assert_eq(meta.min_players, 2)
	assert_eq(meta.max_players, 24)
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")


func test_registered_in_catalog() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"tug_of_war") is TugOfWar)
	MinigameCatalog.clear()


func test_even_team_split_at_all_player_counts() -> void:
	for count: int in [2, 4, 6, 12, 24]:
		var player_slots: Array[int] = []
		for slot in count:
			player_slots.append(slot)
		var game := _game(player_slots)
		assert_eq(game.team_a.size(), count / 2, "%d players" % count)
		assert_eq(game.team_b.size(), count / 2, "%d players" % count)
		for slot: int in player_slots:
			assert_true(slot in game.team_a or slot in game.team_b)


func test_sets_team_mode() -> void:
	var game := _game()
	assert_true(game.team_mode)
	game.finish(game._rank_players())
	assert_true(game.get_results().team_mode)


func test_alternating_pulls_move_the_rope() -> void:
	var game := _game()
	var puller: int = game.team_a[0]
	_pull(game, puller, 2)
	assert_almost_eq(game.rope, -TugOfWar.PULL_STRENGTH * 2.0, 0.001)


func test_repeated_phase_does_not_count() -> void:
	var game := _game()
	var puller: int = game.team_a[0]
	game.handle_input(puller, {"pull": 0})
	game.handle_input(puller, {"pull": 0})
	game.handle_input(puller, {"pull": 0})
	assert_almost_eq(game.rope, -TugOfWar.PULL_STRENGTH, 0.001, "held key counts once")


func test_invalid_pull_values_ignored() -> void:
	var game := _game()
	game.handle_input(game.team_a[0], {"pull": 7})
	game.handle_input(game.team_a[0], {"mx": 1.0})
	assert_eq(game.rope, 0.0)


func test_opposing_pulls_cancel() -> void:
	var game := _game()
	_pull(game, game.team_a[0], 2)
	_pull(game, game.team_b[0], 2)
	assert_almost_eq(game.rope, 0.0, 0.001)


func test_uneven_teams_have_equal_total_pull() -> void:
	var game := _game([0, 1, 2, 3, 4] as Array[int])
	var big: Array = game.team_a if game.team_a.size() == 3 else game.team_b
	var small: Array = game.team_a if game.team_a.size() == 2 else game.team_b
	assert_eq(big.size(), 3)
	assert_eq(small.size(), 2)
	# Every member of each side pulls twice: the rope must end dead level.
	for slot: int in big:
		_pull(game, slot, 2)
	for slot: int in small:
		_pull(game, slot, 2)
	assert_almost_eq(game.rope, 0.0, 0.001, "equal mash rates cancel at 3v2 (#137)")


func test_dragging_over_the_line_wins() -> void:
	var game := _game()
	var pulls_needed := int(ceil(TugOfWar.WIN_OFFSET / TugOfWar.PULL_STRENGTH))
	_pull(game, game.team_a[0], pulls_needed + 1)
	game.tick(TICK)
	assert_true(game.finished)
	var placements: Array = game.get_results().placements
	assert_eq(placements[0], game.team_a)
	assert_eq(placements[1], game.team_b)
	assert_true(game.get_results().team_mode)


func test_timeout_rope_advantage_decides() -> void:
	var game := _game()
	_pull(game, game.team_b[0], 2)
	game.duration_override = TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [game.team_b, game.team_a])


func test_timeout_dead_level_is_a_tie() -> void:
	var game := _game()
	game.duration_override = TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0, 1]])


func test_snapshot_shape() -> void:
	var game := _game()
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.rope, 0.0)
	assert_eq(snapshot.win_offset, TugOfWar.WIN_OFFSET)
	assert_eq(snapshot.team_a.size() + snapshot.team_b.size(), 2)
