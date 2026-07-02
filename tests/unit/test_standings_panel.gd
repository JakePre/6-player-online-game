extends GutTest
## StandingsPanel (M3-05): shared leaderboard/podium display with the
## bottom-up dramatic reveal (SPEC $4).

var panel: StandingsPanel


func before_each() -> void:
	var scene: PackedScene = load("res://src/match/standings_panel.tscn")
	panel = scene.instantiate()
	add_child_autofree(panel)


func _three_lines() -> Array[String]:
	var lines: Array[String] = ["1st  Alice  30", "2nd  Bob  20", "3rd  Cleo  10"]
	return lines


func test_instant_mode_shows_everything_at_once() -> void:
	panel.show_lines("Leaderboard", "", _three_lines(), false)
	assert_eq(panel.revealed_count(), 3)
	assert_eq(panel.get_node("%StandingsTitle").text, "Leaderboard")
	assert_false(panel.get_node("%StandingsSubtitle").visible, "empty subtitle stays hidden")


func test_reveal_runs_bottom_up() -> void:
	panel.reveal_interval = 0.15
	panel.show_lines("Final standings", "Alice wins the match!", _three_lines(), true)
	assert_eq(panel.revealed_count(), 0, "nothing shows before the tween starts")
	await wait_frames(2)
	var list: VBoxContainer = panel.get_node("%StandingsList")
	assert_true((list.get_child(2) as Label).visible, "last place reveals first")
	assert_false((list.get_child(0) as Label).visible, "winner stays hidden longest")
	await wait_seconds(1.0)
	assert_eq(panel.revealed_count(), 3)
	assert_true(panel.get_node("%StandingsSubtitle").visible)


func test_new_show_replaces_previous_rows() -> void:
	panel.show_lines("Leaderboard", "", _three_lines(), false)
	var short_lines: Array[String] = ["1st  Bob  99"]
	panel.show_lines("Leaderboard", "", short_lines, false)
	var list: VBoxContainer = panel.get_node("%StandingsList")
	var live_rows := 0
	for child in list.get_children():
		if not child.is_queued_for_deletion():
			live_rows += 1
	assert_eq(live_rows, 1)
