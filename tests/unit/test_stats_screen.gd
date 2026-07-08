extends GutTest
## Local stats & match history screen (M20-03, #712): renders StatsStore's
## totals, favorites, and recent-match list, and falls back gracefully when
## nothing has been recorded yet.

var screen: Control


func before_each() -> void:
	# A clean slate so a leftover file from another test/run never leaks in —
	# _ready() reads the real StatsStore.PATH.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(StatsStore.PATH))
	var scene: PackedScene = load("res://src/client/screens/stats_screen.tscn")
	screen = scene.instantiate()
	add_child_autofree(screen)


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(StatsStore.PATH))


func _favorite_lines() -> Array:
	return screen.get_node("%FavoritesList").get_children()


func _recent_lines() -> Array:
	return screen.get_node("%RecentList").get_children()


func test_ready_populates_from_the_stored_file() -> void:
	assert_eq(screen.get_node("%SummaryLabel").text, "0 matches played  ·  0 wins  ·  0 podiums")
	assert_eq(_favorite_lines().size(), 1, "the no-favorites fallback line")


func test_populate_renders_summary_line() -> void:
	var stats := StatsStore.defaults()
	stats.matches = 5
	stats.wins = 2
	stats.podiums = 3
	screen.populate(stats)
	assert_eq(screen.get_node("%SummaryLabel").text, "5 matches played  ·  2 wins  ·  3 podiums")


func test_populate_sorts_favorites_by_most_played() -> void:
	var stats := StatsStore.defaults()
	stats.games = {
		"snake_chain": {"plays": 2, "wins": 0},
		"coin_scramble": {"plays": 5, "wins": 3},
	}
	screen.populate(stats)
	var lines := _favorite_lines()
	assert_eq(lines.size(), 2)
	assert_string_contains(lines[0].text, "Coin Scramble")
	assert_string_contains(lines[0].text, "5 plays")
	assert_string_contains(lines[0].text, "3 wins")
	assert_string_contains(lines[1].text, "Snake Chain")


func test_populate_falls_back_for_an_unknown_game_id() -> void:
	var stats := StatsStore.defaults()
	stats.games = {"retired_game": {"plays": 1, "wins": 0}}
	screen.populate(stats)
	assert_string_contains(_favorite_lines()[0].text, "Retired Game")


func test_populate_renders_recent_matches_newest_first() -> void:
	var stats := StatsStore.defaults()
	stats.recent = [
		{
			"date": 1720400000,
			"placement": 1,
			"player_count": 6,
			"standout_game": "coin_scramble",
			"standout_placement": 1,
		}
	]
	screen.populate(stats)
	var lines := _recent_lines()
	assert_eq(lines.size(), 1)
	assert_string_contains(lines[0].text, "1st of 6")
	assert_string_contains(lines[0].text, "Coin Scramble")


func test_populate_omits_standout_when_no_round_was_recorded() -> void:
	var stats := StatsStore.defaults()
	stats.recent = [{"date": 1720400000, "placement": 3, "player_count": 4}]
	stats.recent[0]["standout_game"] = ""
	stats.recent[0]["standout_placement"] = 0
	screen.populate(stats)
	assert_false(_recent_lines()[0].text.contains("Best:"))


func test_populate_empty_recent_shows_fallback_line() -> void:
	screen.populate(StatsStore.defaults())
	assert_eq(_recent_lines().size(), 1)
	assert_string_contains(_recent_lines()[0].text, "No matches recorded")


func test_ordinal_formatting() -> void:
	assert_eq(screen._ordinal(1), "1st")
	assert_eq(screen._ordinal(2), "2nd")
	assert_eq(screen._ordinal(3), "3rd")
	assert_eq(screen._ordinal(4), "4th")
	assert_eq(screen._ordinal(11), "11th", "the teens exception")
	assert_eq(screen._ordinal(12), "12th")
	assert_eq(screen._ordinal(13), "13th")
	assert_eq(screen._ordinal(21), "21st")


func test_back_button_navigates_to_main_menu() -> void:
	watch_signals(screen)
	screen.get_node("%BackButton").pressed.emit()
	assert_signal_emitted_with_parameters(screen, "navigate", [&"main_menu"])
