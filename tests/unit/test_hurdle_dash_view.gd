extends GutTest
## Hurdle Dash client view (M4-07): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/hurdle_dash/hurdle_dash_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"hurdle_dash"),
		"res://src/minigames/hurdle_dash/hurdle_dash_view.tscn"
	)


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"players": {0: [5.0, 1, 0.0, false]},
				"hurdles": [5.0, 12.0],
				"course_len": 40.0,
			}
		)
	)
	assert_eq(view.players.size(), 1)
	assert_eq(view.hurdles, [5.0, 12.0])
	view.render({"players": {}, "hurdles": [], "course_len": 40.0})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.hurdles, [])


func test_iso_view_builds_finish_line_and_poses_runners() -> void:
	view.render(
		{
			"players": {0: [5.0, 1, 0.0, false], 1: [0.0, 0, 0.0, true]},
			"hurdles": [7.0],
			"course_len": 40.0
		}
	)
	assert_not_null(view.arena.get_node("FinishLine"))
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.y, 1.0, 0.001, "airborne runners lift")
	assert_eq(rig.current_action(), &"jump_idle")
	assert_eq(view.rig_for_slot(1).current_action(), &"cheer", "finishers celebrate")
