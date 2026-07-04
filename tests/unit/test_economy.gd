extends GutTest
## Coin economy rules (SPEC $5): placement tables, ties, team awards, and the
## per-round pickup cap.


func test_six_player_placement_awards() -> void:
	var placements := [[0], [1], [2], [3], [4], [5]]
	assert_eq(Economy.award_for_placements(placements), {0: 30, 1: 20, 2: 15, 3: 10, 4: 5, 5: 3})


## M15-03: past the SPEC $5 table the award tapers by 1 to a 1-coin floor, so a
## large field still ranks fairly (here 8 players).
func test_placement_awards_taper_past_six() -> void:
	var placements := [[0], [1], [2], [3], [4], [5], [6], [7]]
	assert_eq(
		Economy.award_for_placements(placements),
		{0: 30, 1: 20, 2: 15, 3: 10, 4: 5, 5: 3, 6: 2, 7: 1}
	)


## Across a full 24-player field the placement award never rises for a worse
## rank, and bottoms out at the floor.
func test_placement_awards_monotonic_to_24() -> void:
	var previous := 999
	for rank in 24:
		var value := Economy.placement_award(rank)
		assert_true(
			value <= previous, "rank %d award %d must not exceed the better rank" % [rank, value]
		)
		assert_true(value >= Economy.PLACEMENT_FLOOR, "rank %d award below floor" % rank)
		previous = value
	assert_eq(Economy.placement_award(23), Economy.PLACEMENT_FLOOR, "the tail sits at the floor")


func test_fewer_players_use_top_of_table() -> void:
	var placements := [[4], [1], [2]]
	assert_eq(Economy.award_for_placements(placements), {4: 30, 1: 20, 2: 15})


func test_ties_share_higher_award_and_consume_ranks() -> void:
	# Two tied for 1st both take 30; the next player is ranked 3rd (15).
	var placements := [[0, 1], [2], [3]]
	assert_eq(Economy.award_for_placements(placements), {0: 30, 1: 30, 2: 15, 3: 10})


func test_all_tied() -> void:
	assert_eq(Economy.award_for_placements([[0, 1, 2]]), {0: 30, 1: 30, 2: 30})


func test_two_team_awards() -> void:
	var awards := Economy.award_for_teams([[0, 1, 2], [3, 4, 5]])
	assert_eq(awards, {0: 20, 1: 20, 2: 20, 3: 5, 4: 5, 5: 5})


func test_three_team_awards() -> void:
	var awards := Economy.award_for_teams([[0, 1], [2, 3], [4, 5]])
	assert_eq(awards, {0: 25, 1: 25, 2: 15, 3: 15, 4: 5, 5: 5})


## M15-03: 4+ teams (large lobbies) taper linearly from the three-team top (25)
## to the loser floor (5).
func test_four_team_awards_taper_to_floor() -> void:
	var awards := Economy.award_for_teams([[0], [1], [2], [3]])
	assert_eq(awards, {0: 25, 1: 18, 2: 12, 3: 5})


## Many teams stay monotonic non-increasing and finish at the loser floor.
func test_many_team_awards_monotonic() -> void:
	var previous := 999
	var teams := 6
	for place in teams:
		var value := Economy.team_award(place, teams)
		assert_true(value <= previous, "team place %d must not out-earn a better team" % place)
		previous = value
	assert_eq(Economy.team_award(teams - 1, teams), 5, "last team gets the loser floor")


func test_pickup_coins_added_to_placement() -> void:
	var totals := Economy.total_round_award([[0], [1]], {0: 4, 1: 7})
	assert_eq(totals, {0: 34, 1: 27})


func test_pickup_coins_capped() -> void:
	var totals := Economy.total_round_award([[0], [1]], {0: 99})
	assert_eq(totals[0], 30 + Economy.PICKUP_CAP)
	assert_eq(totals[1], 20)


func test_pickup_coins_for_slot_without_placement() -> void:
	# Defensive: a pickup entry for a slot missing from placements still counts.
	var totals := Economy.total_round_award([[0]], {7: 5})
	assert_eq(totals, {0: 30, 7: 5})


func test_team_total_combines_team_awards_and_capped_pickups() -> void:
	var totals := Economy.total_team_round_award([[0, 1], [2, 3]], {0: 12, 2: 99})
	assert_eq(totals, {0: 32, 1: 20, 2: 35, 3: 5})


func test_three_team_total() -> void:
	var totals := Economy.total_team_round_award([[0, 1], [2, 3], [4, 5]], {})
	assert_eq(totals, {0: 25, 1: 25, 2: 15, 3: 15, 4: 5, 5: 5})
