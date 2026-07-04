extends GutTest
## Finale Gauntlet client view (M8-12): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/finale/gauntlet_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_setup_builds_iso_arena_with_rigs_and_platform() -> void:
	assert_not_null(view.arena, "MinigameView3D arena should exist after setup")
	assert_not_null(view.rig_for_slot(0))
	assert_not_null(view.rig_for_slot(1))
	var platform: MeshInstance3D = view.arena.get_node("Platform")
	assert_not_null(platform)
	assert_eq((platform.mesh as CylinderMesh).top_radius, Gauntlet.START_RADIUS)


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"radius": 7.0,
				"players": {0: [1.0, -2.0, 2, 0.0], 1: [0.0, 0.0, 1, 0.0]},
				"hazards": [[2.0, 2.0, 1.5, 0.8]],
			}
		)
	)
	assert_eq(view.radius, 7.0)
	assert_eq(view.players.size(), 2)
	assert_eq(view.hazards.size(), 1)
	view.render({"radius": 5.5, "players": {}, "hazards": []})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")
	assert_eq(view.hazards.size(), 0)


func test_platform_disc_tracks_snapshot_radius() -> void:
	view.render({"radius": 4.0, "players": {}, "hazards": []})
	var platform: MeshInstance3D = view.arena.get_node("Platform")
	assert_eq((platform.mesh as CylinderMesh).top_radius, 4.0)


func test_respawning_and_eliminated_players_hide_their_rigs() -> void:
	(
		view
		. render(
			{
				"radius": 10.0,
				"players": {0: [1.0, 1.0, 1, 2.5], 1: [2.0, 2.0, 0, 0.0]},
				"hazards": [],
			}
		)
	)
	assert_false(view.rig_for_slot(0).visible, "respawning players are off the platform")
	assert_false(view.rig_for_slot(1).visible, "eliminated players are gone")
	view.render({"radius": 10.0, "players": {0: [1.0, 1.0, 1, 0.0]}, "hazards": []})
	assert_true(view.rig_for_slot(0).visible, "back after the respawn")


func test_lives_shown_on_nameplate() -> void:
	view.render({"radius": 10.0, "players": {0: [0.0, 0.0, 3, 0.0]}, "hazards": []})
	assert_string_contains(view.rig_for_slot(0).display_name, "♥♥♥")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.hazards.size(), 0)
	assert_eq(view.radius, Gauntlet.START_RADIUS)


func _particle_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			count += 1
	return count


## M13-31: the platform sheds crumble dust each time it shrinks a stage.
func test_shrinking_platform_crumbles_dust() -> void:
	view.render({"radius": Gauntlet.START_RADIUS, "players": {}, "hazards": []})
	var before := _particle_count()
	view.render({"radius": Gauntlet.START_RADIUS - 3.0, "players": {}, "hazards": []})
	assert_gt(_particle_count(), before, "a shrink crumbles the shed rim")


## M13-31: a freshly-armed hazard pops a warning spark; a detonating one bursts.
func test_hazard_telegraph_sparks_then_bursts() -> void:
	var armed := {"radius": Gauntlet.START_RADIUS, "players": {}, "hazards": [[2.0, 0.0, 1.5, 0.8]]}
	view.render(armed)
	var after_spawn := _particle_count()
	assert_gt(after_spawn, 0, "a new hazard telegraphs a spark")
	# Same radius so no crumble; the hazard vanishes (detonates).
	view.render({"radius": Gauntlet.START_RADIUS, "players": {}, "hazards": []})
	assert_gt(_particle_count(), after_spawn, "a detonating hazard bursts")


## M13-31: losing a life bursts where the player stood.
func test_losing_a_life_bursts() -> void:
	var two := {"radius": Gauntlet.START_RADIUS, "players": {0: [0.0, 0.0, 2, 0.0]}, "hazards": []}
	view.render(two)
	var before := _particle_count()
	view.render(
		{"radius": Gauntlet.START_RADIUS, "players": {0: [0.0, 0.0, 1, 0.0]}, "hazards": []}
	)
	assert_gt(_particle_count(), before, "a lost life bursts at the player")
