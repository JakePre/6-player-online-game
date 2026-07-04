extends GutTest
## Snake Chain client view (M10-11): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/snake_chain/snake_chain_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"snake_chain"),
		"res://src/minigames/snake_chain/snake_chain_view.tscn"
	)


func test_render_places_trail_segments_from_the_pool() -> void:
	(
		view
		. render(
			{
				"players": {0: [1.0, 1.0, 3, 0.0]},
				"trails": {0: [[0.5, 0.5], [0.0, 0.0]]},
				"pellets": [[2.0, 2.0]],
				"teams": [],
			}
		)
	)
	assert_eq(view.trails[0].size(), 2)
	var visible_segments := 0
	for node: MeshInstance3D in view._segment_pools[0]:
		if node.visible:
			visible_segments += 1
	assert_eq(visible_segments, 2, "one glowing segment per trail point")
	assert_string_contains(view.rig_for_slot(0).display_name, "3")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.pellets, [])
