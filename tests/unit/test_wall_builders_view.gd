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
	# PR #1074: pool entries are instanced crate scenes (Node3D), not meshes.
	for node: Node3D in view._wall_pools[0]:
		if node.visible:
			team0_visible += 1
	assert_eq(team0_visible, 3, "one crate per wall block")
	assert_string_contains(view.rig_for_slot(0).display_name, "🧱")
	assert_true((view._carry_markers[0] as Node3D).visible)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.blocks, [])


## #807: each team's delivery spot gets a floor decal plus a beacon, visible
## even before any block has actually been stacked.
func test_home_zones_are_marked_for_both_teams() -> void:
	for team_index in 2:
		assert_not_null(view.arena.get_node("HomeZone%d" % team_index))
		assert_not_null(view.arena.get_node("HomeBeacon%d" % team_index))
	var zone0: MeshInstance3D = view.arena.get_node("HomeZone0")
	var zone1: MeshInstance3D = view.arena.get_node("HomeZone1")
	assert_almost_eq(
		zone0.position.x, -WallBuilders.WALL_X, 0.001, "team 0's home sits at its wall"
	)
	assert_almost_eq(zone1.position.x, WallBuilders.WALL_X, 0.001, "team 1's home sits at its wall")
	var mat0: StandardMaterial3D = zone0.mesh.material
	var mat1: StandardMaterial3D = zone1.mesh.material
	assert_ne(mat0.albedo_color, mat1.albedo_color, "each team's home reads as its own color")
