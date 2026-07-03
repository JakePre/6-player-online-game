extends GutTest
## Color Clash client view (M8-10): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/color_clash/color_clash_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"color_clash"),
		"res://src/minigames/color_clash/color_clash_view.tscn"
	)


func test_setup_builds_iso_arena_with_paint_tiles() -> void:
	assert_not_null(view.arena)
	assert_not_null(view.rig_for_slot(0))
	var tiles: MultiMeshInstance3D = view.arena.get_node("PaintTiles")
	assert_eq(tiles.multimesh.instance_count, ColorClash.GRID_SIZE * ColorClash.GRID_SIZE)


func test_render_replaces_replicated_state() -> void:
	view.render({"players": {0: [1.0, 2.0, 0]}, "grid": [0, -1, 1], "teams": []})
	assert_eq(view.players.size(), 1)
	assert_eq(view.grid, [0, -1, 1])
	view.render({"players": {}, "grid": [1], "teams": [[0], [1]]})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")
	assert_eq(view.teams, [[0], [1]])


func test_painted_tiles_take_faction_colors() -> void:
	var full_grid: Array = []
	full_grid.resize(ColorClash.GRID_SIZE * ColorClash.GRID_SIZE)
	full_grid.fill(ColorClash.UNPAINTED)
	full_grid[0] = 0
	view.render({"players": {}, "grid": full_grid, "teams": []})
	assert_ne(view.tile_color(0), view.tile_color(1))
	assert_eq(view.tile_color(0), PlayerPalette.color_for_slot(0).darkened(0.15))


func test_team_tiles_use_first_teammate_color() -> void:
	view.render({"players": {}, "grid": [1], "teams": [[0], [1]]})
	assert_eq(view.tile_color(0), PlayerPalette.color_for_slot(1).darkened(0.15))


func test_rig_follows_player_snapshot() -> void:
	view.render({"players": {0: [4.0, -2.0, 0]}, "grid": [], "teams": []})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 4.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.grid, [])
