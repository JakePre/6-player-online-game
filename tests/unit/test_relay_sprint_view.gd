extends GutTest
## Relay Sprint client view (M4-11): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/relay_sprint/relay_sprint_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"relay_sprint"),
		"res://src/minigames/relay_sprint/relay_sprint_view.tscn"
	)


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"lanes": {0: [[0], 0, 3.0, 0.5, false]},
				"track_len": 24.0,
				"hazards": [[7.0, 1.0]],
			}
		)
	)
	assert_eq(view.lanes.size(), 1)
	assert_eq(view.hazards, [[7.0, 1.0]])
	view.render({"lanes": {}, "track_len": 24.0, "hazards": []})
	assert_eq(view.lanes.size(), 0, "each snapshot fully replaces the last")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.lanes.size(), 0)
	assert_eq(view.hazards, [])
