extends GutTest
## Cart Push client view (recreated per #175): renders replicated snapshots
## in the shared iso-arena — one shared cart, id-keyed ore, team bonuses —
## without simulating anything locally. (Replaces the obsolete 2D contract,
## which errored silently under GUT rather than asserting anything.)

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
				"players": {0: [1.0, 2.0, 0]},
				"cart": -3.0,
				"teams": [[0], [1]],
				"ores": [],
				"bonus": [1, 0],
			}
		)
	)
	assert_eq(view.players.size(), 1)
	assert_almost_eq(view.cart_x, -3.0, 0.001)
	assert_eq(view.teams, [[0], [1]])
	assert_eq(view.bonus, [1, 0])
	view.render({"players": {}, "cart": 0.0, "teams": [], "ores": [], "bonus": [0, 0]})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_cart_node_tracks_the_shared_cart_position() -> void:
	view.render({"players": {}, "cart": 5.0, "teams": [], "ores": [], "bonus": [0, 0]})
	var cart: Node3D = view.arena.get_node("Cart")
	assert_almost_eq(cart.position.x, 5.0, 0.001)


func test_ore_nodes_spawn_by_id_and_despawn() -> void:
	view.render(
		{"players": {}, "cart": 0.0, "teams": [], "ores": [[3, 2.0, -4.0]], "bonus": [0, 0]}
	)
	var ore: Node3D = view.arena.get_node("Ore3")
	assert_not_null(ore)
	assert_almost_eq(ore.position.x, 2.0, 0.001)
	assert_almost_eq(ore.position.z, -4.0, 0.001)
	view.render({"players": {}, "cart": 0.0, "teams": [], "ores": [], "bonus": [0, 0]})
	var gone: Node3D = view.arena.get_node_or_null("Ore3")
	assert_true(gone == null or gone.is_queued_for_deletion(), "collected ore despawns")


func _particle_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			count += 1
	return count


## M13-23: the cart kicks wheel dust as it rolls (once per DUST_STEP travelled).
func test_cart_kicks_wheel_dust_as_it_rolls() -> void:
	view.render({"players": {}, "cart": 0.0, "teams": [], "ores": [], "bonus": [0, 0]})
	assert_eq(_particle_count(), 0, "no dust while the cart is still")
	view.render({"players": {}, "cart": 2.0, "teams": [], "ores": [], "bonus": [0, 0]})
	assert_gt(_particle_count(), 0, "rolling the cart kicks dust")


## A shove landing (stagger rising edge, flag bit 2) puffs dust off the victim.
func test_shove_impact_puffs() -> void:
	view.render(
		{"players": {0: [1.0, 0.0, 0]}, "cart": 0.0, "teams": [], "ores": [], "bonus": [0, 0]}
	)
	assert_eq(_particle_count(), 0)
	view.render(
		{"players": {0: [1.0, 0.0, 2]}, "cart": 0.0, "teams": [], "ores": [], "bonus": [0, 0]}
	)
	assert_gt(_particle_count(), 0, "the shove impact puffs")


## Scooping an ore (it leaves the list) sparkles at the pickup.
func test_ore_pickup_sparkles() -> void:
	view.render(
		{"players": {}, "cart": 0.0, "teams": [], "ores": [[3, 2.0, -4.0]], "bonus": [0, 0]}
	)
	assert_eq(_particle_count(), 0, "no sparkle while the ore sits there")
	view.render({"players": {}, "cart": 0.0, "teams": [], "ores": [], "bonus": [0, 0]})
	assert_gt(_particle_count(), 0, "the pickup sparkles")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_almost_eq(view.cart_x, 0.0, 0.001)
