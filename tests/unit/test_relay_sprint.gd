extends GutTest
## Relay Sprint (SPEC $7 #12): leg handoffs, hazard knockback, finish order,
## the three-team award path at six players, and the FFA sprint fallback.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2, 3, 4, 5]) -> RelaySprint:
	var game := RelaySprint.new()
	game.meta = RelaySprint.make_meta()
	game.setup(player_slots, 42)
	return game


## Runs `team_index`'s active runner straight down a hazard-free line by
## steering around sweepers — for tests we bypass dodging by teleporting
## progress just past each hazard when adjacent to it.
func _sprint_team(game: RelaySprint, team_index: int, legs: int) -> void:
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
			for i in RelaySprint.HAZARD_POSITIONS.size():
				var hazard: float = RelaySprint.HAZARD_POSITIONS[i]
				var progress := float(game.progress[team_index])
				if absf(progress - hazard) <= RelaySprint.HAZARD_RADIUS + 0.3:
					game.progress[team_index] = hazard + RelaySprint.HAZARD_RADIUS + 0.31
			if int(game.active_leg[team_index]) > before:
				break


func test_meta() -> void:
	var meta := RelaySprint.make_meta()
	assert_eq(meta.id, &"relay_sprint")
	assert_eq(meta.category, MinigameMeta.Category.TEAM)


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


func test_two_teams_at_four_players() -> void:
	var game := _game([0, 1, 2, 3] as Array[int])
	assert_true(game.team_mode)
	assert_eq(game.teams.size(), 2)


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


func test_hazard_contact_resets_the_leg() -> void:
	var game := _game([0, 1] as Array[int])
	var team_index := 0
	game.progress[team_index] = RelaySprint.HAZARD_POSITIONS[0]
	game.lateral[team_index] = game.hazard_lateral(0, game.elapsed + TICK)
	var runner: int = game.teams[team_index][0]
	game.handle_input(runner, {"mx": 0.0, "my": 0.0})
	game.tick(TICK)
	assert_eq(game.progress[team_index], 0.0)


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
	assert_eq(snapshot.lanes[0].size(), 5)
	assert_eq(snapshot.track_len, RelaySprint.TRACK_LEN)
	assert_eq(snapshot.hazards.size(), RelaySprint.HAZARD_POSITIONS.size())
