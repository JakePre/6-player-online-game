extends GutTest
## Shock Tag client view (M10-03): renders replicated snapshots in the shared
## iso-arena without simulating anything locally.
## Visual enhancements (#1153): buzz ring, electric beam, storm cloud, sparks.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/shock_tag/shock_tag_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"shock_tag"),
		"res://src/minigames/shock_tag/shock_tag_view.tscn"
	)


func test_zap_ring_tracks_the_electrified_player() -> void:
	view.render({"players": {0: [2.0, -1.0, 3], 1: [4.0, 4.0, 0]}, "zapped": 0})
	var ring: MeshInstance3D = view.arena.get_node("ZapRing")
	assert_true(ring.visible)
	assert_almost_eq(ring.position.x, 2.0, 0.001)
	assert_almost_eq(ring.position.z, -1.0, 0.001)
	assert_string_contains(view.rig_for_slot(0).display_name, "ZAP!")
	assert_false("ZAP!" in view.rig_for_slot(1).display_name)
	view.render({"players": {0: [2.0, -1.0, 3], 1: [4.0, 4.0, 0]}, "zapped": -1})
	assert_false(ring.visible, "no holder, no ring")


func test_buzz_ring_tracks_the_electrified_player() -> void:
	view.render({"players": {0: [2.0, -1.0, 3], 1: [4.0, 4.0, 0]}, "zapped": 0})
	var buzz: MeshInstance3D = view.arena.get_node("BuzzRing")
	assert_true(buzz.visible)
	assert_almost_eq(buzz.position.x, 2.0, 0.001)
	assert_almost_eq(buzz.position.z, -1.0, 0.001)
	view.render({"players": {0: [2.0, -1.0, 3], 1: [4.0, 4.0, 0]}, "zapped": -1})
	assert_false(buzz.visible, "no holder, no buzz ring")


func test_storm_cloud_tracks_the_electrified_player() -> void:
	view.render({"players": {0: [2.0, -1.0, 3], 1: [4.0, 4.0, 0]}, "zapped": 0})
	var cloud: Node3D = view.arena.get_node("StormCloud")
	assert_true(cloud.visible)
	assert_almost_eq(cloud.position.x, 2.0, 0.001)
	assert_almost_eq(cloud.position.z, -1.0, 0.001)
	view.render({"players": {0: [2.0, -1.0, 3], 1: [4.0, 4.0, 0]}, "zapped": -1})
	assert_false(cloud.visible, "no holder, no storm cloud")


func test_floor_sparks_track_the_electrified_player() -> void:
	view.render({"players": {0: [2.0, -1.0, 3], 1: [4.0, 4.0, 0]}, "zapped": 0})
	for i in 5:
		var node: MeshInstance3D = view.arena.get_node("FloorSpark%d" % i)
		assert_true(node.visible, "spark %d visible when zapped" % i)
	view.render({"players": {0: [2.0, -1.0, 3], 1: [4.0, 4.0, 0]}, "zapped": -1})
	for i in 5:
		var node: MeshInstance3D = view.arena.get_node("FloorSpark%d" % i)
		assert_false(node.visible, "spark %d hidden when no zap" % i)


func test_coins_ride_the_nameplate() -> void:
	view.render({"players": {0: [0.0, 0.0, 7], 1: [1.0, 1.0, 2]}, "zapped": 1})
	assert_string_contains(view.rig_for_slot(0).display_name, "7")
	assert_string_contains(view.rig_for_slot(1).display_name, "2")


func test_zap_changing_hands_requests_a_shake() -> void:
	watch_signals(view)
	view.render({"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zapped": 0})
	assert_signal_not_emitted(view, "shake_requested", "seeding snapshot stays calm")
	view.render({"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zapped": 1})
	assert_signal_emitted(view, "shake_requested")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.zapped, -1)
	assert_false(view.arena.get_node("ZapRing").visible)


## M13-09 + #1153: the hand-off fires bursts at both ends AND spawns a visible
## electric beam (BoxMesh) plus its self-free timer.
func test_tag_fires_bursts_and_beam_on_handoff() -> void:
	view.render({"players": {0: [0.0, 0.0, 0], 1: [3.0, 0.0, 0]}, "zapped": 0})
	var before: int = view.arena.get_child_count()
	view.render({"players": {0: [0.0, 0.0, 0], 1: [3.0, 0.0, 0]}, "zapped": 1})
	# 2 CPUParticles3D bursts + 1 beam MeshInstance3D + 1 Timer = 4 new children.
	var added: int = view.arena.get_child_count() - before
	assert_eq(added, 4, "2 bursts + 1 beam + 1 timer on hand-off")


func test_ring_throbs_across_snapshots() -> void:
	view.render({"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zapped": 0})
	var ring: MeshInstance3D = view.arena.get_node("ZapRing")
	var scale_a: float = ring.scale.x
	view.render({"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zapped": 0})
	assert_ne(ring.scale.x, scale_a, "the crackle pulses with the snapshot cadence")


func test_buzz_ring_buzzes_independently() -> void:
	view.render({"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zapped": 0})
	var ring: MeshInstance3D = view.arena.get_node("ZapRing")
	var buzz: MeshInstance3D = view.arena.get_node("BuzzRing")
	var ring_scale_a: float = ring.scale.x
	var buzz_scale_a: float = buzz.scale.x
	view.render({"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zapped": 0})
	# Both rings pulse, but at different rates — they should differ.
	assert_ne(ring.scale.x, buzz.scale.x, "zap ring and buzz ring pulse at different frequencies")


func test_mood_returns_dark_electric() -> void:
	# The view overrides _mood to return a dark blue-grey for the electric arena.
	var mood: Color = view._mood()
	assert_lt(mood.r, 0.2, "dark red channel")
	assert_lt(mood.g, 0.2, "dark green channel")
	assert_gt(mood.b, 0.15, "blue-ish channel")
