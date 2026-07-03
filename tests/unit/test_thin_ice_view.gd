extends GutTest
## Thin Ice client view (M8-06): renders replicated snapshots in the shared
## iso-arena without simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/thin_ice/thin_ice_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func _full_grid(state: int) -> Array:
	var grid: Array = []
	grid.resize(ThinIce.GRID_SIZE * ThinIce.GRID_SIZE)
	grid.fill(state)
	return grid


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"thin_ice"),
		"res://src/minigames/thin_ice/thin_ice_view.tscn"
	)


func test_setup_builds_ice_grid_over_water() -> void:
	assert_not_null(view.arena.get_node("Water"))
	assert_not_null(view.arena.get_node("Tile_0_0"))
	assert_not_null(
		view.arena.get_node("Tile_%d_%d" % [ThinIce.GRID_SIZE - 1, ThinIce.GRID_SIZE - 1])
	)
	assert_null(view.arena.get_node_or_null("Floor"), "default kit floor is replaced by the ice")


func test_tiles_follow_damage_states() -> void:
	var grid := _full_grid(ThinIce.TileState.INTACT)
	grid[0] = ThinIce.TileState.CRACKED
	grid[1] = ThinIce.TileState.GONE
	view.render({"tiles": grid, "players": {}, "fallen": []})
	var cracked: MeshInstance3D = view.arena.get_node("Tile_0_0")
	var gone: MeshInstance3D = view.arena.get_node("Tile_1_0")
	var intact: MeshInstance3D = view.arena.get_node("Tile_2_0")
	assert_true(cracked.visible)
	assert_eq(cracked.material_override, view._cracked_material)
	assert_false(gone.visible, "gone tiles vanish into the water")
	assert_eq(intact.material_override, view._intact_material)


func test_rig_follows_player_snapshot() -> void:
	view.render(
		{"tiles": _full_grid(ThinIce.TileState.INTACT), "players": {0: [3.0, -2.0]}, "fallen": []}
	)
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_true(rig.visible)
	assert_almost_eq(rig.position.x, 3.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)


func test_fallen_player_rig_disappears() -> void:
	var grid := _full_grid(ThinIce.TileState.INTACT)
	view.render({"tiles": grid, "players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "fallen": []})
	assert_true(view.rig_for_slot(1).visible)
	view.render({"tiles": grid, "players": {0: [0.0, 0.0]}, "fallen": [[1]]})
	assert_false(view.rig_for_slot(1).visible, "fall groups flatten to hidden rigs")
	assert_true(view.rig_for_slot(0).visible)


func test_render_replaces_replicated_state() -> void:
	var grid := _full_grid(ThinIce.TileState.INTACT)
	view.render({"tiles": grid, "players": {0: [1.0, -2.0]}, "fallen": []})
	assert_eq(view.players.size(), 1)
	assert_eq(view.players[0], [1.0, -2.0])
	view.render({"tiles": grid, "players": {}, "fallen": [[0]]})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.tiles.size(), 0)
	assert_eq(view.fallen.size(), 0)
