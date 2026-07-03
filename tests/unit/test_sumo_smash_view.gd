extends GutTest
## Sumo Smash client view (M8-07): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/sumo_smash/sumo_smash_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"sumo_smash"),
		"res://src/minigames/sumo_smash/sumo_smash_view.tscn"
	)


func test_setup_builds_iso_arena_with_rigs_and_platform() -> void:
	assert_not_null(view.arena)
	assert_not_null(view.rig_for_slot(0))
	assert_not_null(view.rig_for_slot(1))
	var platform: MeshInstance3D = view.arena.get_node("Platform")
	assert_eq((platform.mesh as CylinderMesh).top_radius, SumoSmash.PLATFORM_RADIUS)


func test_render_replaces_replicated_state() -> void:
	view.render({"radius": 8.0, "players": {0: [1.0, -2.0, 0.5, 1]}, "out": []})
	assert_eq(view.players.size(), 1)
	assert_eq(view.players[0], [1.0, -2.0, 0.5, 1])
	view.render({"radius": 8.0, "players": {}, "out": [[0]]})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")
	assert_eq(view.out, [[0]])


func test_rig_follows_snapshot_and_ringouts_hide() -> void:
	view.render(
		{"radius": 8.0, "players": {0: [3.0, -1.0, 0.0, 0], 1: [0.0, 0.0, 0.0, 0]}, "out": []}
	)
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_true(rig.visible)
	assert_almost_eq(rig.position.x, 3.0, 0.001)
	assert_almost_eq(rig.position.z, -1.0, 0.001)
	view.render({"radius": 8.0, "players": {1: [0.0, 0.0, 0.0, 0]}, "out": [[0]]})
	assert_false(view.rig_for_slot(0).visible, "rung-out players leave the ring")
	assert_true(view.rig_for_slot(1).visible)


func test_cooldown_on_nameplate() -> void:
	view.render({"radius": 8.0, "players": {0: [0.0, 0.0, 1.5, 0]}, "out": []})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_string_contains(rig.display_name, "1.5")
	view.render({"radius": 8.0, "players": {0: [0.0, 0.0, 0.0, 0]}, "out": []})
	assert_eq(view.rig_for_slot(0).display_name, "Alice", "ready again")


func test_local_dash_indicator_tracks_cooldown() -> void:
	view.render({"radius": 8.0, "players": {0: [0.0, 0.0, 1.0, 0]}, "out": []})
	var label: Label = view.get_node("DashIndicator")
	assert_string_contains(label.text, "DASH")
	assert_false(label.text.contains("READY"), "cooling down")
	view.render({"radius": 8.0, "players": {0: [0.0, 0.0, 0.0, 0]}, "out": []})
	assert_string_contains(label.text, "READY")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.out, [])
