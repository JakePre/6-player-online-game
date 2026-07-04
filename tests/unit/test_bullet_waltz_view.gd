extends GutTest
## Bullet Waltz client view (M10-18): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/bullet_waltz/bullet_waltz_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"bullet_waltz"),
		"res://src/minigames/bullet_waltz/bullet_waltz_view.tscn"
	)


func test_setup_builds_turret_and_bullet_pool() -> void:
	assert_not_null(view.arena.get_node("Turret"))
	assert_not_null(view.rig_for_slot(0))


func test_bullets_show_from_the_pool_and_kos_hide_rigs() -> void:
	(
		view
		. render(
			{
				"players": {0: [1.0, 1.0, 2]},
				"bullets": [[0.5, 0.5], [2.0, -1.0]],
				"out": [[1]],
			}
		)
	)
	assert_eq(view.bullets.size(), 2)
	assert_false(view.rig_for_slot(1).visible, "KO'd players leave the floor")
	assert_true(view.rig_for_slot(0).visible)
	assert_string_contains(view.rig_for_slot(0).display_name, "2")
	view.render({"players": {0: [1.0, 1.0, 0]}, "bullets": [], "out": [[1]]})
	assert_eq(view.bullets.size(), 0, "each snapshot fully replaces the last")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.bullets, [])


func _particle_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			count += 1
	return count


## M13-29: a bullet out in the field stretches into a tracer streak; one still at
## the muzzle stays round (its travel direction is undefined there).
func test_bullet_stretches_into_a_tracer() -> void:
	view.render({"players": {0: [0.0, 0.0, 0]}, "bullets": [[3.0, 0.0]], "out": []})
	assert_true(view._bullet_pool[0].visible, "the active bullet is shown")
	assert_gt(view._bullet_pool[0].scale.z, 1.0, "a flying bullet stretches into a tracer")
	view.render({"players": {0: [0.0, 0.0, 0]}, "bullets": [[0.1, 0.0]], "out": []})
	assert_almost_eq(view._bullet_pool[0].scale.z, 1.0, 0.001, "a muzzle-close bullet stays round")


## M13-29: a fresh graze shimmers a spark at the dancer; an unchanged count does not.
func test_grazing_pops_a_shimmer() -> void:
	view.render({"players": {0: [0.0, 0.0, 0], 1: [2.0, 0.0, 0]}, "bullets": [], "out": []})
	var before := _particle_count()
	view.render({"players": {0: [0.0, 0.0, 1], 1: [2.0, 0.0, 0]}, "bullets": [], "out": []})
	assert_gt(_particle_count(), before, "a fresh graze shimmers")
	var steady := _particle_count()
	view.render({"players": {0: [0.0, 0.0, 1], 1: [2.0, 0.0, 0]}, "bullets": [], "out": []})
	assert_eq(_particle_count(), steady, "an unchanged graze count does not re-spark")


## M13-29: dropping out of the round blasts a burst at the dancer.
func test_ko_pops_a_blast() -> void:
	view.render({"players": {0: [0.0, 0.0, 0], 1: [2.0, 0.0, 0]}, "bullets": [], "out": []})
	var before := _particle_count()
	# Slot 0 is eliminated: gone from players, listed in an out group.
	view.render({"players": {1: [2.0, 0.0, 0]}, "bullets": [], "out": [[0]]})
	assert_gt(_particle_count(), before, "a KO blasts a burst")
