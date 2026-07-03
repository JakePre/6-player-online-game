extends GutTest
## Count Quick sim (M10-08): flash/answer phases, lock-on-touch scoring with
## the first-correct bonus, anti-peek replication, and total ranking.

const TICK := 1.0 / 30.0


func _game_with(count: int) -> CountQuick:
	var game := CountQuick.new()
	game.meta = CountQuick.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 7)
	return game


func _pad_with_value(game: CountQuick, value: int) -> Dictionary:
	for pad: Dictionary in game.pads:
		if int(pad.value) == value:
			return pad
	return {}


func _wrong_pad(game: CountQuick) -> Dictionary:
	for pad: Dictionary in game.pads:
		if int(pad.value) != game.correct_count:
			return pad
	return {}


func _to_answer(game: CountQuick) -> void:
	game._phase_left = 0.0
	game.tick(TICK)


func test_flash_deals_a_swarm_matching_the_answer() -> void:
	var game := _game_with(2)
	assert_eq(game.phase, CountQuick.Phase.FLASH)
	assert_eq(game.swarm.size(), game.correct_count)
	assert_between(game.correct_count, CountQuick.SWARM_MIN, CountQuick.SWARM_MAX)


func test_pads_offer_the_correct_count_plus_distractors() -> void:
	var game := _game_with(2)
	_to_answer(game)
	assert_eq(game.pads.size(), 4)
	assert_false(_pad_with_value(game, game.correct_count).is_empty(), "truth among the pads")
	var values := {}
	for pad: Dictionary in game.pads:
		values[int(pad.value)] = true
	assert_eq(values.size(), 4, "all pad values distinct")


func test_swarm_hidden_from_snapshots_during_answers() -> void:
	var game := _game_with(2)
	assert_eq(game.get_snapshot().swarm.size(), game.correct_count)
	assert_eq(game.get_snapshot().pads.size(), 0, "no pads while flashing")
	_to_answer(game)
	assert_eq(game.get_snapshot().swarm.size(), 0, "answer-phase clients cannot recount")
	assert_eq(game.get_snapshot().pads.size(), 4)


func test_first_correct_lock_scores_double() -> void:
	var game := _game_with(3)
	_to_answer(game)
	var right: Dictionary = _pad_with_value(game, game.correct_count)
	game.positions[1] = right.pos
	game.tick(TICK)
	assert_eq(game.scores[1], CountQuick.SCORE_FIRST, "first correct pays double")
	game.positions[2] = right.pos
	game.tick(TICK)
	assert_eq(game.scores[2], CountQuick.SCORE_CORRECT, "later corrects pay single")
	assert_eq(game.locked[1], game.locked[2], "both locked the same pad")


func test_wrong_pad_locks_for_zero_and_no_takebacks() -> void:
	var game := _game_with(2)
	_to_answer(game)
	var wrong: Dictionary = _wrong_pad(game)
	game.positions[0] = wrong.pos
	game.tick(TICK)
	assert_eq(game.scores[0], 0)
	assert_ne(game.locked[0], -1)
	var right: Dictionary = _pad_with_value(game, game.correct_count)
	game.positions[0] = right.pos
	game.tick(TICK)
	assert_eq(game.scores[0], 0, "locked answers cannot be changed")


func test_all_locked_advances_the_round_early() -> void:
	var game := _game_with(2)
	_to_answer(game)
	var right: Dictionary = _pad_with_value(game, game.correct_count)
	game.positions[0] = right.pos
	game.positions[1] = _wrong_pad(game).pos
	game.tick(TICK)
	game.tick(TICK)
	assert_eq(game.round_number, 1, "everyone locked = next round")
	assert_eq(game.phase, CountQuick.Phase.FLASH)
	assert_eq(game.locked[0], -1, "locks reset with the new deal")


func test_six_rounds_then_ranking_by_total() -> void:
	var game := _game_with(3)
	game.scores = {0: 5, 1: 9, 2: 5}
	game.round_number = CountQuick.ROUNDS - 1
	game.phase = CountQuick.Phase.ANSWER
	game._phase_left = 0.0
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0, 2]])


func test_snapshot_shape() -> void:
	var game := _game_with(2)
	var snapshot := game.get_snapshot()
	assert_eq((snapshot.players[0] as Array).size(), 4, "[x, y, score, locked]")
	assert_eq(snapshot.round, 0)


## Review fix on #224: two players locking the correct pad on the same tick
## are a tie group — both get the first-correct double, slot order never
## decides a photo finish.
func test_same_tick_correct_locks_share_the_first_double() -> void:
	var game := _game_with(3)
	_to_answer(game)
	var correct_pad := _pad_with_value(game, game.correct_count)
	game.positions[0] = correct_pad.pos
	game.positions[1] = correct_pad.pos
	game.tick(TICK)
	assert_eq(game.scores[0], CountQuick.SCORE_FIRST)
	assert_eq(game.scores[1], CountQuick.SCORE_FIRST)
	# A later correct lock is past the photo finish: single points only.
	game.positions[2] = correct_pad.pos
	game.tick(TICK)
	assert_eq(game.scores[2], CountQuick.SCORE_CORRECT)
