extends GutTest
## Bey Brawl client view (#1034, replaces sumo_smash_view): the stepped bowl,
## permanently-whirlwinding axe-armed rigs, spin pips, clash-edge FX, and
## seeded elimination splashes.

const VIEW_SCENE := preload("res://src/minigames/bey_brawl/bey_brawl_view.tscn")

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func _snapshot(players: Dictionary, out: Array = []) -> Dictionary:
	return {"radius": BeyBrawl.BOWL_RADIUS, "players": players, "out": out}


func _particle_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			count += 1
	return count


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"bey_brawl"),
		"res://src/minigames/bey_brawl/bey_brawl_view.tscn"
	)


func test_setup_builds_the_stepped_bowl_with_a_lip_ring() -> void:
	assert_not_null(view.arena.get_node("BowlLip"))
	assert_not_null(view.arena.get_node("BowlStep0"), "inner discs sell the concave slope")
	var rim: MeshInstance3D = view.arena.get_node("Rim")
	assert_almost_eq(
		(rim.mesh as TorusMesh).outer_radius,
		BeyBrawl.BOWL_RADIUS,
		0.001,
		"the fatal lip sits at the ring-out radius"
	)


func test_spinners_whirlwind_with_the_axe_in_hand() -> void:
	view.render(_snapshot({0: [1.0, 0.0, 1.0, 0], 1: [-1.0, 0.0, 1.0, 0]}))
	var rig := view.rig_for_slot(0)
	assert_true(rig.visible)
	assert_eq(rig.current_action(), &"whirlwind", "everyone spins, always")
	assert_true(rig.has_held_weapon(), "the axe rides the handslot bone")


func test_movement_never_stomps_the_whirlwind() -> void:
	view.render(_snapshot({0: [0.0, 0.0, 1.0, 0], 1: [4.0, 0.0, 1.0, 0]}))
	view.render(_snapshot({0: [1.5, 0.0, 1.0, 0], 1: [4.0, 0.0, 1.0, 0]}))
	assert_eq(
		view.rig_for_slot(0).current_action(),
		&"whirlwind",
		"a moving spinner keeps spinning — no walk/idle override"
	)


func test_spin_meter_rides_the_nameplate_as_pips() -> void:
	view.render(_snapshot({0: [0.0, 0.0, 0.6, 0], 1: [4.0, 0.0, 1.0, 0]}))
	var caption: String = view.rig_for_slot(0).display_name
	assert_string_contains(caption, "●●●○○", "0.6 spin reads as 3 of 5 pips")


func test_clash_edge_bursts_once_not_every_snapshot() -> void:
	view.render(_snapshot({0: [0.0, 0.0, 1.0, 0], 1: [1.0, 0.0, 1.0, 0]}))
	var before := _particle_count()
	view.render(_snapshot({0: [0.0, 0.0, 0.9, 1], 1: [1.0, 0.0, 0.8, 1]}))
	assert_gt(_particle_count(), before, "a fresh clash bursts")
	var after_first := _particle_count()
	view.render(_snapshot({0: [0.0, 0.0, 0.9, 1], 1: [1.0, 0.0, 0.8, 1]}))
	assert_eq(_particle_count(), after_first, "a held clash_seq does not re-burst")


func test_rejoiner_first_snapshot_stays_calm() -> void:
	# Mid-match join: counters already high, one body already out — no FX yet.
	var before := _particle_count()
	view.render(_snapshot({0: [0.0, 0.0, 0.5, 7]}, [[1]]))
	assert_eq(_particle_count(), before, "seeding snapshot fires no clash or KO FX")


func test_out_spinner_splashes_and_hides() -> void:
	view.render(_snapshot({0: [0.0, 0.0, 1.0, 0], 1: [5.0, 0.0, 0.2, 0]}))
	var before := _particle_count()
	view.render(_snapshot({0: [0.0, 0.0, 1.0, 0]}, [[1]]))
	assert_gt(_particle_count(), before, "leaving play splashes")
	assert_false(view.rig_for_slot(1).visible, "an out spinner leaves the bowl")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_not_null(view.arena.get_node("BowlLip"))
