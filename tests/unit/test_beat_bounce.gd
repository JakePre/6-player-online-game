extends GutTest
## Beat Bounce server simulation (M4-09, SPEC $7 #10): beat scheduling and
## tempo ramp, on-beat/off-beat/missed-beat handling, two-strike elimination,
## and survivor-first ranking.

const FIRST_BEAT := BeatBounce.LEAD_IN_SEC
const WINDOW := BeatBounce.HIT_WINDOW_SEC


func _make_game(player_count: int) -> BeatBounce:
	var game := BeatBounce.new()
	game.meta = BeatBounce.make_meta()
	var slots: Array[int] = []
	for i in player_count:
		slots.append(i)
	game.setup(slots, 42)
	return game


## Ticks the game up to an absolute elapsed time in small steps.
func _tick_to(game: BeatBounce, target: float) -> void:
	while game.elapsed < target and not game.finished:
		game.tick(0.05)


func test_setup_all_alive_with_zero_strikes() -> void:
	var game := _make_game(3)
	for slot in 3:
		assert_true(game.alive[slot])
		assert_eq(game.strikes[slot], 0)


func test_on_beat_press_is_a_hit_not_a_strike() -> void:
	var game := _make_game(2)
	_tick_to(game, FIRST_BEAT + 0.05)
	assert_eq(game.beat_index, 1)
	game.handle_input(0, {"press": true})
	assert_eq(game.strikes[0], 0)
	assert_eq(game.last_hit[0], 1)


func test_missing_a_beat_is_a_strike() -> void:
	var game := _make_game(2)
	game.handle_input(0, {"press": true})  # off-beat during lead-in: strike 1
	assert_eq(game.strikes[0], 1)
	# Player 1 never presses: the first beat closing takes them to strike 1.
	_tick_to(game, FIRST_BEAT + WINDOW + 0.1)
	assert_eq(game.strikes[1], 1)


func test_two_strikes_eliminate_and_end_the_duel() -> void:
	var game := _make_game(2)
	game.handle_input(0, {"press": true})
	game.tick(0.01)
	game.handle_input(0, {"press": true})  # second off-beat press: eliminated
	assert_false(game.alive[0])
	# Elimination left one bouncer standing, which finishes the game.
	assert_true(game.finished)
	assert_eq(game.get_results().placements[0], [1])


func test_double_press_on_one_beat_does_not_strike() -> void:
	var game := _make_game(2)
	_tick_to(game, FIRST_BEAT + 0.05)
	game.handle_input(0, {"press": true})
	game.handle_input(0, {"press": true})  # same open beat: swallowed
	assert_eq(game.strikes[0], 0)


func test_tempo_ramps_down_to_the_floor() -> void:
	var game := _make_game(2)
	assert_eq(game.interval, BeatBounce.START_INTERVAL_SEC)
	for _i in 200:
		game._open_beat()
		game._close_beat()
	assert_eq(game.interval, BeatBounce.MIN_INTERVAL_SEC)


func test_ranking_survivors_first_then_by_beats_survived() -> void:
	var game := _make_game(4)
	game.alive[0] = false
	game.eliminated_on[0] = 3
	game.alive[1] = false
	game.eliminated_on[1] = 7
	game.strikes[2] = 1
	game.strikes[3] = 0
	var placements := game._rank_players()
	assert_eq(placements[0], [3])  # survivor, clean sheet
	assert_eq(placements[1], [2])  # survivor with a strike
	assert_eq(placements[2], [1])  # lasted to beat 7
	assert_eq(placements[3], [0])  # fell on beat 3


func test_finishes_at_duration_with_survivors_on_top() -> void:
	var game := _make_game(2)
	game.duration_override = 1.0
	game.alive[1] = false
	game.eliminated_on[1] = 1
	game.tick(1.1)
	assert_true(game.finished)
	assert_eq(game.get_results().placements[0], [0])
