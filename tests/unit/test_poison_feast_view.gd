extends GutTest
## Poison Feast client view (reworked per #174): renders replicated
## snapshots in the shared iso-arena without simulating anything locally —
## id-keyed tiered dishes, the pot banner, and stagger captions.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/poison_feast/poison_feast_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_dishes_spawn_by_id_at_snapshot_positions_and_despawn_when_eaten() -> void:
	(
		view
		. render(
			{
				"players": {},
				"dishes":
				[
					[7, 2.0, -3.0, PoisonFeast.Tier.CLEAN],
					[8, 4.0, 5.0, PoisonFeast.Tier.DELICACY],
				],
				"pot": 0,
			}
		)
	)
	var first: Node3D = view.arena.get_node("Dish7")
	assert_not_null(first)
	assert_almost_eq(first.position.x, 2.0, 0.001)
	assert_almost_eq(first.position.z, -3.0, 0.001)
	assert_not_null(view.arena.get_node("Dish8"))
	view.render({"players": {}, "dishes": [[8, 4.0, 5.0, PoisonFeast.Tier.DELICACY]], "pot": 0})
	# queue_free() lands at frame end; the node is at least despawning.
	var eaten: Node3D = view.arena.get_node_or_null("Dish7")
	assert_true(eaten == null or eaten.is_queued_for_deletion(), "eaten dishes despawn")


func test_rig_follows_player_snapshot_with_score_and_stagger() -> void:
	view.render({"players": {0: [3.0, -2.0, 4, 0]}, "dishes": [], "pot": 0})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 3.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)
	assert_string_contains(rig.display_name, "Alice")
	assert_string_contains(rig.display_name, "4")
	view.render({"players": {0: [3.0, -2.0, 1, 1]}, "dishes": [], "pot": 3})
	assert_string_contains(rig.display_name, "poisoned")


func test_pot_banner_shows_only_while_the_pot_holds_points() -> void:
	var banner: Label = view.get_node("PotLabel")
	view.render({"players": {}, "dishes": [], "pot": 0})
	assert_false(banner.visible)
	view.render({"players": {}, "dishes": [], "pot": 7})
	assert_true(banner.visible)
	assert_string_contains(banner.text, "7")


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"players": {0: [0.0, 0.0, 1, 0], 1: [1.0, 1.0, 2, 0]},
				"dishes": [[1, 0.0, 0.0, PoisonFeast.Tier.CLEAN]],
				"pot": 0,
			}
		)
	)
	assert_eq(view.players.size(), 2)
	assert_eq(view.dishes.size(), 1)
	view.render({"players": {0: [0.0, 0.0, 1, 0]}, "dishes": [], "pot": 0})
	assert_eq(view.players.size(), 1, "each snapshot fully replaces the last")
	assert_eq(view.dishes.size(), 0)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.dishes.size(), 0)
