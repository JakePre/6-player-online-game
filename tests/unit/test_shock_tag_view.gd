extends GutTest
## Shock Tag client view (M10-03): renders replicated snapshots in the shared
## iso-arena without simulating anything locally.

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


## M13-09: the hand-off arcs at both ends, and the carrier ring throbs.
func test_tag_fires_bursts_at_both_ends() -> void:
	view.render({"players": {0: [0.0, 0.0, 0], 1: [3.0, 0.0, 0]}, "zapped": 0})
	var before: int = view.arena.get_child_count()
	view.render({"players": {0: [0.0, 0.0, 0], 1: [3.0, 0.0, 0]}, "zapped": 1})
	assert_eq(view.arena.get_child_count(), before + 2, "old carrier + new carrier both burst")


func test_ring_throbs_across_snapshots() -> void:
	view.render({"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zapped": 0})
	var ring: MeshInstance3D = view.arena.get_node("ZapRing")
	var scale_a: float = ring.scale.x
	view.render({"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zapped": 0})
	assert_ne(ring.scale.x, scale_a, "the crackle pulses with the snapshot cadence")
