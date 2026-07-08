extends GutTest
## Ro-Sham-Bo Royale sim (M14-05): group RPS elimination pools, wash redraws,
## the sudden-death 1v1 decider, spectate-vote bonus coins, and ranking.

const TICK := 1.0 / 30.0


func _game_with(count: int) -> RoShamBo:
	var game := RoShamBo.new()
	game.meta = RoShamBo.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 7)
	return game


func _pad_pos(game: RoShamBo, shape: int) -> Vector2:
	for pad: Dictionary in game.pads:
		if int(pad.shape) == shape:
			return pad.pos
	return Vector2.ZERO


## Drives every given slot onto its shape's pad, then ticks once.
func _throw_all(game: RoShamBo, throws_by_slot: Dictionary) -> void:
	for slot: int in throws_by_slot:
		game.positions[slot] = _pad_pos(game, throws_by_slot[slot])
	game.tick(TICK)


func test_meta() -> void:
	var meta := RoShamBo.make_meta()
	assert_eq(meta.id, &"ro_sham_bo")
	assert_eq(meta.category, MinigameMeta.Category.SKILL)
	assert_eq(meta.min_players, 2)
	assert_eq(meta.max_players, 24)


func test_registered_in_catalog() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"ro_sham_bo") is RoShamBo)
	MinigameCatalog.clear()


func test_two_distinct_shapes_eliminates_the_losing_shape() -> void:
	var game := _game_with(3)
	_throw_all(game, {0: RoShamBo.Shape.ROCK, 1: RoShamBo.Shape.ROCK, 2: RoShamBo.Shape.PAPER})
	assert_eq(game.phase, RoShamBo.Phase.REVEAL)
	assert_eq(game.eliminated_order, [[0, 1]], "paper beats rock — both rocks are out")


func test_all_three_shapes_is_a_wash() -> void:
	var game := _game_with(3)
	_throw_all(game, {0: RoShamBo.Shape.ROCK, 1: RoShamBo.Shape.PAPER, 2: RoShamBo.Shape.SCISSORS})
	assert_eq(game.eliminated_order, [], "no clear winner among three shapes")
	assert_true(game.last_result.wash)


func test_everyone_matching_is_a_wash() -> void:
	var game := _game_with(3)
	_throw_all(
		game, {0: RoShamBo.Shape.SCISSORS, 1: RoShamBo.Shape.SCISSORS, 2: RoShamBo.Shape.SCISSORS}
	)
	assert_eq(game.eliminated_order, [])
	assert_true(game.last_result.wash)


func test_wash_redraws_after_the_reveal_gap() -> void:
	var game := _game_with(3)
	_throw_all(game, {0: RoShamBo.Shape.ROCK, 1: RoShamBo.Shape.PAPER, 2: RoShamBo.Shape.SCISSORS})
	game._phase_left = 0.0
	game.tick(TICK)
	assert_eq(game.phase, RoShamBo.Phase.THROW, "the pool redraws, nobody is out")
	assert_eq(game.throws, {}, "throws reset for the new sub-round")


func test_uneven_split_can_eliminate_straight_to_a_champion() -> void:
	var game := _game_with(3)
	_throw_all(game, {0: RoShamBo.Shape.ROCK, 1: RoShamBo.Shape.ROCK, 2: RoShamBo.Shape.PAPER})
	game._phase_left = 0.0
	game.tick(TICK)
	assert_true(game.finished, "one player left after the elimination — match over")
	assert_eq(game.get_results().placements, [[2], [0, 1]])


func test_slow_player_gets_a_random_throw_at_timeout() -> void:
	var game := _game_with(2)
	game.positions[0] = _pad_pos(game, RoShamBo.Shape.ROCK)
	game._phase_left = 0.0
	game.tick(TICK)
	assert_true(game.throws.has(1), "slot 1 never moved but still got a throw")
	assert_eq(game.phase, RoShamBo.Phase.REVEAL)


func test_snapshot_hides_thrown_shapes_until_reveal() -> void:
	var game := _game_with(2)
	game.positions[0] = _pad_pos(game, RoShamBo.Shape.ROCK)
	game.tick(TICK)
	var mid_snapshot := game.get_snapshot()
	assert_eq(mid_snapshot.last_result, {}, "no reveal data mid-throw")
	assert_eq(int(mid_snapshot.players[0][RoShamBo.PS_THROWN]), 1, "locked-in is public")
	assert_eq(int(mid_snapshot.players[1][RoShamBo.PS_THROWN]), 0)
	game.positions[1] = _pad_pos(game, RoShamBo.Shape.SCISSORS)
	game.tick(TICK)
	var reveal_snapshot := game.get_snapshot()
	assert_eq(
		reveal_snapshot.last_result.throws, {0: RoShamBo.Shape.ROCK, 1: RoShamBo.Shape.SCISSORS}
	)


func test_two_players_tying_enters_sudden_death() -> void:
	var game := _game_with(2)
	_throw_all(game, {0: RoShamBo.Shape.ROCK, 1: RoShamBo.Shape.ROCK})
	assert_true(game.last_result.wash)
	game._phase_left = 0.0
	game.tick(TICK)
	assert_true(game.sudden_death, "a 2-player tie can't redraw normally — it's sudden death")
	assert_true(
		game.target_shape in [RoShamBo.Shape.ROCK, RoShamBo.Shape.PAPER, RoShamBo.Shape.SCISSORS]
	)


func test_sudden_death_correct_counter_wins_outright() -> void:
	var game := _game_with(2)
	_throw_all(game, {0: RoShamBo.Shape.ROCK, 1: RoShamBo.Shape.ROCK})
	game._phase_left = 0.0
	game.tick(TICK)
	assert_true(game.sudden_death)
	var target: int = game.target_shape
	var counter: int = {
		RoShamBo.Shape.ROCK: RoShamBo.Shape.PAPER,
		RoShamBo.Shape.PAPER: RoShamBo.Shape.SCISSORS,
		RoShamBo.Shape.SCISSORS: RoShamBo.Shape.ROCK,
	}[target]
	var wrong: int = {
		RoShamBo.Shape.ROCK: RoShamBo.Shape.SCISSORS,
		RoShamBo.Shape.PAPER: RoShamBo.Shape.ROCK,
		RoShamBo.Shape.SCISSORS: RoShamBo.Shape.PAPER,
	}[target]
	_throw_all(game, {0: counter, 1: wrong})
	assert_eq(game.eliminated_order, [[1]], "only the correct counter survives")
	game._phase_left = 0.0
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[0], [1]])


func test_sudden_death_both_correct_is_still_a_tie() -> void:
	var game := _game_with(2)
	_throw_all(game, {0: RoShamBo.Shape.ROCK, 1: RoShamBo.Shape.ROCK})
	game._phase_left = 0.0
	game.tick(TICK)
	var target: int = game.target_shape
	var counter: int = {
		RoShamBo.Shape.ROCK: RoShamBo.Shape.PAPER,
		RoShamBo.Shape.PAPER: RoShamBo.Shape.SCISSORS,
		RoShamBo.Shape.SCISSORS: RoShamBo.Shape.ROCK,
	}[target]
	_throw_all(game, {0: counter, 1: counter})
	assert_eq(game.eliminated_order, [], "both correct — still tied")
	game._phase_left = 0.0
	game.tick(TICK)
	assert_true(game.sudden_death, "stays in sudden death until it's broken")


func test_eliminated_player_can_vote_for_the_champion() -> void:
	var game := _game_with(3)
	_throw_all(game, {0: RoShamBo.Shape.ROCK, 1: RoShamBo.Shape.ROCK, 2: RoShamBo.Shape.PAPER})
	game.handle_input(0, {"vote": 2})
	assert_eq(game.votes, {0: 2}, "an eliminated player can vote once seated")
	game.handle_input(0, {"vote": 1})
	assert_eq(game.votes[0], 2, "no changing your vote")


func test_alive_player_cannot_vote() -> void:
	var game := _game_with(3)
	game.handle_input(0, {"vote": 1})
	assert_false(game.votes.has(0), "still alive — nothing to spectate yet")


func test_voting_for_yourself_or_a_dead_player_is_rejected() -> void:
	var game := _game_with(4)
	_throw_all(
		game,
		{
			0: RoShamBo.Shape.ROCK,
			1: RoShamBo.Shape.ROCK,
			2: RoShamBo.Shape.PAPER,
			3: RoShamBo.Shape.PAPER,
		}
	)
	assert_eq(game.eliminated_order, [[0, 1]])
	game.handle_input(0, {"vote": 0})
	assert_false(game.votes.has(0), "cannot vote for yourself")
	game.handle_input(1, {"vote": 0})
	assert_false(game.votes.has(1), "cannot vote for another eliminated player")


func test_correct_vote_pays_a_bonus_coin_at_match_end() -> void:
	var game := _game_with(3)
	_throw_all(game, {0: RoShamBo.Shape.ROCK, 1: RoShamBo.Shape.ROCK, 2: RoShamBo.Shape.PAPER})
	game.handle_input(0, {"vote": 2})
	game.handle_input(1, {"vote": 0})  # slot 0 is already out — a bad call
	game._phase_left = 0.0
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().pickup_coins, {0: RoShamBo.VOTE_BONUS_COINS})


func test_timeout_ranking_ties_survivors_ahead_of_the_eliminated() -> void:
	var game := _game_with(4)
	game.eliminated_order = [[0], [1]]
	game.duration_override = TICK
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[2, 3], [1], [0]])


func test_setup_handles_twenty_four_players() -> void:
	var game := _game_with(24)
	assert_eq(game._alive_slots().size(), 24)
	assert_eq(game.pads.size(), 3)
