extends GutTest
## Shred Session server sim (M14-04): seeded 4-lane note chart, on-beat scoring
## with PERFECT/GOOD windows, streak multipliers, and per-player miss tracking.

var game: ShredSession


func before_each() -> void:
	game = ShredSession.new()
	game.meta = ShredSession.make_meta()
	game.setup([0, 1], 12345)


## Replaces the seeded chart with a known one so timing tests are deterministic.
func _load_chart(chart: Array) -> void:
	game.chart = chart
	game._miss_cursor = 0
	for slot: int in game.slots:
		game._hit[slot] = {}
		game.score[slot] = 0
		game.streak[slot] = 0
		game.event_count[slot] = 0


func test_registered_in_catalog() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.is_registered(&"shred_session"))


func test_chart_is_seeded_and_deterministic() -> void:
	var other := ShredSession.new()
	other.meta = ShredSession.make_meta()
	other.setup([0, 1], 12345)
	assert_eq(other.chart, game.chart, "same seed builds an identical chart")
	assert_gt(game.chart.size(), 0, "the song has notes")
	var different := ShredSession.new()
	different.meta = ShredSession.make_meta()
	different.setup([0, 1], 999)
	assert_ne(different.chart, game.chart, "a different seed builds a different chart")


func test_chart_notes_ride_the_lanes_and_the_song() -> void:
	for note: Dictionary in game.chart:
		assert_between(int(note.lane), 0, ShredSession.LANES - 1)
		assert_gte(float(note.time), ShredSession.LEAD_IN_SEC)
		assert_lt(float(note.time), game.effective_duration())


func test_on_beat_press_scores_a_perfect_double() -> void:
	_load_chart([{"time": 3.0, "lane": 1}])
	game.elapsed = 3.0
	game.handle_input(0, {"lane": 1})
	assert_eq(int(game.score[0]), ShredSession.PERFECT_POINTS, "dead-on is a PERFECT (double)")
	assert_eq(int(game.streak[0]), 1)
	assert_eq(int(game.last_judgment[0]), ShredSession.Judgment.PERFECT)


func test_slightly_late_press_scores_a_good_single() -> void:
	_load_chart([{"time": 3.0, "lane": 2}])
	game.elapsed = 3.0 + 0.20  # inside GOOD (0.25), outside PERFECT (0.12)
	game.handle_input(0, {"lane": 2})
	assert_eq(int(game.score[0]), ShredSession.GOOD_POINTS, "a loose hit is a GOOD (single)")
	assert_eq(int(game.last_judgment[0]), ShredSession.Judgment.GOOD)


func test_wrong_lane_press_is_a_whiff_that_breaks_the_streak() -> void:
	_load_chart([{"time": 3.0, "lane": 0}])
	game.streak[0] = 5
	game.elapsed = 3.0
	game.handle_input(0, {"lane": 3})  # note is in lane 0, not 3
	assert_eq(int(game.score[0]), 0, "no points for the wrong lane")
	assert_eq(int(game.streak[0]), 0, "the whiff breaks the streak")
	assert_eq(int(game.last_judgment[0]), ShredSession.Judgment.MISS)


func test_note_left_unhit_becomes_a_miss_on_tick() -> void:
	_load_chart([{"time": 3.0, "lane": 1}])
	game.streak[0] = 4
	game.elapsed = 3.0 + ShredSession.GOOD_SEC + 0.05
	game._tick(0.0)
	assert_eq(int(game.streak[0]), 0, "letting the note pass breaks the streak")
	assert_eq(int(game.last_judgment[0]), ShredSession.Judgment.MISS)
	assert_eq(game._miss_cursor, 1, "the closed note advances the cursor")


func test_streak_multiplier_kicks_in_at_the_tier() -> void:
	var chart: Array = []
	for i in 8:
		chart.append({"time": 3.0 + i, "lane": 0})
	_load_chart(chart)
	for i in 8:
		game.elapsed = 3.0 + i
		game.handle_input(0, {"lane": 0})
	# Hits 1-7 score 2 each at x1 (14); hit 8 reaches streak 8 → x2, scoring 4.
	assert_eq(int(game.streak[0]), 8)
	assert_eq(int(game.score[0]), 18, "the 8th clean hit lands the x2 multiplier")


func test_ranking_orders_by_score() -> void:
	_load_chart([{"time": 3.0, "lane": 0}])
	game.score[0] = 40
	game.score[1] = 90
	var placements := game._rank_players()
	assert_eq(placements[0], [1], "the higher score ranks first")
	assert_eq(placements[1], [0])


func test_snapshot_advertises_the_lookahead_window() -> void:
	_load_chart([{"time": 3.0, "lane": 0}, {"time": 30.0, "lane": 1}])
	game.elapsed = 2.0
	var snap := game.get_snapshot()
	assert_has(snap, "elapsed")
	assert_has(snap, "players")
	assert_eq(snap.notes.size(), 1, "only the near note is inside the lookahead")
	assert_eq(int(snap.players[0].size()), 5, "per-player: score, streak, judgment, lane, events")
