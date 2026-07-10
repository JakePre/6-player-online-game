extends GutTest
## Final ranking rules (SPEC $6): Gauntlet elimination order first, ties
## broken by leftover coins, then total coins earned; exact ties stay tied.


func test_elimination_order_is_untouched_without_ties() -> void:
	var placements := FinaleRanking.rank([[3], [1], [2]], {}, {})
	assert_eq(placements, [[3], [1], [2]])


func test_tie_broken_by_leftover_coins() -> void:
	var placements := FinaleRanking.rank([[1, 2], [3]], {1: 10, 2: 40}, {})
	assert_eq(placements, [[2], [1], [3]])


func test_leftover_tie_falls_back_to_coins_earned() -> void:
	var placements := FinaleRanking.rank([[1, 2]], {1: 20, 2: 20}, {1: 90, 2: 120})
	assert_eq(placements, [[2], [1]])


func test_exact_ties_stay_grouped() -> void:
	var placements := FinaleRanking.rank([[1, 2, 3]], {1: 20, 2: 20, 3: 5}, {1: 90, 2: 90})
	assert_eq(placements, [[1, 2], [3]])


func test_tiebreaks_never_cross_gauntlet_groups() -> void:
	# Slot 3 was eliminated earlier: richer or not, it stays behind.
	var placements := FinaleRanking.rank([[1], [3]], {1: 0, 3: 500}, {1: 0, 3: 500})
	assert_eq(placements, [[1], [3]])


func test_missing_coin_entries_count_as_zero() -> void:
	var placements := FinaleRanking.rank([[1, 2]], {2: 1}, {})
	assert_eq(placements, [[2], [1]])


func test_winner_of_the_gauntlet_wins_the_match() -> void:
	# SPEC $6: a poorer survivor still beats a richer earlier casualty.
	var placements := FinaleRanking.rank(
		[[4], [0, 5], [2]], {4: 0, 0: 60, 5: 60, 2: 999}, {4: 3, 0: 200, 5: 150, 2: 999}
	)
	assert_eq(placements, [[4], [0], [5], [2]])


func test_standings_rows_share_placement_numbers_on_ties() -> void:
	var rows := FinaleRanking.standings([[1, 2], [3]], {}, {})
	assert_eq(
		rows,
		[
			{"slot": 1, "placement": 1},
			{"slot": 2, "placement": 1},
			{"slot": 3, "placement": 3},
		]
	)


func test_standings_after_tiebreak() -> void:
	var rows := FinaleRanking.standings([[1, 2]], {1: 10, 2: 40}, {})
	assert_eq(rows, [{"slot": 2, "placement": 1}, {"slot": 1, "placement": 2}])


func test_gauntlet_results_feed_ranking_end_to_end() -> void:
	# Full pipeline: shop -> gauntlet -> ranking.
	var shop := FinaleShop.new({0: 150, 1: 150, 2: 40})
	shop.buy(0, &"extra_life")
	shop.buy(1, &"shield")
	shop.buy(1, &"speed_boost")
	var game := Gauntlet.new()
	game.meta = Gauntlet.make_meta()
	game.setup([0, 1, 2] as Array[int], 7)
	game.apply_loadouts(shop.loadouts())
	game._invuln_left.clear()  # past the opening spawn-protection window (#787)
	# 2 falls, then 1 falls twice (shield first, then its life); 0 survives.
	game.positions[2] = Vector2(game.radius + 1.0, 0.0)
	game._hazard_accum = -INF
	game.tick(1.0 / 30.0)
	for _i in 3:
		game.positions[1] = Vector2(game.radius + 1.0, 0.0)
		game._hazard_accum = -INF
		game.tick(1.0 / 30.0)
	assert_true(game.finished)
	var final := FinaleRanking.rank(
		game.get_results().placements,
		{0: shop.coins_left(0), 1: shop.coins_left(1), 2: shop.coins_left(2)},
		{0: 150, 1: 150, 2: 40}
	)
	assert_eq(final, [[0], [1], [2]])
