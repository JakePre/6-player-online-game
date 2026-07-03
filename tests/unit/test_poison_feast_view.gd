extends GutTest
## Poison Feast client view (M8-11): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/poison_feast/poison_feast_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_setup_pools_uniform_hidden_dishes() -> void:
	assert_not_null(view.arena.get_node("Dish0"))
	assert_not_null(view.arena.get_node("Dish%d" % (PoisonFeast.MAX_ACTIVE_DISHES - 1)))
	for i in PoisonFeast.MAX_ACTIVE_DISHES:
		assert_false(view.arena.get_node("Dish%d" % i).visible, "dishes start hidden")


func test_dishes_show_at_snapshot_positions() -> void:
	view.render({"players": {}, "dishes": [[2.0, -3.0], [4.0, 5.0]]})
	var first: Node3D = view.arena.get_node("Dish0")
	var second: Node3D = view.arena.get_node("Dish1")
	var third: Node3D = view.arena.get_node("Dish2")
	assert_true(first.visible)
	assert_almost_eq(first.position.x, 2.0, 0.001)
	assert_almost_eq(first.position.z, -3.0, 0.001)
	assert_true(second.visible)
	assert_false(third.visible, "pool beyond the snapshot stays hidden")
	view.render({"players": {}, "dishes": [[1.0, 1.0]]})
	assert_false(second.visible, "eaten dishes disappear")


func test_rig_follows_player_snapshot_with_score() -> void:
	view.render({"players": {0: [3.0, -2.0, 4]}, "dishes": []})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 3.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)
	assert_string_contains(rig.display_name, "Alice")
	assert_string_contains(rig.display_name, "4")


func test_render_replaces_replicated_state() -> void:
	view.render({"players": {0: [0.0, 0.0, 1], 1: [1.0, 1.0, 2]}, "dishes": [[0.0, 0.0]]})
	assert_eq(view.players.size(), 2)
	assert_eq(view.dishes.size(), 1)
	view.render({"players": {0: [0.0, 0.0, 1]}, "dishes": []})
	assert_eq(view.players.size(), 1, "each snapshot fully replaces the last")
	assert_eq(view.dishes.size(), 0)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.dishes.size(), 0)
