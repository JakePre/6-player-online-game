extends GutTest
## Poison Feast client view (M8-11): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

const VIEW_SCENE := preload("res://src/minigames/poison_feast/poison_feast_view.tscn")

var view: MinigameView


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_dishes_appear_by_id_at_snapshot_positions() -> void:
	# Sim contract: dish entries are [id, x, y, tier]; nodes are id-keyed so
	# identity is stable however the array is ordered.
	view.render({"players": {}, "dishes": [[7, 2.0, -3.0, 0], [3, 4.0, 5.0, 2]]})
	var seven: Node3D = view.arena.get_node("Dish7")
	var three: Node3D = view.arena.get_node("Dish3")
	assert_almost_eq(seven.position.x, 2.0, 0.001)
	assert_almost_eq(seven.position.z, -3.0, 0.001)
	assert_almost_eq(three.position.x, 4.0, 0.001)


func test_eaten_dishes_disappear() -> void:
	view.render({"players": {}, "dishes": [[7, 2.0, -3.0, 0], [3, 4.0, 5.0, 2]]})
	view.render({"players": {}, "dishes": [[3, 4.0, 5.0, 2]]})
	# queue_free lands at frame end; the view's own registry drops it now.
	assert_false(view._dish_nodes.has(7), "eaten dish leaves the registry")
	assert_true(view._dish_nodes.has(3))


func test_rig_follows_player_snapshot_with_score() -> void:
	view.render({"players": {0: [3.0, -2.0, 4, 0]}, "dishes": []})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 3.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)
	assert_string_contains(rig.display_name, "Alice")
	assert_string_contains(rig.display_name, "4")


func test_render_replaces_replicated_state() -> void:
	view.render(
		{"players": {0: [0.0, 0.0, 1, 0], 1: [1.0, 1.0, 2, 0]}, "dishes": [[1, 0.0, 0.0, 0]]}
	)
	assert_eq(view.players.size(), 2)
	assert_eq(view.dishes.size(), 1)
	view.render({"players": {0: [0.0, 0.0, 1, 0]}, "dishes": []})
	assert_eq(view.players.size(), 1, "each snapshot fully replaces the last")
	assert_eq(view.dishes.size(), 0)


func _burst_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			count += 1
	return count


## M13-25: a dish only leaves the list when eaten, so its removal bursts.
func test_eating_a_dish_bursts() -> void:
	view.render({"players": {}, "dishes": [[7, 2.0, -3.0, 0]]})
	assert_eq(_burst_count(), 0, "no burst while the dish sits there")
	view.render({"players": {}, "dishes": []})
	assert_gt(_burst_count(), 0, "eating the dish bursts")


## Biting poison (stagger rising edge) puffs over the eater — for anyone, not
## just the local player.
func test_poison_bite_puffs() -> void:
	view.render({"players": {1: [0.0, 0.0, 0, 0]}, "dishes": []})
	assert_eq(_burst_count(), 0)
	view.render({"players": {1: [0.0, 0.0, -3, 1]}, "dishes": []})
	assert_gt(_burst_count(), 0, "a poisoned bite puffs")


## The pot emptying (a clean bite claimed it) pops a burst on the table.
func test_pot_claim_bursts() -> void:
	view.render({"players": {}, "dishes": [], "pot": 5})
	assert_eq(_burst_count(), 0, "no burst while the pot is building")
	view.render({"players": {}, "dishes": [], "pot": 0})
	assert_gt(_burst_count(), 0, "claiming the pot pops a burst")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.dishes.size(), 0)


## M15: the view derives its floor/camera size from the lobby count with the
## same formula the sim uses, so the rendered table matches the scaled one.
func test_arena_half_scales_with_lobby_size() -> void:
	assert_almost_eq(view._arena_half(), PoisonFeast.ARENA_HALF, 0.001, "2 players = base table")
	var big: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(big)
	var names := {}
	for i in 12:
		names[i] = "P%d" % (i + 1)
	big.setup(names, 0)
	assert_gt(big._arena_half(), PoisonFeast.ARENA_HALF, "12 players get a bigger table")
