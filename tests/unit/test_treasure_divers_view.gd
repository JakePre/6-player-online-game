extends GutTest
## Treasure Divers client view (M10-04): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView


func _player(x: float, y: float, coin_count: int, dive: int, air: float, stun: float) -> Array:
	return [x, y, coin_count, dive, air, stun]


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/treasure_divers/treasure_divers_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"treasure_divers"),
		"res://src/minigames/treasure_divers/treasure_divers_view.tscn"
	)


func test_surfaced_rigs_swim_high_and_divers_sink() -> void:
	assert_not_null(view.arena.get_node("WaterSurface"))
	view.render(
		{
			"players":
			{0: _player(1.0, 2.0, 0, 0, 1.0, 0.0), 1: _player(-1.0, -2.0, 0, 1, 0.5, 0.0)},
			"treasure": []
		}
	)
	assert_almost_eq(view.rig_for_slot(0).position.y, view.SURFACE_HEIGHT, 0.001, "swimmer on top")
	assert_almost_eq(view.rig_for_slot(1).position.y, 0.0, 0.001, "diver on the seabed")


## #235: air is a hovering bar fed from the replicated fraction; the ASCII
## meter no longer rides the nameplate.
func test_air_bar_tracks_the_replicated_fraction() -> void:
	view.render({"players": {0: _player(0.0, 0.0, 4, 1, 1.0, 0.0)}, "treasure": []})
	assert_string_contains(view.rig_for_slot(0).display_name, "4")
	assert_false("|" in view.rig_for_slot(0).display_name, "no ASCII meter on the plate")
	assert_almost_eq(float(view._air_seen[0]), 1.0, 0.001)
	assert_true(view._air_bars.has(0), "a bar exists for the slot")
	view.render({"players": {0: _player(0.0, 0.0, 4, 1, 0.35, 0.0)}, "treasure": []})
	assert_almost_eq(float(view._air_seen[0]), 0.35, 0.001)


func test_fresh_blackout_flinches_and_shakes() -> void:
	watch_signals(view)
	view.render({"players": {0: _player(0.0, 0.0, 0, 0, 0.1, 0.0)}, "treasure": []})
	assert_signal_not_emitted(view, "shake_requested")
	view.render({"players": {0: _player(0.0, 0.0, 0, 0, 0.0, 2.5)}, "treasure": []})
	assert_signal_emitted(view, "shake_requested")
	assert_eq(view.rig_for_slot(0).current_action(), &"hit")
	view.render({"players": {0: _player(0.0, 0.0, 0, 0, 0.0, 2.4)}, "treasure": []})
	assert_signal_emit_count(view, "shake_requested", 1, "ongoing stun does not re-shake")


func test_treasure_pool_tracks_snapshot() -> void:
	view.render({"players": {}, "treasure": [[3.0, -4.0]]})
	var coin: MeshInstance3D = view.arena.get_node("Treasure0")
	assert_true(coin.visible)
	assert_almost_eq(coin.position.x, 3.0, 0.001)
	assert_false(view.arena.get_node("Treasure1").visible)
	view.render({"players": {}, "treasure": []})
	assert_false(coin.visible, "collected treasure disappears")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.treasure.size(), 0)
