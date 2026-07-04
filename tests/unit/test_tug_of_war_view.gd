extends GutTest
## Tug of War client view (M8-09): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/tug_of_war/tug_of_war_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"tug_of_war"),
		"res://src/minigames/tug_of_war/tug_of_war_view.tscn"
	)


func test_setup_builds_rope_marker_and_win_lines() -> void:
	assert_not_null(view.arena)
	assert_not_null(view.arena.get_node("Rope"))
	assert_not_null(view.arena.get_node("Marker"))
	var left: MeshInstance3D = view.arena.get_node("WinLineLeft")
	assert_almost_eq(left.position.x, -TugOfWar.WIN_OFFSET, 0.001)


func test_render_replaces_replicated_state() -> void:
	view.render({"rope": -3.5, "win_offset": 10.0, "team_a": [0], "team_b": [1]})
	assert_eq(view.rope, -3.5)
	assert_eq(view.team_a, [0])
	assert_eq(view.team_b, [1])
	view.render({"rope": 1.0, "win_offset": 10.0, "team_a": [1], "team_b": [0]})
	assert_eq(view.team_a, [1], "each snapshot fully replaces the last")


func test_marker_tracks_rope_offset() -> void:
	view.render({"rope": 4.0, "win_offset": 10.0, "team_a": [0], "team_b": [1]})
	var marker: MeshInstance3D = view.arena.get_node("Marker")
	assert_almost_eq(marker.position.x, 4.0, 0.001)


func test_teams_stand_relative_to_the_rope() -> void:
	view.render({"rope": 2.0, "win_offset": 10.0, "team_a": [0], "team_b": [1]})
	var rig_a: CharacterRig = view.rig_for_slot(0)
	var rig_b: CharacterRig = view.rig_for_slot(1)
	assert_lt(rig_a.position.x, 2.0, "team A hangs off the -x side of the knot")
	assert_gt(rig_b.position.x, 2.0, "team B mirrors on +x")


## #314 FX: the win burst fires exactly once, when the rope reaches the line.
func test_win_burst_fires_once_at_the_line() -> void:
	view.render({"rope": -8.0, "win_offset": 10.0, "team_a": [0], "team_b": [1]})
	assert_false(view._win_fired, "no win before the line")
	var before := view.arena.get_child_count()
	view.render({"rope": -10.0, "win_offset": 10.0, "team_a": [0], "team_b": [1]})
	assert_true(view._win_fired, "dragging the knot over the line fires the burst")
	assert_gt(view.arena.get_child_count(), before, "burst meshes spawned")
	# A second at-the-line render must not re-fire the one-shot burst.
	var mid := view.arena.get_child_count()
	view.render({"rope": -10.0, "win_offset": 10.0, "team_a": [0], "team_b": [1]})
	assert_lte(view.arena.get_child_count(), mid, "the burst does not re-fire while held")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.rope, 0.0)
	assert_eq(view.team_a, [])
