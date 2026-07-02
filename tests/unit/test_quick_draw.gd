extends GutTest
## Quick Draw server simulation (M4-06, SPEC $7 #7): wait/signal phases,
## false starts, round resolution, and best-of-5 ranking.

const PAST_WAIT := QuickDraw.WAIT_MAX_SEC + 0.1
const PAST_TIMEOUT := QuickDraw.LIVE_TIMEOUT_SEC + 0.1
const PAST_GAP := QuickDraw.ROUND_GAP_SEC + 0.1


func _make_game(player_count: int) -> QuickDraw:
	var game := QuickDraw.new()
	game.meta = QuickDraw.make_meta()
	var slots: Array[int] = []
	for i in player_count:
		slots.append(i)
	game.setup(slots, 42)
	return game


func test_setup_starts_waiting_with_zero_wins() -> void:
	var game := _make_game(3)
	assert_eq(game.phase, QuickDraw.Phase.WAITING)
	for slot in 3:
		assert_eq(game.wins[slot], 0)


func test_early_press_is_a_false_start_and_cannot_win() -> void:
	var game := _make_game(2)
	game.tick(0.1)  # well inside the 1.0-3.0s wait window
	game.handle_input(0, {"press": true})
	assert_true(game.false_started.has(0))
	assert_eq(game.wins[0], 0)

	game.tick(PAST_WAIT)  # crosses into LIVE regardless of the rolled wait_time
	assert_eq(game.phase, QuickDraw.Phase.LIVE)
	game.handle_input(0, {"press": true})  # already acted this round; ignored
	assert_eq(game.wins[0], 0)
	assert_eq(game.winner_slot, -1)


func test_first_correct_press_during_live_wins_the_round() -> void:
	var game := _make_game(2)
	game.tick(PAST_WAIT)
	assert_eq(game.phase, QuickDraw.Phase.LIVE)
	game.handle_input(1, {"press": true})
	assert_eq(game.wins[1], 1)
	assert_eq(game.winner_slot, 1)
	assert_eq(game.phase, QuickDraw.Phase.ROUND_OVER)


func test_second_press_does_not_steal_the_win() -> void:
	var game := _make_game(2)
	game.tick(PAST_WAIT)
	game.handle_input(0, {"press": true})
	game.handle_input(1, {"press": true})
	assert_eq(game.winner_slot, 0)
	assert_eq(game.wins[0], 1)
	assert_eq(game.wins[1], 0)


func test_live_timeout_with_no_press_ends_round_without_a_winner() -> void:
	var game := _make_game(2)
	game.tick(PAST_WAIT)
	game.tick(PAST_TIMEOUT)
	assert_eq(game.phase, QuickDraw.Phase.ROUND_OVER)
	assert_eq(game.winner_slot, -1)
	assert_eq(game.wins[0], 0)
	assert_eq(game.wins[1], 0)


func test_ranking_groups_tied_win_counts() -> void:
	var game := _make_game(4)
	game.wins = {0: 2, 1: 3, 2: 2, 3: 0}
	assert_eq(game._rank_players(), [[1], [0, 2], [3]])


func test_five_rounds_finish_the_match_and_rank_by_wins() -> void:
	var game := _make_game(2)
	for _round in QuickDraw.ROUNDS_TO_PLAY:
		game.tick(PAST_WAIT)
		game.handle_input(0, {"press": true})
		game.tick(PAST_GAP)

	assert_true(game.finished)
	var results := game.get_results()
	assert_eq(results.placements, [[0], [1]])
	assert_eq(results.pickup_coins, {})


func test_snapshot_reports_phase_round_and_wins() -> void:
	var game := _make_game(2)
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.phase, QuickDraw.Phase.WAITING)
	assert_eq(snapshot.round, 0)
	assert_eq(snapshot.rounds_total, QuickDraw.ROUNDS_TO_PLAY)
	assert_eq(snapshot.wins, {0: 0, 1: 0})
