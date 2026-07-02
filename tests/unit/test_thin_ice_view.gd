extends GutTest
## Thin Ice client view (M4-03): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/thin_ice/thin_ice_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"thin_ice"),
		"res://src/minigames/thin_ice/thin_ice_view.tscn"
	)


func test_render_replaces_replicated_state() -> void:
	var tiles: Array = []
	tiles.resize(ThinIce.GRID_SIZE * ThinIce.GRID_SIZE)
	tiles.fill(ThinIce.TileState.INTACT)
	view.render({"tiles": tiles, "players": {0: [1.0, -2.0]}, "fallen": []})
	assert_eq(view.players.size(), 1)
	assert_eq(view.players[0], [1.0, -2.0])
	view.render({"tiles": tiles, "players": {}, "fallen": [[0]]})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
