extends GutTest
## Sumo Smash client view (M4-04): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/sumo_smash/sumo_smash_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"sumo_smash"),
		"res://src/minigames/sumo_smash/sumo_smash_view.tscn"
	)


func test_render_replaces_replicated_state() -> void:
	view.render({"radius": 8.0, "players": {0: [1.0, -2.0, 0.5, 1]}, "out": []})
	assert_eq(view.players.size(), 1)
	assert_eq(view.players[0], [1.0, -2.0, 0.5, 1])
	view.render({"radius": 8.0, "players": {}, "out": [[0]]})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
