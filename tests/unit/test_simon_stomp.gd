extends GutTest
## Simon Stomp server simulation (M4-05, SPEC $7 #5): show/input phases, correct
## and wrong stomps, per-round elimination, growing sequence, and ranking by
## rounds cleared.


func _make_game(player_count: int) -> SimonStomp:
	var game := SimonStomp.new()
	game.meta = SimonStomp.make_meta()
	var slots: Array[int] = []
	for i in player_count:
		slots.append(i)
	game.setup(slots, 42)
	return game


## Ticks from SHOW into INPUT (SHOW lasts a lead-in beat plus length * SHOW_PER_PAD_SEC).
func _enter_input(game: SimonStomp) -> void:
	game.tick(
		SimonStomp.SHOW_LEAD_IN_SEC + game.sequence.size() * SimonStomp.SHOW_PER_PAD_SEC + 0.05
	)
	assert_eq(game.phase, SimonStomp.Phase.INPUT)


## Feeds `slot` the whole current sequence in order.
func _stomp_full_sequence(game: SimonStomp, slot: int) -> void:
	for pad: int in game.sequence:
		game.handle_input(slot, {"pad": pad})


func test_setup_starts_in_show_with_starting_length() -> void:
	var game := _make_game(3)
	assert_eq(game.phase, SimonStomp.Phase.SHOW)
	assert_eq(game.sequence.size(), SimonStomp.START_LENGTH)
	for slot in 3:
		assert_true(game.alive[slot])
		assert_eq(game.cleared_count[slot], 0)


func test_show_advances_to_input() -> void:
	var game := _make_game(2)
	_enter_input(game)


## #588: a lead-in beat holds SHOW before the first pad flash, so tapping the
## sequence's would-be duration alone must not yet reach INPUT.
func test_show_lead_in_delays_the_first_flash() -> void:
	var game := _make_game(2)
	game.tick(game.sequence.size() * SimonStomp.SHOW_PER_PAD_SEC - 0.05)
	assert_eq(game.phase, SimonStomp.Phase.SHOW, "still watching — the lead-in hasn't elapsed yet")
	game.tick(SimonStomp.SHOW_LEAD_IN_SEC + 0.1)
	assert_eq(game.phase, SimonStomp.Phase.INPUT)


func test_input_ignored_during_show() -> void:
	var game := _make_game(2)
	game.handle_input(0, {"pad": game.sequence[0]})
	assert_eq(game.progress.get(0, 0), 0)


func test_correct_sequence_clears_the_round() -> void:
	var game := _make_game(2)
	_enter_input(game)
	_stomp_full_sequence(game, 0)
	assert_true(game.round_cleared[0])


func test_wrong_pad_eliminates_for_the_game() -> void:
	var game := _make_game(2)
	_enter_input(game)
	# Deliberately wrong first pad (sequence pads are 0-3; +1 mod 4 is always wrong).
	var wrong := (int(game.sequence[0]) + 1) % SimonStomp.PAD_COUNT
	game.handle_input(0, {"pad": wrong})
	assert_true(game.round_failed[0])
	# Other player clears; both resolved -> round ends and the wrong player is out.
	_stomp_full_sequence(game, 1)
	assert_eq(game.phase, SimonStomp.Phase.RESULT)
	assert_false(game.alive[0])
	assert_true(game.alive[1])
	assert_eq(game.cleared_count[1], 1)


func test_out_of_range_pad_is_ignored() -> void:
	var game := _make_game(2)
	_enter_input(game)
	game.handle_input(0, {"pad": 99})
	game.handle_input(0, {"pad": -1})
	assert_false(game.round_failed.get(0, false))
	assert_eq(game.progress[0], 0)


func test_all_resolved_ends_round_before_timeout() -> void:
	var game := _make_game(2)
	_enter_input(game)
	_stomp_full_sequence(game, 0)
	_stomp_full_sequence(game, 1)
	assert_eq(game.phase, SimonStomp.Phase.RESULT)


func test_sequence_grows_next_round() -> void:
	var game := _make_game(3)
	var first_length := game.sequence.size()
	_enter_input(game)
	for slot in 3:
		_stomp_full_sequence(game, slot)
	game.tick(SimonStomp.RESULT_SEC + 0.05)  # RESULT -> next round
	assert_eq(game.phase, SimonStomp.Phase.SHOW)
	assert_eq(game.sequence.size(), first_length + 1)


func test_game_ends_when_one_player_remains() -> void:
	var game := _make_game(2)
	_enter_input(game)
	_stomp_full_sequence(game, 0)  # slot 0 clears
	var wrong := (int(game.sequence[0]) + 1) % SimonStomp.PAD_COUNT
	game.handle_input(1, {"pad": wrong})  # slot 1 busts -> both resolved
	game.tick(SimonStomp.RESULT_SEC + 0.05)  # only 1 alive -> finish
	assert_true(game.finished)
	var results := game.get_results()
	assert_eq(results.placements, [[0], [1]])
	assert_eq(results.pickup_coins, {})


func test_ranking_groups_tied_cleared_counts() -> void:
	var game := _make_game(4)
	game.cleared_count = {0: 3, 1: 1, 2: 3, 3: 0}
	assert_eq(game._rank_players(), [[0, 2], [1], [3]])


func test_snapshot_hides_sequence_outside_show() -> void:
	var game := _make_game(2)
	var shown := game.get_snapshot()
	assert_eq(shown.phase, SimonStomp.Phase.SHOW)
	assert_eq((shown.sequence as Array).size(), SimonStomp.START_LENGTH)
	_enter_input(game)
	var hidden := game.get_snapshot()
	assert_eq(hidden.phase, SimonStomp.Phase.INPUT)
	assert_eq((hidden.sequence as Array).size(), 0)
	assert_eq(hidden.length, SimonStomp.START_LENGTH)


func test_max_players_raised_to_twenty_four() -> void:
	assert_eq(SimonStomp.make_meta().max_players, 24)


## No arena/position state (M15): a 24-player match just tracks 24 sets of
## alive/cleared-count against the same shared 4-pad sequence.
func test_setup_handles_twenty_four_players() -> void:
	var game := _make_game(24)
	assert_eq(game.alive.size(), 24)
	for slot in 24:
		assert_true(game.alive[slot])
		assert_eq(game.cleared_count[slot], 0)
	# Everyone can clear the round independently of headcount.
	_enter_input(game)
	for slot in 24:
		_stomp_full_sequence(game, slot)
	assert_eq(game.phase, SimonStomp.Phase.RESULT)
	for slot in 24:
		assert_eq(game.cleared_count[slot], 1)
