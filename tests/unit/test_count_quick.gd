extends GutTest
## Count Quick sim (M10-08): flash/answer phases, no-lock-in answering scored at
## the buzzer (#799), anti-peek replication, and total ranking.

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


## FLASH -> ANSWER (expires the flash timer).
func _to_answer(game: CountQuick) -> void:
	game._phase_left = 0.0
	game.tick(TICK)


## Ends the ANSWER phase — this is where answers are scored and the next round
## deals. Players don't move (move_dirs stay zero), so scoring reads whatever
## position each slot was placed at.
func _buzzer(game: CountQuick) -> void:
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


## #799: standing on the correct pad when the timer ends scores a point — one
## point, no first-correct bonus (there is no lock-race left to reward).
func test_correct_pad_at_the_buzzer_scores() -> void:
	var game := _game_with(3)
	_to_answer(game)
	var right: Dictionary = _pad_with_value(game, game.correct_count)
	game.positions[0] = right.pos
	game.positions[1] = right.pos
	_buzzer(game)
	assert_eq(game.scores[0], CountQuick.SCORE_CORRECT, "a correct answer scores one")
	assert_eq(game.scores[1], CountQuick.SCORE_CORRECT, "no first-correct double — everyone equal")


## #799: nothing scores mid-phase — a player parked on the correct pad has zero
## until the buzzer, so the answer stays changeable right up to the end.
func test_no_score_until_the_answer_phase_ends() -> void:
	var game := _game_with(2)
	_to_answer(game)
	var right: Dictionary = _pad_with_value(game, game.correct_count)
	game.positions[0] = right.pos
	for _i in 5:
		game.tick(TICK)
	assert_eq(game.scores[0], 0, "on the right pad but the buzzer hasn't sounded")
	assert_eq(game.phase, CountQuick.Phase.ANSWER, "and the phase is still running")
	_buzzer(game)
	assert_eq(game.scores[0], CountQuick.SCORE_CORRECT, "scored only when the timer ends")


## #799: the headline fix — you can change your pick. A player on a wrong pad
## (incl. one they spawned on) can move to the right one before the buzzer and
## score, which the old auto-lock made impossible.
func test_you_can_change_your_answer_before_the_buzzer() -> void:
	var game := _game_with(2)
	_to_answer(game)
	game.positions[0] = _wrong_pad(game).pos
	for _i in 3:
		game.tick(TICK)
	assert_eq(game.scores[0], 0, "the wrong pad never locked anything in")
	game.positions[0] = _pad_with_value(game, game.correct_count).pos
	_buzzer(game)
	assert_eq(game.scores[0], CountQuick.SCORE_CORRECT, "the changed answer is the one that counts")


## #799: the reported bug — a player standing where a pad spawns is no longer
## auto-committed; ticking on that pad accrues nothing, and they're free to
## leave.
func test_standing_on_a_pad_at_answer_start_does_not_auto_answer() -> void:
	var game := _game_with(2)
	_to_answer(game)
	game.positions[0] = _wrong_pad(game).pos  # as if a pad spawned under them
	game.tick(TICK)
	assert_eq(game.scores[0], 0, "no instant lock on the pad underfoot")
	assert_eq(game.get_snapshot().players[0][CountQuick.PS_ANSWER], int(_wrong_pad(game).value))


func test_wrong_pad_at_the_buzzer_scores_zero() -> void:
	var game := _game_with(2)
	_to_answer(game)
	game.positions[0] = _wrong_pad(game).pos
	_buzzer(game)
	assert_eq(game.scores[0], 0)


func test_off_all_pads_at_the_buzzer_scores_zero() -> void:
	var game := _game_with(2)
	_to_answer(game)
	game.positions[0] = Vector2.ZERO  # dead center, on no pad
	_buzzer(game)
	assert_eq(game.scores[0], 0, "no answer given, no point")


## #799: the phase always runs its full timer now — parking on the correct pad
## never advances the round early (there is no lock-in to count).
func test_answer_phase_runs_the_full_timer() -> void:
	var game := _game_with(2)
	_to_answer(game)
	game.positions[0] = _pad_with_value(game, game.correct_count).pos
	game.positions[1] = _pad_with_value(game, game.correct_count).pos
	for _i in 5:
		game.tick(TICK)
	assert_eq(game.round_number, 0, "everyone on the answer, but the timer decides the end")
	assert_eq(game.phase, CountQuick.Phase.ANSWER)


## The snapshot reports each player's live pick: the value of the pad they're
## on during ANSWER, or -1 for none / during FLASH.
func test_snapshot_reports_the_current_pick() -> void:
	var game := _game_with(2)
	assert_eq(game.get_snapshot().players[0][CountQuick.PS_ANSWER], -1, "no pick during flash")
	_to_answer(game)
	var right: Dictionary = _pad_with_value(game, game.correct_count)
	game.positions[0] = right.pos
	game.positions[1] = Vector2.ZERO
	assert_eq(
		game.get_snapshot().players[0][CountQuick.PS_ANSWER], int(right.value), "the pad value"
	)
	assert_eq(game.get_snapshot().players[1][CountQuick.PS_ANSWER], -1, "off all pads = -1")


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
	assert_eq((snapshot.players[0] as Array).size(), CountQuick.PS_COUNT, "[x, y, score, answer]")
	assert_eq(snapshot.round, 0)


func test_max_players_raised_to_twenty_four() -> void:
	assert_eq(CountQuick.make_meta().max_players, 24)


## The count/guess phases were lengthened (#799, reported twice as too short);
## guard against a regression that shrinks them back.
func test_phases_are_lengthened_for_counting() -> void:
	assert_gte(CountQuick.FLASH_SEC, 4.0, "counting the swarm needs a real beat")
	assert_gte(CountQuick.ANSWER_SEC, 6.0, "and there's time to commit an answer")


## No player-player collision (M15): pads have no exclusive occupancy, so a
## 24-player match just tracks 24 independent scores against the shared swarm
## and pads — all correct answers score equally at the buzzer.
func test_setup_handles_twenty_four_players() -> void:
	var game := _game_with(24)
	assert_eq(game.scores.size(), 24)
	for slot in 24:
		assert_eq(game.scores[slot], 0)
	_to_answer(game)
	var correct_pad := _pad_with_value(game, game.correct_count)
	for slot in 24:
		game.positions[slot] = correct_pad.pos
	_buzzer(game)
	for slot in 24:
		assert_eq(game.scores[slot], CountQuick.SCORE_CORRECT)
