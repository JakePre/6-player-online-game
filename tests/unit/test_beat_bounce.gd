extends GutTest
## Beat Bounce server sim (reworked #259): Simon-Says-on-a-clock — WATCH
## demonstrates a growing pad sequence one-per-beat, REPEAT judges each step
## against its beat window (right pad = clear, wrong/missed/off-beat = strike),
## two strikes in a round eliminate, and the sequence grows + tempo ramps each
## round.

const WINDOW := BeatBounce.HIT_WINDOW_SEC


func _make_game(player_count: int) -> BeatBounce:
	var game := BeatBounce.new()
	game.meta = BeatBounce.make_meta()
	var slots: Array[int] = []
	for i in player_count:
		slots.append(i)
	game.setup(slots, 42)
	return game


## Ticks in small steps until a predicate holds (or a safety cap trips).
func _tick_until(game: BeatBounce, predicate: Callable) -> void:
	var guard := 0
	while not predicate.call() and not game.finished and guard < 5000:
		game.tick(0.02)
		guard += 1


func _reach_repeat(game: BeatBounce) -> void:
	_tick_until(game, func() -> bool: return game.phase == BeatBounce.Phase.REPEAT)


## True while a REPEAT step's hit window is open for input.
func _window_open(game: BeatBounce) -> bool:
	return (
		game.phase == BeatBounce.Phase.REPEAT
		and not game._prev_closed
		and game.phase_step >= 0
		and game.phase_step < game.sequence.size()
	)


func test_setup_starts_watching_a_short_sequence() -> void:
	var game := _make_game(3)
	assert_eq(game.phase, BeatBounce.Phase.WATCH)
	assert_eq(game.sequence.size(), BeatBounce.START_LENGTH)
	for slot in 3:
		assert_true(game.alive[slot])
		assert_eq(game.strikes[slot], 0)


func test_watch_reveals_the_sequence_but_repeat_hides_it() -> void:
	var game := _make_game(2)
	assert_eq(game.get_snapshot().sequence.size(), game.sequence.size(), "shown while watching")
	_reach_repeat(game)
	assert_eq(game.get_snapshot().sequence.size(), 0, "hidden so REPEAT can't be light-read")


func test_flash_walks_the_sequence_during_watch() -> void:
	var game := _make_game(2)
	var seen: Array[int] = []
	_tick_until(
		game,
		func() -> bool:
			if game.phase == BeatBounce.Phase.WATCH and game.flash_pad != -1:
				if seen.is_empty() or seen[-1] != game.flash_pad:
					seen.append(game.flash_pad)
			return game.phase == BeatBounce.Phase.REPEAT
	)
	assert_eq(seen, game.sequence, "every sequence pad flashed, in order")


func test_right_pad_on_the_beat_clears_the_step() -> void:
	var game := _make_game(2)
	_tick_until(game, func() -> bool: return _window_open(game))
	var expected: int = game.sequence[game.phase_step]
	game.handle_input(0, {"pad": expected})
	assert_eq(game.strikes[0], 0, "correct + on time = safe")
	assert_eq(game.progress[0], 1, "step cleared")


func test_wrong_pad_on_the_beat_is_a_strike() -> void:
	var game := _make_game(2)
	_tick_until(game, func() -> bool: return _window_open(game))
	var wrong: int = (int(game.sequence[game.phase_step]) + 1) % BeatBounce.PAD_COUNT
	game.handle_input(0, {"pad": wrong})
	assert_eq(game.strikes[0], 1)
	assert_eq(game.progress[0], 0)


func test_missing_a_beat_strikes_on_close() -> void:
	var game := _make_game(2)
	_tick_until(game, func() -> bool: return _window_open(game))
	var target := game._prev_beat + WINDOW + 0.05
	# Slot 1 hits, slot 0 stays idle through the window's close.
	game.handle_input(1, {"pad": game.sequence[game.phase_step]})
	while game.elapsed < target and not game.finished:
		game.tick(0.02)
	assert_eq(game.strikes[0], 1, "the idle player missed the step")
	assert_eq(game.strikes[1], 0, "the one who hit is safe")


func test_double_hit_on_one_step_is_swallowed() -> void:
	var game := _make_game(2)
	_tick_until(game, func() -> bool: return _window_open(game))
	var expected: int = game.sequence[game.phase_step]
	game.handle_input(0, {"pad": expected})
	game.handle_input(0, {"pad": (expected + 1) % BeatBounce.PAD_COUNT})  # same beat
	assert_eq(game.strikes[0], 0, "already resolved this step; the repeat is ignored")
	assert_eq(game.progress[0], 1)


func test_watch_presses_are_ignored() -> void:
	var game := _make_game(2)
	assert_eq(game.phase, BeatBounce.Phase.WATCH)
	game.handle_input(0, {"pad": 0})
	game.handle_input(0, {"pad": 1})
	assert_eq(game.strikes[0], 0, "you cannot strike while watching")


func test_two_strikes_in_a_round_eliminate() -> void:
	var game := _make_game(3)
	_reach_repeat(game)
	# Force two clean misses for slot 0 by driving through two step closes.
	var start_round := game.round_index
	_tick_until(
		game,
		func() -> bool: return not game.alive[0] or game.round_index != start_round or game.finished
	)
	# Slot 0 never sent input, so it should have struck out this round.
	assert_false(game.alive[0], "two missed steps eliminate")
	assert_eq(game.eliminated_on[0], start_round)


func test_clearing_a_round_grows_the_sequence_and_ramps_tempo() -> void:
	var game := _make_game(2)
	var first_len := game.sequence.size()
	var first_interval := game.interval
	# Auto-clear every step for both players until the round rolls over.
	var start_round := game.round_index
	var guard := 0
	while game.round_index == start_round and not game.finished and guard < 5000:
		if _window_open(game):
			for slot in 2:
				if not game._resolved_this_beat.has(slot):
					game.handle_input(slot, {"pad": game.sequence[game.phase_step]})
		game.tick(0.02)
		guard += 1
	assert_eq(game.round_index, start_round + 1, "a cleared round advances")
	assert_eq(game.sequence.size(), first_len + 1, "the sequence grows by one")
	assert_lt(game.interval, first_interval, "and the tempo climbs")
	assert_eq(game.strikes[0], 0, "round strikes reset for survivors")


func test_ranking_survivors_first_then_by_elimination_round() -> void:
	var game := _make_game(4)
	game.round_index = 5
	game.alive[0] = false
	game.eliminated_on[0] = 1
	game.alive[1] = false
	game.eliminated_on[1] = 3
	game.progress[2] = 2
	game.progress[3] = 0
	var placements := game._rank_players()
	assert_eq(placements[0], [2], "survivor further into the round")
	assert_eq(placements[1], [3], "survivor")
	assert_eq(placements[2], [1], "fell in round 3")
	assert_eq(placements[3], [0], "fell in round 1")


func test_snapshot_shape() -> void:
	var game := _make_game(2)
	var snap := game.get_snapshot()
	assert_eq(snap.phase, BeatBounce.Phase.WATCH)
	assert_eq(snap.pad_count, BeatBounce.PAD_COUNT)
	assert_true(snap.has("beat") and snap.has("next_in") and snap.has("progress"))


func test_max_players_raised_to_twenty_four() -> void:
	assert_eq(BeatBounce.make_meta().max_players, 24)


## No arena/position state (M15): a 24-player match just tracks 24 sets of
## strikes/alive/progress against the same shared beat clock and pad sequence.
func test_setup_handles_twenty_four_players() -> void:
	var game := _make_game(24)
	assert_eq(game.alive.size(), 24)
	for slot in 24:
		assert_true(game.alive[slot])
		assert_eq(game.strikes[slot], 0)
	# Everyone can clear a step on the same beat with no exclusivity conflict.
	_tick_until(game, func() -> bool: return _window_open(game))
	var expected: int = game.sequence[game.phase_step]
	for slot in 24:
		game.handle_input(slot, {"pad": expected})
	for slot in 24:
		assert_eq(game.strikes[slot], 0)
		assert_eq(game.progress[slot], 1)
