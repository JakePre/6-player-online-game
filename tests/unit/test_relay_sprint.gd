extends GutTest
## Relay Sprint (SPEC $7 #12, M15 12-cap): leg handoffs, hazard knockback,
## finish order, the multi-team award path up to twelve players, and the FFA
## sprint fallback.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2, 3, 4, 5]) -> RelaySprint:
	var game := RelaySprint.new()
	game.meta = RelaySprint.make_meta()
	game.setup(player_slots, 42)
	return game


## Runs `team_index`'s active runner straight down the lane. Relay-flow tests
## aren't hazard tests, so callers disarm the stations first (#1068) — the
## hazard types get their own targeted coverage below.
func _sprint_team(game: RelaySprint, team_index: int, legs: int) -> void:
	game.hazard_stations = []
	for _leg in legs:
		var guard := 0
		while int(game.active_leg[team_index]) < legs and guard < 100_000:
			guard += 1
			var runner: int = game.teams[team_index][int(game.active_leg[team_index])]
			game.handle_input(runner, {"mx": 1.0, "my": 0.0})
			var before := int(game.active_leg[team_index])
			game.tick(TICK)
			if game.finished:
				return
			if int(game.active_leg[team_index]) > before:
				break


func test_meta() -> void:
	var meta := RelaySprint.make_meta()
	assert_eq(meta.id, &"relay_sprint")
	assert_eq(meta.category, MinigameMeta.Category.TEAM)
	assert_eq(meta.max_players, 12, "M15: scales to six teams of two")
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")


func test_registered_in_catalog() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"relay_sprint") is RelaySprint)
	MinigameCatalog.clear()


func test_three_teams_of_two_at_six_players() -> void:
	var game := _game()
	assert_true(game.team_mode)
	assert_eq(game.teams.size(), 3)
	for team: Array in game.teams:
		assert_eq(team.size(), 2)
	# #811: merged tie groups in placements can't reveal the team count, so
	# the true count must ride the results for the award table.
	assert_eq(game.team_count, 3)


## #811: two teams finishing in the same tick merge into one placements
## group; with team_count on the results the award path pays both the
## three-team FIRST award (25) instead of reading a two-team game (20).
func test_tick_tied_finishers_share_the_higher_award() -> void:
	var game := _game()
	var placements: Array = [game.teams[0] + game.teams[1], game.teams[2]]
	var awards := Economy.award_for_teams(placements, game.team_count)
	for slot: int in placements[0]:
		assert_eq(int(awards[slot]), 25, "tied-first teams share the 3-team 1st award")
	for slot: int in placements[1]:
		assert_eq(int(awards[slot]), 5)


func test_two_teams_at_four_players() -> void:
	var game := _game([0, 1, 2, 3] as Array[int])
	assert_true(game.team_mode)
	assert_eq(game.teams.size(), 2)


## M15: six teams of two at the new twelve-player cap; every player is on
## exactly one team and each lane still gets its own independent runner.
func test_six_teams_of_two_at_twelve_players() -> void:
	var player_slots: Array[int] = []
	for slot in 12:
		player_slots.append(slot)
	var game := _game(player_slots)
	assert_true(game.team_mode)
	assert_eq(game.teams.size(), 6)
	var seen := {}
	for team: Array in game.teams:
		assert_eq(team.size(), 2)
		for slot: int in team:
			assert_false(seen.has(slot), "slot %d assigned to only one team" % slot)
			seen[slot] = true
	assert_eq(seen.size(), 12)


func test_ffa_sprint_fallback_at_two_and_odd_counts() -> void:
	for count: int in [2, 3, 5]:
		var player_slots: Array[int] = []
		for slot in count:
			player_slots.append(slot)
		var game := _game(player_slots)
		assert_false(game.team_mode, "%d players is a head-to-head sprint" % count)
		assert_eq(game.teams.size(), count)


func test_running_advances_only_forward() -> void:
	var game := _game([0, 1] as Array[int])
	var team_index := 0
	var runner: int = game.teams[team_index][0]
	game.handle_input(runner, {"mx": -1.0, "my": 0.0})
	game.tick(TICK)
	assert_eq(game.progress[team_index], 0.0, "cannot run backwards below start")


## #1068: a hit knocks you back one station gap (recentred), not to zero —
## a spinner's pivot dot sits at (x, 0) always, so parking there is a
## guaranteed contact.
func test_hazard_contact_knocks_back_one_station() -> void:
	var game := _game([0, 1] as Array[int])
	var team_index := 0
	game.hazard_stations = [
		{"type": RelaySprint.Hazard.SPINNER, "x": 7.0, "phase": 0.0, "gap": 0.0}
	]
	game.progress[team_index] = 7.0
	game.lateral[team_index] = 0.0
	var runner: int = game.teams[team_index][0]
	game.handle_input(runner, {"mx": 0.0, "my": 0.0})
	game.tick(TICK)
	assert_almost_eq(
		float(game.progress[team_index]), 7.0 - RelaySprint.HIT_KNOCKBACK, 0.001, "one gap back"
	)
	assert_eq(game.lateral[team_index], 0.0, "recentred in the lane")


## #1068: every round seeds one of each hazard type (plus a random fourth) —
## variety is guaranteed, and the same seed reproduces the same gauntlet.
func test_stations_are_seeded_with_all_three_types() -> void:
	var game := _game([0, 1] as Array[int])
	assert_eq(game.hazard_stations.size(), RelaySprint.STATION_XS.size())
	var types := {}
	for station: Dictionary in game.hazard_stations:
		types[int(station.type)] = true
	assert_eq(types.size(), 3, "sweeper, spinner and gate all present")
	var again := _game([0, 1] as Array[int])
	for i in game.hazard_stations.size():
		assert_eq(game.hazard_stations[i], again.hazard_stations[i], "same seed = same gauntlet")


## #1068: the spinner replicates as a pivot plus two tips orbiting SPINNER_ARM
## away, opposite each other — the dot form every consumer already reads.
func test_spinner_dots_orbit_the_pivot() -> void:
	var game := _game([0, 1] as Array[int])
	game.hazard_stations = [
		{"type": RelaySprint.Hazard.SPINNER, "x": 9.0, "phase": 0.0, "gap": 0.0}
	]
	var dots: Array = game.hazard_dots(1.234)
	assert_eq(dots.size(), 3, "pivot + two tips")
	var pivot := Vector2(float(dots[0][0]), float(dots[0][1]))
	assert_eq(pivot, Vector2(9.0, 0.0))
	for tip_index in [1, 2]:
		var tip := Vector2(float(dots[tip_index][0]), float(dots[tip_index][1]))
		assert_almost_eq(tip.distance_to(pivot), RelaySprint.SPINNER_ARM, 0.001, "on the arm")
	var t1 := Vector2(float(dots[1][0]), float(dots[1][1]))
	var t2 := Vector2(float(dots[2][0]), float(dots[2][1]))
	assert_almost_eq(((t1 + t2) / 2.0).distance_to(pivot), 0.0, 0.001, "tips oppose")


## #1068: a gate's wall dots cover the lane on both sides of the gap and
## leave the gap itself clear — a weave, not a wall.
func test_gate_dots_flank_a_clear_gap() -> void:
	var game := _game([0, 1] as Array[int])
	game.hazard_stations = [{"type": RelaySprint.Hazard.GATE, "x": 11.0, "phase": 0.0, "gap": 0.6}]
	var dots: Array = game.hazard_dots(0.0)
	assert_gt(dots.size(), 1, "walls on both sides")
	var above := false
	var below := false
	for dot: Array in dots:
		assert_eq(float(dot[0]), 11.0, "gate dots are static at the station")
		var lat := float(dot[1])
		assert_gt(absf(lat - 0.6), RelaySprint.GATE_GAP_HALF - 0.45, "no dot blocks the gap mouth")
		if lat > 0.6:
			above = true
		else:
			below = true
	assert_true(above and below, "both sides of the gap are walled")


func test_finishing_a_leg_tags_the_partner() -> void:
	var game := _game([0, 1, 2, 3] as Array[int])
	game.progress[0] = RelaySprint.TRACK_LEN - 0.01
	game.lateral[0] = RelaySprint.LANE_HALF
	var runner: int = game.teams[0][0]
	game.handle_input(runner, {"mx": 1.0, "my": 0.0})
	game.tick(TICK)
	assert_eq(int(game.active_leg[0]), 1, "second runner takes over")
	assert_eq(game.progress[0], 0.0, "next leg starts from the line")


func test_first_team_home_wins_three_team_placements() -> void:
	var game := _game()
	_sprint_team(game, 2, 2)
	_sprint_team(game, 0, 2)
	_sprint_team(game, 1, 2)
	assert_true(game.finished)
	var placements: Array = game.get_results().placements
	assert_eq(placements.size(), 3)
	assert_eq(placements[0], game.teams[2])
	assert_eq(placements[1], game.teams[0])
	assert_eq(placements[2], game.teams[1])
	assert_true(game.get_results().team_mode)


func test_timeout_ranks_unfinished_by_total_progress() -> void:
	var game := _game([0, 1, 2, 3] as Array[int])
	game.active_leg[0] = 1
	game.progress[0] = 2.0
	game.progress[1] = 5.0
	game.duration_override = game.elapsed + TICK
	var idle_runner: int = game.teams[0][1]
	game.handle_input(idle_runner, {"mx": 0.0, "my": 0.0})
	game.tick(TICK)
	assert_true(game.finished)
	var placements: Array = game.get_results().placements
	assert_eq(placements[0], game.teams[0], "a full leg beats raw distance")
	assert_eq(placements[1], game.teams[1])


func test_snapshot_shape() -> void:
	var game := _game()
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.lanes.size(), 3)
	assert_eq(snapshot.lanes[0].size(), RelaySprint.LN_COUNT)
	assert_eq(snapshot.track_len, RelaySprint.TRACK_LEN)
	assert_gte(
		snapshot.hazards.size(), RelaySprint.STATION_XS.size(), "at least one dot per station"
	)
	for hazard: Array in snapshot.hazards:
		assert_eq(hazard.size(), 2, "every hazard dot is [x, lateral]")


## M15: the timeout-ranks-by-progress path must generalize past the original
## three-team case — every one of the six lanes at twelve players is ordered
## by total distance covered, not just the first few.
func test_timeout_ranking_generalizes_to_six_teams() -> void:
	var player_slots: Array[int] = []
	for slot in 12:
		player_slots.append(slot)
	var game := _game(player_slots)
	# Team i gets progress proportional to i, so team 5 leads and team 0 trails.
	for team_index in game.teams.size():
		game.progress[team_index] = float(team_index) * 2.0
	game.duration_override = game.elapsed + TICK
	for team_index in game.teams.size():
		var runner: int = game.teams[team_index][0]
		game.handle_input(runner, {"mx": 0.0, "my": 0.0})
	game.tick(TICK)
	assert_true(game.finished)
	var placements: Array = game.get_results().placements
	assert_eq(placements.size(), 6, "every team ranked, none dropped")
	for i in placements.size():
		assert_eq(placements[i], game.teams[5 - i], "ordered furthest-first")
	assert_true(game.get_results().team_mode)


func test_snapshot_shape_at_twelve_players() -> void:
	var player_slots: Array[int] = []
	for slot in 12:
		player_slots.append(slot)
	var game := _game(player_slots)
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.lanes.size(), 6, "six lanes for six teams")
	assert_eq(
		snapshot.lanes[0].size(), RelaySprint.LN_COUNT, "same per-lane shape as at six players"
	)
