extends GutTest


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(StatsStore.PATH))


func test_defaults_when_no_file() -> void:
	assert_eq(StatsStore.load_stats(), StatsStore.DEFAULTS)


func test_defaults_returns_a_fresh_independent_copy() -> void:
	var a := StatsStore.defaults()
	a.games["coin_scramble"] = {"plays": 1, "wins": 1}
	assert_false(StatsStore.DEFAULTS.games.has("coin_scramble"), "deep copy, no shared state")


func test_sanitize_drops_unknown_keys_and_clamps_negatives() -> void:
	var clean := StatsStore.sanitize({"matches": -5, "wins": 3, "hax": true})
	assert_eq(clean.matches, 0, "negative clamps to 0")
	assert_eq(clean.wins, 3)
	assert_false(clean.has("hax"))


func test_sanitize_keeps_only_well_shaped_game_entries() -> void:
	var clean := (
		StatsStore
		. sanitize(
			{
				"games":
				{
					"coin_scramble": {"plays": 4, "wins": 2},
					"junk": "not a dict",
					"snake_chain": {"plays": -1, "wins": -1},
				}
			}
		)
	)
	assert_eq(clean.games.coin_scramble, {"plays": 4, "wins": 2})
	assert_false(clean.games.has("junk"))
	assert_eq(clean.games.snake_chain, {"plays": 0, "wins": 0}, "negatives clamp to 0")


func test_sanitize_keeps_only_well_shaped_recent_entries_and_caps_at_ten() -> void:
	var recent: Array = []
	for i in 15:
		recent.append({"date": 1000 + i, "placement": 1})
	recent.append("garbage")
	recent.append({"date": 1})  # missing placement
	var clean := StatsStore.sanitize({"recent": recent})
	assert_eq(clean.recent.size(), StatsStore.MAX_RECENT)


func test_save_load_round_trip() -> void:
	var stats := StatsStore.defaults()
	stats.matches = 3
	stats.wins = 1
	stats.podiums = 2
	stats.games = {"coin_scramble": {"plays": 3, "wins": 1}}
	stats.recent = [
		{
			"date": 1720000000,
			"placement": 1,
			"player_count": 6,
			"standout_game": "coin_scramble",
			"standout_placement": 1,
		}
	]
	StatsStore.save_stats(stats)
	assert_eq(StatsStore.load_stats(), stats)


func test_load_recovers_to_defaults_from_a_corrupt_file() -> void:
	var file := FileAccess.open(StatsStore.PATH, FileAccess.WRITE)
	file.store_string("{not valid json")
	file.close()
	assert_eq(StatsStore.load_stats(), StatsStore.DEFAULTS)


func test_load_recovers_to_defaults_from_a_non_dict_json_file() -> void:
	var file := FileAccess.open(StatsStore.PATH, FileAccess.WRITE)
	file.store_string("[1, 2, 3]")
	file.close()
	assert_eq(StatsStore.load_stats(), StatsStore.DEFAULTS)


func test_record_match_increments_totals_on_a_win() -> void:
	var stats := StatsStore.record_match(
		StatsStore.defaults(), {"date": 100, "placement": 1, "player_count": 4, "rounds": []}
	)
	assert_eq(stats.matches, 1)
	assert_eq(stats.wins, 1)
	assert_eq(stats.podiums, 1, "1st place counts as a podium too")


func test_record_match_counts_podium_without_a_win_at_2nd_and_3rd() -> void:
	var second := StatsStore.record_match(
		StatsStore.defaults(), {"date": 100, "placement": 2, "player_count": 4, "rounds": []}
	)
	assert_eq(second.wins, 0)
	assert_eq(second.podiums, 1)
	var fourth := StatsStore.record_match(
		StatsStore.defaults(), {"date": 100, "placement": 4, "player_count": 4, "rounds": []}
	)
	assert_eq(fourth.podiums, 0, "4th is not a podium")


func test_record_match_tracks_per_game_plays_and_wins() -> void:
	var rounds := [
		{"game_id": "coin_scramble", "placement": 1},
		{"game_id": "coin_scramble", "placement": 2},
		{"game_id": "snake_chain", "placement": 3},
	]
	var stats := StatsStore.record_match(
		StatsStore.defaults(), {"date": 100, "placement": 2, "player_count": 4, "rounds": rounds}
	)
	assert_eq(stats.games.coin_scramble, {"plays": 2, "wins": 1})
	assert_eq(stats.games.snake_chain, {"plays": 1, "wins": 0})


func test_record_match_picks_the_best_round_as_standout() -> void:
	var rounds := [
		{"game_id": "coin_scramble", "placement": 3},
		{"game_id": "snake_chain", "placement": 1},
		{"game_id": "hot_potato", "placement": 2},
	]
	var stats := StatsStore.record_match(
		StatsStore.defaults(), {"date": 100, "placement": 1, "player_count": 6, "rounds": rounds}
	)
	assert_eq(stats.recent[0].standout_game, "snake_chain")
	assert_eq(stats.recent[0].standout_placement, 1)


func test_record_match_with_no_rounds_has_an_empty_standout() -> void:
	var stats := StatsStore.record_match(
		StatsStore.defaults(), {"date": 100, "placement": 1, "player_count": 2, "rounds": []}
	)
	assert_eq(stats.recent[0].standout_game, "")
	assert_eq(stats.recent[0].standout_placement, 0)


func test_record_match_prepends_to_recent_and_rotates_past_ten() -> void:
	var stats := StatsStore.defaults()
	for i in 12:
		stats = StatsStore.record_match(
			stats, {"date": 100 + i, "placement": 1, "player_count": 2, "rounds": []}
		)
	assert_eq(stats.recent.size(), StatsStore.MAX_RECENT)
	assert_eq(stats.recent[0].date, 111, "newest first")
	assert_eq(stats.matches, 12, "totals keep counting past the recent-10 cap")


func test_record_match_is_pure_and_does_not_mutate_the_input() -> void:
	var original := StatsStore.defaults()
	var before := original.duplicate(true)
	StatsStore.record_match(original, {"date": 1, "placement": 1, "player_count": 2, "rounds": []})
	assert_eq(original, before, "record_match returns a new dict, the input is untouched")
