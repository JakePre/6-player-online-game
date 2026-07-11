extends GutTest
## Hold-Tab match-log overlay (#814): a pure renderer of a ranked roster + a
## scrolling event feed. match_screen owns the data; this just lays it out.

var overlay: MatchLogOverlay


func before_each() -> void:
	overlay = MatchLogOverlay.new()
	add_child_autofree(overlay)


func _labels(list: VBoxContainer) -> Array[String]:
	var out: Array[String] = []
	for child in list.get_children():
		if child is Label:
			out.append((child as Label).text)
	return out


func test_starts_hidden() -> void:
	assert_false(overlay.is_open(), "closed until opened")


func test_open_fills_the_roster_and_feed() -> void:
	overlay.open_with(
		["P1 Alice — 5", "P2 Bob — 2"], ["▶ Match started", "Round 1 — Coin Scramble", "   🥇 Alice"]
	)
	assert_true(overlay.is_open())
	assert_eq(_labels(overlay._standings_list), ["P1 Alice — 5", "P2 Bob — 2"], "roster ranked")
	var feed := _labels(overlay._feed_list)
	assert_eq(feed.size(), 3, "one label per feed line")
	assert_eq(feed[-1], "   🥇 Alice", "newest event is last (bottom of the scroll)")


func test_reopening_replaces_the_previous_contents() -> void:
	overlay.open_with(["P1 Alice — 1"], ["Round 1 — Coin Scramble"])
	overlay.open_with(["P1 Bob — 3", "P2 Alice — 1"], ["Round 1 — Coin Scramble", "   🥇 Bob"])
	assert_eq(_labels(overlay._standings_list).size(), 2, "stale roster rows cleared")
	assert_eq(_labels(overlay._feed_list)[-1], "   🥇 Bob")


func test_empty_state_shows_placeholders_not_blank() -> void:
	overlay.open_with([], [])
	assert_eq(_labels(overlay._standings_list).size(), 1, "a 'no scores yet' placeholder")
	assert_eq(_labels(overlay._feed_list).size(), 1, "a 'getting started' placeholder")


func test_close_hides_it() -> void:
	overlay.open_with(["P1 Alice — 1"], ["Round 1"])
	overlay.close()
	assert_false(overlay.is_open())
