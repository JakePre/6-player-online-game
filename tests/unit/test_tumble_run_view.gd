extends GutTest
## Tumble Run client view (M14-09): renders replicated climb snapshots on
## the side-scroll base — laddered stage, crumble ledges shown only while
## solid, boulders, stun/summit chrome — without simulating anything.

const VIEW_SCENE := preload("res://src/minigames/tumble_run/tumble_run_view.tscn")

var view: SideScrollView


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720.0, 720.0)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func _climber(x: float, y: float, facing: int, flags: int) -> Array:
	return [x, y, facing, flags]


func _solid_crumble() -> Array:
	var out: Array = []
	for i in TumbleRun.LEDGE_COUNT:
		out.append(true)
	return out


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"tumble_run"),
		"res://src/minigames/tumble_run/tumble_run_view.tscn"
	)


func test_setup_builds_the_ladder_and_crumble_panels() -> void:
	var base := TumbleRun.solid_platforms().size() + TumbleRun.ledges().size()
	assert_eq(view._platform_nodes.size(), base, "floor + summit + every ledge")
	assert_eq(
		view._crumble_nodes.size(), TumbleRun._crumble_indices().size(), "one panel per crumbler"
	)


func test_crumble_panel_hides_when_the_ledge_is_gone() -> void:
	var index: int = TumbleRun._crumble_indices()[0]
	var state := _solid_crumble()
	view.render({"players": {}, "boulders": [], "crumble": state, "standings": []})
	assert_true(view._crumble_nodes[index].visible, "solid ledges show")
	state[index] = false
	view.render({"players": {}, "boulders": [], "crumble": state, "standings": []})
	assert_false(view._crumble_nodes[index].visible, "a crumbled ledge disappears")


func test_stun_and_summit_tint_the_climber() -> void:
	(
		view
		. render(
			{
				"players":
				{
					0: _climber(0.0, 5.0, 1, 1),  # stunned
					1: _climber(1.0, TumbleRun.GOAL_HEIGHT, 1, 2),  # summited
				},
				"boulders": [],
				"crumble": _solid_crumble(),
				"standings": [1, 0]
			}
		)
	)
	assert_ne(view.rig_for_slot(0).modulate, Color.WHITE, "stunned is tinted")
	assert_ne(view.rig_for_slot(1).modulate, Color.WHITE, "summited is tinted")
	assert_ne(view.rig_for_slot(0).modulate, view.rig_for_slot(1).modulate, "distinctly")


func test_summit_edge_chimes_once_seeded() -> void:
	watch_signals(view)
	var base := {"boulders": [], "crumble": _solid_crumble(), "standings": []}
	var climbing := base.duplicate()
	climbing["players"] = {0: _climber(0.0, 10.0, 1, 0)}
	view.render(climbing)
	assert_signal_not_emitted(view, "shake_requested", "seeding snapshot is calm")
	var topped := base.duplicate()
	topped["players"] = {0: _climber(0.0, TumbleRun.GOAL_HEIGHT, 1, 2)}
	view.render(topped)
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"confirm"])


func test_render_tracks_boulders_and_leader_hud() -> void:
	view.render(
		{"players": {}, "boulders": [[2.0, 12.0]], "crumble": _solid_crumble(), "standings": [1, 0]}
	)
	assert_eq(view.boulders.size(), 1)
	assert_string_contains(view._hud.text, "Bob", "the leader shows in the HUD")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.boulders, [])
