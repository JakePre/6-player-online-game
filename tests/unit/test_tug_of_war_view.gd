extends GutTest
## Tug of War client view (M4-10): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView


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


func test_render_replaces_replicated_state() -> void:
	view.render({"rope": -3.5, "win_offset": 10.0, "team_a": [0], "team_b": [1]})
	assert_eq(view.rope, -3.5)
	assert_eq(view.team_a, [0])
	assert_eq(view.team_b, [1])
	view.render({"rope": 1.0, "win_offset": 10.0, "team_a": [1], "team_b": [0]})
	assert_eq(view.team_a, [1], "each snapshot fully replaces the last")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.rope, 0.0)
	assert_eq(view.team_a, [])
