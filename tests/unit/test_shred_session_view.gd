extends GutTest
## Shred Session client view (M14-04): renders the lane highway, falling notes,
## and scoreboard from replicated snapshots without simulating anything.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/shred_session/shred_session_view.tscn")

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


## players entry: [score, streak, last_judgment, last_lane, event_count]
func _snap(notes: Array, players: Dictionary, elapsed := 0.0) -> Dictionary:
	return {
		"elapsed": elapsed,
		"lanes": ShredSession.LANES,
		"song_end": 62.0,
		"notes": notes,
		"players": players,
	}


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"shred_session"),
		"res://src/minigames/shred_session/shred_session_view.tscn"
	)


func test_setup_builds_four_lanes_and_a_hit_line() -> void:
	for lane in ShredSession.LANES:
		assert_not_null(view.arena.get_node("Lane%d" % lane), "lane %d exists" % lane)
	assert_not_null(view.arena.get_node("HitLine"))


func test_notes_spawn_and_clear_with_the_snapshot() -> void:
	view.render(_snap([[3.0, 0], [3.5, 2]], {0: [0, 0, 0, -1, 0]}))
	assert_eq(view._note_nodes.size(), 2, "a node per advertised note")
	# The 3.0 note passes; only the later one remains.
	view.render(_snap([[3.5, 2]], {0: [0, 0, 0, -1, 0]}))
	assert_eq(view._note_nodes.size(), 1, "notes that leave the snapshot are dropped")


func test_note_sits_at_the_hit_line_when_the_clock_reaches_it() -> void:
	view.render(_snap([[4.0, 1]], {0: [0, 0, 0, -1, 0]}, 4.0))
	var entry: Dictionary = view._note_nodes.values()[0]
	assert_almost_eq(
		(entry.node as MeshInstance3D).position.z, view.HIT_Z, 0.01, "dt=0 places it on the line"
	)


func test_note_is_up_track_before_its_time() -> void:
	view.render(_snap([[6.0, 1]], {0: [0, 0, 0, -1, 0]}, 4.0))
	var entry: Dictionary = view._note_nodes.values()[0]
	assert_lt(
		(entry.node as MeshInstance3D).position.z, view.HIT_Z, "a future note is short of the line"
	)


func test_scoreboard_reflects_scores() -> void:
	view.render(_snap([], {0: [40, 3, 1, 1, 5], 1: [90, 0, 3, 2, 4]}))
	assert_string_contains((view._score_rows[1] as Label).text, "90")
	assert_string_contains((view._score_rows[0] as Label).text, "40")


func test_local_verdict_flashes_on_a_fresh_event() -> void:
	var label: Label = view.get_node("JudgmentLabel")
	view.render(_snap([], {0: [0, 0, 0, -1, 0]}))
	assert_false(label.visible, "no verdict yet")
	# Local player's event counter ticks with a PERFECT.
	view.render(_snap([], {0: [2, 1, ShredSession.Judgment.PERFECT, 1, 1]}))
	assert_true(label.visible, "the verdict flashes")
	assert_string_contains(label.text, "PERFECT")


func test_streak_banner_shows_once_the_multiplier_is_live() -> void:
	var streak: Label = view.get_node("StreakLabel")
	view.render(_snap([], {0: [16, ShredSession.STREAK_X2, 1, 0, 3]}))
	assert_true(streak.visible)
	assert_string_contains(streak.text, "×2")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view._note_nodes.size(), 0)
