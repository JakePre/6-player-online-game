extends GutTest
## Coin economy rules (SPEC $5): placement tables, ties, team awards, and the
## per-round pickup cap.


func test_six_player_placement_awards() -> void:
	var placements := [[0], [1], [2], [3], [4], [5]]
	assert_eq(Economy.award_for_placements(placements), {0: 30, 1: 20, 2: 15, 3: 10, 4: 5, 5: 3})


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
