extends GutTest
## Cart Push client view (M4-12): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/cart_push/cart_push_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"cart_push"),
		"res://src/minigames/cart_push/cart_push_view.tscn"
	)


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"players": {0: [1.0, 2.0]},
				"carts": [-3.0, 4.0],
				"track": [-9.0, 9.0],
				"lane_y": 4.0,
				"teams": [[0], [1]],
			}
		)
	)
	assert_eq(view.players.size(), 1)
	assert_eq(view.carts, [-3.0, 4.0])
	assert_eq(view.teams, [[0], [1]])
	view.render({"players": {}, "carts": [], "track": [], "teams": []})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.carts, [])
