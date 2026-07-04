extends GutTest
## Text formatting for the match chrome (M3-04): ordinals, timers, and
## tie-aware result/standings lines.

const NAMES := {0: "Alice", 1: "Bob", 2: "Cleo"}


func test_ordinals() -> void:
	assert_eq(MatchFormat.ordinal(1), "1st")
	assert_eq(MatchFormat.ordinal(2), "2nd")
	assert_eq(MatchFormat.ordinal(3), "3rd")
	assert_eq(MatchFormat.ordinal(6), "6th")
	assert_eq(MatchFormat.ordinal(7), "7th", "past the table falls back to Nth")


func test_category_names() -> void:
	assert_eq(MatchFormat.category_name(MinigameMeta.Category.FFA), "Free-for-all")
	assert_eq(MatchFormat.category_name(MinigameMeta.Category.SABOTAGE), "Sabotage")
	assert_eq(MatchFormat.category_name(99), "?")


func test_clock_rounds_up_and_clamps() -> void:
	assert_eq(MatchFormat.clock(42.4), "0:43")
	assert_eq(MatchFormat.clock(60.0), "1:00")
	assert_eq(MatchFormat.clock(-1.0), "0:00")


## M15-02 (ADR 003 F2): every name carries its always-on P-number; nameless
## slots read as just the number. The number never wraps, unlike the colour.
func test_player_name_carries_the_player_number() -> void:
	assert_eq(MatchFormat.player_name(NAMES, 1), "P2 Bob")
	assert_eq(MatchFormat.player_name(NAMES, 5), "P6", "nameless slots are just their number")
	assert_eq(MatchFormat.player_name(NAMES, 23), "P24", "numbers stay unique past the palette")


func test_result_lines_ties_share_rank_and_skip_past() -> void:
	var lines := MatchFormat.result_lines([[1, 2], [0]], {1: 30, 2: 30, 0: 15}, NAMES)
	assert_eq(lines, ["1st  P2 Bob  +30", "1st  P3 Cleo  +30", "3rd  P1 Alice  +15"])


func test_standings_lines_sorted_with_shared_ranks() -> void:
	var lines := MatchFormat.standings_lines({0: 20, 1: 45, 2: 20}, NAMES)
	assert_eq(lines, ["1st  P2 Bob  45", "2nd  P1 Alice  20", "2nd  P3 Cleo  20"])


func test_series_lines_rank_and_tie() -> void:
	var rows := [
		{"slot": 1, "points": 17, "coins": 120},
		{"slot": 0, "points": 17, "coins": 120},
		{"slot": 2, "points": 9, "coins": 40},
	]
	var lines := MatchFormat.series_lines(rows, {0: "Alice", 1: "Bob", 2: "Cid"})
	assert_eq(lines[0], "1st  P2 Bob — 17 pts")
	assert_eq(lines[1], "1st  P1 Alice — 17 pts", "identical points+coins share the rank")
	assert_eq(lines[2], "3rd  P3 Cid — 9 pts")
