extends GutTest
## Best-of-N series (M11-01): points table with tie sharing, the coin
## tiebreak, completion, resets, and Room/MatchController integration.


func _rows(scores: Dictionary) -> Array:
	var rows: Array = []
	for slot: int in scores:
		rows.append({"slot": slot, "name": "P%d" % slot, "score": scores[slot]})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	return rows


func test_idle_at_length_one() -> void:
	var series := SeriesTracker.new()
	series.record_match(_rows({0: 100, 1: 50}))
	assert_false(series.is_active())
	assert_eq(series.matches_played, 0, "single matches never accumulate")


func test_points_by_placement() -> void:
	var series := SeriesTracker.new()
	series.reset(3)
	series.record_match(_rows({0: 60, 1: 50, 2: 40, 3: 30, 4: 20, 5: 10}))
	assert_eq(series.points, {0: 10, 1: 7, 2: 5, 3: 4, 4: 3, 5: 2})


func test_ties_share_the_higher_value_and_consume_ranks() -> void:
	var series := SeriesTracker.new()
	series.reset(3)
	series.record_match(_rows({0: 50, 1: 50, 2: 30}))
	assert_eq(series.points[0], 10)
	assert_eq(series.points[1], 10, "tied for first share 10")
	assert_eq(series.points[2], 5, "next rank is 3rd (5), like SPEC $5")


func test_accumulates_across_matches_and_completes() -> void:
	var series := SeriesTracker.new()
	series.reset(3)
	for _i in 2:
		series.record_match(_rows({0: 60, 1: 30}))
	assert_false(series.is_complete())
	series.record_match(_rows({1: 60, 0: 30}))
	assert_true(series.is_complete())
	assert_eq(series.points, {0: 27, 1: 24})
	assert_eq(series.champions(), [0])


func test_point_tie_breaks_by_series_coins() -> void:
	var series := SeriesTracker.new()
	series.reset(1)
	series.length = 2
	series.record_match(_rows({0: 60, 1: 30}))
	series.record_match(_rows({1: 90, 0: 30}))
	# Both have 10 + 7 = 17 points; slot 1 earned 120 coins vs slot 0's 90.
	assert_eq(series.points[0], series.points[1])
	assert_eq(series.champions(), [1], "coin tiebreak decides")
	assert_eq(series.standings()[0].slot, 1)


func test_reset_zeroes_everything() -> void:
	var series := SeriesTracker.new()
	series.reset(3)
	series.record_match(_rows({0: 60, 1: 30}))
	series.reset(5)
	assert_eq(series.length, 5)
	assert_eq(series.matches_played, 0)
	assert_eq(series.points, {})


func test_room_setting_is_lobby_only_and_validated() -> void:
	var room := Room.new()
	room.add_member(100, "A", "t1")
	assert_true(room.set_series_length(3))
	assert_eq(room.series.length, 3)
	assert_false(room.set_series_length(4), "only 1/3/5")
	room.state = Room.State.IN_MATCH
	assert_false(room.set_series_length(5), "lobby only")
	assert_eq(room.to_state_dict().series.length, 3, "state dict carries the series")


func test_completed_series_restarts_on_next_match_start() -> void:
	var room := Room.new()
	room.add_member(100, "A", "t1")
	room.add_member(200, "B", "t2")
	room.set_series_length(3)
	room.series.matches_played = 3
	assert_true(room.series.is_complete())
	for member in room.members:
		member.ready = true
	assert_true(room.start_match())
	assert_eq(room.series.matches_played, 0, "fresh series, same length")
	assert_eq(room.series.length, 3)


func test_match_controller_records_into_the_series() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register(
		MinigameMeta.create({"id": &"stub", "duration_sec": 60.0}), MinigameBase
	)
	var room := Room.new()
	room.code = "SERIES"
	room.add_member(100, "A", "t1")
	room.add_member(200, "B", "t2")
	room.set_series_length(3)
	var events: Array = []
	var controller := (
		MatchController
		. new(
			room,
			{
				"seed": 7,
				"playlist": [&"stub"],
				"intro_sec": 0.05,
				"results_sec": 0.05,
				"podium_sec": 0.05,
				"duration_override": 0.05,
			}
		)
	)
	controller.event_emitted.connect(func(event: Dictionary) -> void: events.append(event))
	controller.start()
	for _i in 10_000:
		if controller.is_done():
			break
		controller.tick(1.0 / 30.0)
	assert_eq(room.series.matches_played, 1)
	var ended: Array = events.filter(
		func(event: Dictionary) -> bool: return String(event.type) == "match_ended"
	)
	assert_eq(ended.size(), 1)
	assert_eq(int(ended[0].series.matches_played), 1, "event carries the series payload")
	MinigameCatalog.clear()
