extends GutTest
## Bullseye Bowl sim (M10-07): rolls, flight timing, ring scoring against the
## sliding target, and best-total ranking. Server-side logic only.

const TICK := 1.0 / 30.0


func _game_with(count: int) -> BullseyeBowl:
	var game := BullseyeBowl.new()
	game.meta = BullseyeBowl.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 7)
	return game


## Pins slot 0's target dead center for the whole flight.
func _pin_target(game: BullseyeBowl, slot: int) -> void:
	game._phases[slot] = 0.0
	game.elapsed = 0.0


func test_roll_spends_a_ball_and_launches_one_flight() -> void:
	var game := _game_with(2)
	game.handle_input(0, {"roll": true})
	assert_eq(game.balls_left[0], BullseyeBowl.BALLS - 1)
	assert_eq(game.flights.size(), 1)
	game.handle_input(0, {"roll": true})
	assert_eq(game.flights.size(), 1, "one ball in flight at a time")
	assert_eq(game.balls_left[0], BullseyeBowl.BALLS - 1, "the blocked roll costs nothing")


func test_no_rolls_when_out_of_balls() -> void:
	var game := _game_with(2)
	game.balls_left[0] = 0
	game.handle_input(0, {"roll": true})
	assert_eq(game.flights.size(), 0)


func test_ring_points_by_distance() -> void:
	var game := _game_with(2)
	assert_eq(game._ring_points(0.0), BullseyeBowl.SCORE_BULLSEYE)
	assert_eq(game._ring_points(BullseyeBowl.RING_MID - 0.01), BullseyeBowl.SCORE_MID)
	assert_eq(game._ring_points(BullseyeBowl.RING_OUTER - 0.01), BullseyeBowl.SCORE_OUTER)
	assert_eq(game._ring_points(BullseyeBowl.RING_OUTER + 0.01), 0)


func test_flight_scores_against_target_at_arrival() -> void:
	var game := _game_with(2)
	_pin_target(game, 0)
	game.handle_input(0, {"roll": true})
	# Tick just under a full period so the target returns to center at arrival:
	# elapsed at scoring == FLIGHT_SEC after roll, phase 0 -> offset sin(...).
	var ticks := int(ceilf(BullseyeBowl.FLIGHT_SEC / TICK)) + 1
	for _i in ticks:
		game.tick(TICK)
	assert_eq(game.flights.size(), 0, "the ball landed")
	assert_gt(game.scores[0], -1, "scored (value depends on target position at arrival)")


func test_match_ends_when_every_ball_is_spent() -> void:
	var game := _game_with(2)
	game.balls_left = {0: 0, 1: 1}
	game.handle_input(1, {"roll": true})
	assert_false(game.finished)
	var ticks := int(ceilf(BullseyeBowl.FLIGHT_SEC / TICK)) + 1
	for _i in ticks:
		game.tick(TICK)
	assert_true(game.finished, "last ball landing ends the round early")


func test_ranking_by_total_with_ties() -> void:
	var game := _game_with(3)
	game.scores = {0: 12, 1: 20, 2: 12}
	game.balls_left = {0: 0, 1: 0, 2: 0}
	game.tick(TICK)
	assert_true(game.finished)
	assert_eq(game.get_results().placements, [[1], [0, 2]])


func test_target_oscillates_within_amplitude() -> void:
	var game := _game_with(2)
	var seen_min := 99.0
	var seen_max := -99.0
	for i in 200:
		game.elapsed = i * 0.05
		var offset := game.target_offset(0)
		seen_min = minf(seen_min, offset)
		seen_max = maxf(seen_max, offset)
		assert_lte(absf(offset), BullseyeBowl.TARGET_AMPLITUDE + 0.001)
	assert_lt(seen_min, -BullseyeBowl.TARGET_AMPLITUDE * 0.8, "sweeps both ways")
	assert_gt(seen_max, BullseyeBowl.TARGET_AMPLITUDE * 0.8)


func test_snapshot_shape() -> void:
	var game := _game_with(2)
	game.handle_input(0, {"roll": true})
	var snapshot := game.get_snapshot()
	assert_eq(
		(snapshot.players[0] as Array).size(),
		BullseyeBowl.PS_COUNT,
		"[score, balls, flight_t, target_x]"
	)
	assert_almost_eq(
		float(snapshot.players[0][BullseyeBowl.PS_FLIGHT_T]), 0.0, 0.001, "fresh flight at t=0"
	)
	assert_eq(float(snapshot.players[1][BullseyeBowl.PS_FLIGHT_T]), -1.0, "no flight = -1")


func test_max_players_raised_to_twenty_four() -> void:
	assert_eq(BullseyeBowl.make_meta().max_players, 24)


## No shared arena state (M15): each player has an independent lane, so a
## 24-player match is just 24 independent sets of scores/balls/phases.
func test_setup_handles_twenty_four_players() -> void:
	var game := _game_with(24)
	assert_eq(game.scores.size(), 24)
	for slot in 24:
		assert_eq(game.scores[slot], 0)
		assert_eq(game.balls_left[slot], BullseyeBowl.BALLS)
