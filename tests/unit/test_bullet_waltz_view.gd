extends GutTest
## Bullet Waltz client view (M10-18): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

const VIEW_SCENE := preload("res://src/minigames/bullet_waltz/bullet_waltz_view.tscn")

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
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


## #929: the real MDL-014 emitter model replaces the flat grey cylinder.
func test_turret_uses_the_emitter_model() -> void:
	var turret: Node3D = view.arena.get_node("Turret")
	assert_gt(turret.get_child_count(), 0, "the real model has its own mesh hierarchy")


## #929: the dark stage overlay swallowed the floor edge — a bright ring at
## the arena boundary sells where the stage actually ends.
func test_arena_rim_is_brightened() -> void:
	var rim: MeshInstance3D = view.arena.get_node("RimGlow")
	var mesh := rim.mesh as TorusMesh
	assert_almost_eq(mesh.outer_radius, view._arena_half(), 0.001, "sits at the floor boundary")


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


## #1036: a volley firing punches the turret and bursts a flash at the muzzle
## — otherwise it's an inert prop with no visible tie to the bullets.
func test_a_fresh_volley_pulses_the_turret() -> void:
	view.render({"players": {}, "bullets": [], "out": []})
	var before := _particle_count()
	view.render({"players": {}, "bullets": [[0.0, 0.0], [0.5, 0.5], [1.0, 1.0]], "out": []})
	assert_eq(view._turret.scale, Vector3.ONE * 1.2, "the turret punches on a fresh volley")
	assert_gt(_particle_count(), before, "a burst flashes at the muzzle")


## A shrinking bullet count (expiry/hits thinning the field) never re-pulses.
func test_bullets_thinning_out_does_not_pulse_the_turret() -> void:
	view.render({"players": {}, "bullets": [[0.0, 0.0], [0.5, 0.5]], "out": []})
	view._turret.scale = Vector3.ONE
	view.render({"players": {}, "bullets": [[0.0, 0.0]], "out": []})
	assert_eq(view._turret.scale, Vector3.ONE, "fewer bullets this snapshot does not pulse")


func test_turret_pulse_is_skipped_under_reduced_motion() -> void:
	ArenaFX.reduced_motion = true
	view.render({"players": {}, "bullets": [], "out": []})
	view.render({"players": {}, "bullets": [[0.0, 0.0]], "out": []})
	assert_eq(view._turret.scale, Vector3.ONE, "no scale pop under reduced motion")


func after_each() -> void:
	ArenaFX.reduced_motion = false


## M15 †-cap: the framed floor grows with a big lobby to match the scaled sim,
## and the 2-player before_each view stays on the tuned baseline.
func test_arena_frames_scale_with_the_crowd() -> void:
	assert_almost_eq(view._arena_half(), BulletWaltz.ARENA_HALF, 0.001, "small lobby is unchanged")
	var crowd: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(crowd)
	var names := {}
	for i in 24:
		names[i] = "P%d" % i
	crowd.setup(names, 0)
	assert_gt(crowd._arena_half(), BulletWaltz.ARENA_HALF, "24 players get a bigger floor")
