extends GutTest
## Tilt Deck client view (#794): renders replicated snapshots in the iso arena —
## the raft leans with the tilt vector, players ride it, and slipping off the
## rim splashes into the sea. No local simulation.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/tilt_deck/tilt_deck_view.tscn")

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func _snap(
	players: Dictionary, tilt := [0.0, 0.0], coins := [], cargo := [], fallen := []
) -> Dictionary:
	return {
		"players": players,
		"tilt": tilt,
		"deck_radius": TiltDeck.DECK_RADIUS,
		"coins": coins,
		"cargo": cargo,
		"fallen": fallen,
	}


func test_setup_builds_the_deck_over_water() -> void:
	assert_not_null(view.arena.get_node_or_null("Deck"), "the tilting raft exists")
	assert_not_null(view.arena.get_node_or_null("Water"), "it floats on water")
	assert_false((view.arena.get_node("Floor") as Node3D).visible, "the base tile floor is hidden")


func test_rigs_ride_the_deck() -> void:
	# Reparented in _setup_3d so they tilt with the raft.
	assert_eq(view.rig_for_slot(0).get_parent(), view.arena.get_node("Deck"))


func test_deck_leans_with_the_tilt_vector() -> void:
	view.render(_snap({0: [0.0, 0.0, 0]}, [0.8, 0.0]))
	var deck: Node3D = view.arena.get_node("Deck")
	# +tilt.x rolls the +x edge down: rotation about z is negative, non-trivial.
	assert_lt(deck.rotation.z, -0.01, "a +x lean rolls the deck")
	view.render(_snap({0: [0.0, 0.0, 0]}, [0.0, 0.0]))
	assert_almost_eq(deck.rotation.z, 0.0, 0.001, "a level deck sits flat")


func test_players_render_with_coin_count_on_the_plate() -> void:
	view.render(_snap({0: [2.0, -1.0, 4]}))
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_true(rig.visible, "an aboard player is shown")
	assert_string_contains(rig.display_name, "4", "the plate shows their coins")


func test_falling_off_hides_the_rig_and_splashes() -> void:
	view.render(_snap({0: [3.0, 0.0, 0], 1: [-3.0, 0.0, 0]}))
	var before := _particle_count()
	# Slot 0 drops off the rim (its group appears in fallen, and it leaves players).
	view.render(_snap({1: [-3.0, 0.0, 0]}, [0.0, 0.0], [], [], [[0]]))
	assert_false(view.rig_for_slot(0).visible, "the fallen rig drops into the sea")
	assert_gt(_particle_count(), before, "a splash bursts where they went over")


func test_coins_pool_onto_the_deck() -> void:
	view.render(_snap({0: [0.0, 0.0, 0]}, [0.0, 0.0], [[6.0, 0.0], [0.0, 6.0]]))
	assert_eq(view._coin_nodes.size(), 2, "a coin node per replicated coin")
	assert_true((view._coin_nodes[0] as Node3D).visible)
	assert_eq(
		(view._coin_nodes[0] as Node3D).get_parent(), view.arena.get_node("Deck"), "rides deck"
	)


func test_cargo_renders_and_fades_with_its_life() -> void:
	view.render(_snap({0: [0.0, 0.0, 0]}, [0.0, 0.0], [], [[4.0, 0.0, 1.0]]))
	assert_eq(view._cargo_nodes.size(), 1, "a crate node for the drop")
	var full_alpha: float = view._cargo_materials[0].albedo_color.a
	view.render(_snap({0: [0.0, 0.0, 0]}, [0.0, 0.0], [], [[4.0, 0.0, 0.1]]))
	assert_lt(view._cargo_materials[0].albedo_color.a, full_alpha, "the crate fades as it lifts")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_almost_eq((view.arena.get_node("Deck") as Node3D).rotation.z, 0.0, 0.001)


func _particle_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			count += 1
	return count
