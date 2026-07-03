extends GutTest
## Meteor Shower client view (M10-01): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/meteor_shower/meteor_shower_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"meteor_shower"),
		"res://src/minigames/meteor_shower/meteor_shower_view.tscn"
	)


func test_zone_disc_follows_snapshot() -> void:
	view.render({"players": {}, "zone": [0.0, 0.0, 6.5], "meteors": [], "fallen": []})
	var zone_node: MeshInstance3D = view.arena.get_node("Zone")
	assert_true(zone_node.visible)
	assert_almost_eq(zone_node.scale.x, 6.5, 0.001)


func test_telegraphs_grow_as_impact_nears() -> void:
	view.render(
		{
			"players": {},
			"zone": [0.0, 0.0, 8.0],
			"meteors": [[2.0, -3.0, MeteorShower.METEOR_TELEGRAPH_SEC], [1.0, 1.0, 0.0]],
			"fallen": []
		}
	)
	var fresh: MeshInstance3D = view.arena.get_node("Telegraph0")
	var landing: MeshInstance3D = view.arena.get_node("Telegraph1")
	assert_true(fresh.visible)
	assert_almost_eq(fresh.position.x, 2.0, 0.001)
	assert_almost_eq(fresh.scale.x, MeteorShower.METEOR_RADIUS * 0.5, 0.001, "fresh = half size")
	assert_almost_eq(landing.scale.x, MeteorShower.METEOR_RADIUS, 0.001, "landing = full size")
	assert_false(view.arena.get_node("Telegraph2").visible, "pool beyond snapshot stays hidden")
	view.render({"players": {}, "zone": [0.0, 0.0, 8.0], "meteors": [], "fallen": []})
	assert_false(fresh.visible, "landed meteors clear their marker")


func test_downed_player_collapses_and_dims() -> void:
	view.render(
		{
			"players": {0: [0.0, 0.0], 1: [1.0, 1.0]},
			"zone": [0.0, 0.0, 8.0],
			"meteors": [],
			"fallen": []
		}
	)
	view.render(
		{"players": {0: [0.0, 0.0]}, "zone": [0.0, 0.0, 8.0], "meteors": [], "fallen": [[1]]}
	)
	var rig: CharacterRig = view.rig_for_slot(1)
	assert_eq(rig.current_action(), &"ko")
	assert_eq(rig.player_color, view.ELIMINATED_COLOR)


func test_new_down_requests_screen_shake() -> void:
	watch_signals(view)
	view.render(
		{"players": {0: [0.0, 0.0]}, "zone": [0.0, 0.0, 8.0], "meteors": [], "fallen": [[1]]}
	)
	assert_signal_not_emitted(view, "shake_requested", "seeding snapshot stays calm")
	view.render({"players": {}, "zone": [0.0, 0.0, 8.0], "meteors": [], "fallen": [[1], [0]]})
	assert_signal_emitted(view, "shake_requested")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.meteors.size(), 0)
	assert_eq(view.fallen.size(), 0)
