extends GutTest
## Wall Builders client view (M10-10): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/wall_builders/wall_builders_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"wall_builders"),
		"res://src/minigames/wall_builders/wall_builders_view.tscn"
	)


func test_wall_stacks_track_heights_and_carriers_read() -> void:
	(
		view
		. render(
			{
				"players": {0: [1.0, 1.0, 1]},
				"blocks": [[0.0, 0.0]],
				"walls": [3, 1],
				"teams": [[0], [1]],
			}
		)
	)
	var team0_visible := 0
	for node: MeshInstance3D in view._wall_pools[0]:
		if node.visible:
			team0_visible += 1
	assert_eq(team0_visible, 3, "one cube per wall block")
	assert_string_contains(view.rig_for_slot(0).display_name, "🧱")
	assert_true((view._carry_markers[0] as MeshInstance3D).visible)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.blocks, [])
