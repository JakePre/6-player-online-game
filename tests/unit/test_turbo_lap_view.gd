extends GutTest
## Turbo Lap client view (M14-02): renders replicated race snapshots in the
## shared iso-arena — ribbon track, pads, box-karts, pooled shells/oils —
## without simulating anything locally.

const VIEW_SCENE := preload("res://src/minigames/turbo_lap/turbo_lap_view.tscn")

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func _kart(x: float, y: float, heading: float, item: int, bits: int) -> Array:
	return [x, y, heading, item, bits]


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"turbo_lap"),
		"res://src/minigames/turbo_lap/turbo_lap_view.tscn"
	)


func test_setup_builds_track_pads_and_karts() -> void:
	assert_not_null(view.arena.get_node("Track0"), "ribbon strips exist")
	assert_not_null(view.arena.get_node("Track%d" % (TurboLap.WAYPOINT_COUNT - 1)))
	assert_not_null(view.arena.get_node("StartLine"))
	assert_not_null(view.arena.get_node("ItemPad0"))
	assert_not_null(view.arena.get_node("Shell0"))
	assert_not_null(view.rig_for_slot(0).get_node("KartBody"), "every racer rides a kart")


func test_render_moves_rigs_and_dims_cooling_pads() -> void:
	(
		view
		. render(
			{
				"players": {0: _kart(3.0, -2.0, 0.0, 0, 0)},
				"shells": [],
				"oils": [],
				"pads": [[1.0, 1.0, 0], [2.0, 2.0, 1], [3.0, 3.0, 1]],
				"standings": [0, 1],
			}
		)
	)
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 3.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)
	var cooling: MeshInstance3D = view.arena.get_node("ItemPad0")
	var active: MeshInstance3D = view.arena.get_node("ItemPad1")
	assert_gt(cooling.transparency, 0.0, "a taken pad dims")
	assert_almost_eq(active.transparency, 0.0, 0.001, "a live pad glows")


func test_nameplate_carries_position_and_item() -> void:
	view.render({"players": {0: _kart(0.0, 0.0, 0.0, TurboLap.ITEM_SHELL, 0)}, "standings": [1, 0]})
	var plate: String = view.rig_for_slot(0).display_name
	assert_string_contains(plate, "P2", "second place reads P2")
	assert_string_contains(plate, "🐢", "the held shell shows")
	view.render({"players": {0: _kart(0.0, 0.0, 0.0, 0, 8)}, "standings": [0, 1]})
	assert_string_contains(view.rig_for_slot(0).display_name, "🏁", "finishers fly the flag")


func test_spin_fires_fx_and_sfx_once_seeded() -> void:
	watch_signals(view)
	view.render({"players": {0: _kart(0.0, 0.0, 0.0, 0, 1)}, "standings": []})
	assert_signal_not_emitted(view, "shake_requested", "seeding snapshot stays calm")
	view.render({"players": {0: _kart(0.0, 0.0, 0.0, 0, 0)}, "standings": []})
	view.render({"players": {0: _kart(0.0, 0.0, 0.0, 0, 1)}, "standings": []})
	assert_signal_emitted(view, "shake_requested")
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"powerdown"])


func test_shell_and_oil_pools_track_snapshot() -> void:
	view.render({"players": {}, "shells": [[2.0, 3.0]], "oils": [[4.0, 5.0]], "standings": []})
	var shell: MeshInstance3D = view.arena.get_node("Shell0")
	assert_true(shell.visible)
	assert_almost_eq(shell.position.x, 2.0, 0.001)
	assert_false(view.arena.get_node("Shell1").visible, "pool beyond snapshot hidden")
	assert_true(view.arena.get_node("Oil0").visible)
	view.render({"players": {}, "shells": [], "oils": [], "standings": []})
	assert_false(shell.visible, "a landed shell disappears")


## #785: the finish line crosses the track perpendicular to the racing
## direction — rotated to the track heading at the line, not axis-aligned.
func test_finish_line_crosses_perpendicular() -> void:
	var points := TurboLap.waypoints()
	var start: MeshInstance3D = view.arena.get_node("StartLine")
	var expected := -(points[1] - points[0]).angle()
	assert_almost_eq(start.rotation.y, expected, 0.001, "rotated to the track heading at the line")
	var strip: MeshInstance3D = view.arena.get_node("Track0")
	assert_almost_eq(
		start.rotation.y, strip.rotation.y, 0.001, "aligned with the ribbon at the line"
	)
	assert_almost_eq(
		(start.mesh as BoxMesh).size.z,
		TurboLap.TRACK_HALF_WIDTH * 2.0,
		0.001,
		"spans the full width"
	)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.standings, [])
