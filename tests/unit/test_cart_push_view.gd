extends GutTest
## Payload Race client view (#932, reworked from the shared-cart Cart Push
## #175): renders replicated snapshots in the shared iso-arena — two team-keyed
## carts on parallel rails — without simulating anything locally.

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
	view.render({"players": {0: [1.0, 2.0, 0]}, "carts": [-3.0, 4.0], "teams": [[0], [1]]})
	assert_eq(view.players.size(), 1)
	assert_eq(view.progress, [-3.0, 4.0])
	assert_eq(view.teams, [[0], [1]])
	view.render({"players": {}, "carts": [0.0, 0.0], "teams": []})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_each_cart_tracks_its_lanes_progress() -> void:
	view.render({"players": {}, "carts": [5.0, 2.0], "teams": []})
	var cart0: Node3D = view.arena.get_node("Cart0")
	var cart1: Node3D = view.arena.get_node("Cart1")
	assert_almost_eq(cart0.position.x, -CartPush.TRACK_HALF + 5.0, 0.001)
	assert_almost_eq(cart1.position.x, -CartPush.TRACK_HALF + 2.0, 0.001)


func _particle_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			count += 1
	return count


## M13-23: a cart kicks wheel dust as it rolls (once per DUST_STEP travelled).
func test_carts_kick_wheel_dust_as_they_roll() -> void:
	view.render({"players": {}, "carts": [0.0, 0.0], "teams": []})
	assert_eq(_particle_count(), 0, "no dust while the carts are still")
	view.render({"players": {}, "carts": [2.0, 0.0], "teams": []})
	assert_gt(_particle_count(), 0, "rolling a cart kicks dust")


## A shove landing (stagger rising edge, FLAG_STAGGERED) puffs dust off the victim.
func test_shove_impact_puffs() -> void:
	view.render({"players": {0: [1.0, 0.0, 0]}, "carts": [0.0, 0.0], "teams": []})
	assert_eq(_particle_count(), 0)
	view.render(
		{"players": {0: [1.0, 0.0, CartPush.FLAG_STAGGERED]}, "carts": [0.0, 0.0], "teams": []}
	)
	assert_gt(_particle_count(), 0, "the shove impact puffs")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.progress, [0.0, 0.0])
