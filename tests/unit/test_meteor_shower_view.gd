extends GutTest
## Meteor Shower client view (M10-01): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

const VIEW_SCENE := preload("res://src/minigames/meteor_shower/meteor_shower_view.tscn")

var view: MinigameView


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
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


## M13-07: rocks streak down in sync with the replicated timer, landings
## burst, knockdowns burst at the rig.
func test_meteors_fall_with_the_replicated_timer() -> void:
	view.render(
		{
			"players": {},
			"zone": [0.0, 0.0, 8.0],
			"meteors": [[2.0, -3.0, MeteorShower.METEOR_TELEGRAPH_SEC], [1.0, 1.0, 0.0]],
			"fallen": []
		}
	)
	var fresh: Node3D = view.arena.get_node("Meteor0")
	var landing: Node3D = view.arena.get_node("Meteor1")
	assert_true(fresh.visible)
	assert_almost_eq(fresh.position.y, view.METEOR_DROP_HEIGHT + 0.5, 0.001, "fresh = sky-high")
	assert_almost_eq(landing.position.y, 0.5, 0.001, "timer spent = at the ground")
	assert_false(view.arena.get_node("Meteor2").visible, "pool beyond snapshot hidden")


func test_landing_fires_impact_fx() -> void:
	view.render(
		{"players": {}, "zone": [0.0, 0.0, 8.0], "meteors": [[2.0, -3.0, 0.1]], "fallen": []}
	)
	var before: int = view.arena.get_child_count()
	view.render({"players": {}, "zone": [0.0, 0.0, 8.0], "meteors": [], "fallen": []})
	assert_eq(view.arena.get_child_count(), before + 2, "burst + dust at the crater")


func test_vanish_with_time_left_is_not_a_landing() -> void:
	view.render(
		{"players": {}, "zone": [0.0, 0.0, 8.0], "meteors": [[2.0, -3.0, 1.0]], "fallen": []}
	)
	var before: int = view.arena.get_child_count()
	view.render({"players": {}, "zone": [0.0, 0.0, 8.0], "meteors": [], "fallen": []})
	assert_eq(view.arena.get_child_count(), before, "no FX for a mid-air disappearance")


func test_knockdown_bursts_at_the_rig() -> void:
	view.render(
		{
			"players": {0: [0.0, 0.0], 1: [3.0, 3.0]},
			"zone": [0.0, 0.0, 8.0],
			"meteors": [],
			"fallen": []
		}
	)
	var before: int = view.arena.get_child_count()
	view.render(
		{"players": {0: [0.0, 0.0]}, "zone": [0.0, 0.0, 8.0], "meteors": [], "fallen": [[1]]}
	)
	assert_eq(view.arena.get_child_count(), before + 1, "one burst at the downed rig")


## M15: the view derives its floor/camera size from the lobby count with the
## same formula the sim uses, so the rendered arena matches the scaled one.
func test_arena_half_scales_with_lobby_size() -> void:
	assert_almost_eq(view._arena_half(), MeteorShower.ARENA_HALF, 0.001, "2 players = base arena")
	var big: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(big)
	var names := {}
	for i in 12:
		names[i] = "P%d" % (i + 1)
	big.setup(names, 0)
	assert_gt(big._arena_half(), MeteorShower.ARENA_HALF, "12 players get a bigger arena")
