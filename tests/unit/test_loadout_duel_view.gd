extends GutTest
## Loadout Duel client view (M14-01): renders replicated arena snapshots on
## the side-scroll base — stage, daises, projectiles, KO chrome, round HUD —
## without simulating anything locally.

const VIEW_SCENE := preload("res://src/minigames/loadout_duel/loadout_duel_view.tscn")

var view: SideScrollView


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(960.0, 540.0)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func _fighter(x: float, y: float, facing: int, flags: int, held: int) -> Array:
	return [x, y, facing, flags, held]


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"loadout_duel"),
		"res://src/minigames/loadout_duel/loadout_duel_view.tscn"
	)


func test_setup_builds_the_shared_stage() -> void:
	# One platform panel per solid + one-way rect from the sim's own layout.
	var expected := LoadoutDuel.solid_platforms().size() + LoadoutDuel.one_way_platforms().size()
	assert_eq(view._platform_nodes.size(), expected, "stage matches the sim geometry")


func test_render_places_rigs_and_greys_out_the_downed() -> void:
	(
		view
		. render(
			{
				"players":
				{
					0: _fighter(-2.0, 0.5, 1, 1, LoadoutDuel.Kind.BLASTER),
					1: _fighter(2.0, 0.5, -1, 0, LoadoutDuel.Kind.NONE),
				},
				"shots": [],
				"daises": [],
				"phase": LoadoutDuel.Phase.FIGHT,
				"sub_round": 0,
				"scores": {0: 0, 1: 0},
			}
		)
	)
	assert_eq(view.rig_for_slot(0).modulate, Color.WHITE, "the living render bright")
	assert_ne(view.rig_for_slot(1).modulate, Color.WHITE, "the downed are greyed")


func test_ko_edge_shakes_and_stings_once_seeded() -> void:
	watch_signals(view)
	var alive := {
		"players": {0: _fighter(0.0, 0.5, 1, 1, 0)},
		"shots": [],
		"daises": [],
		"phase": LoadoutDuel.Phase.FIGHT,
		"scores": {}
	}
	view.render(alive)
	assert_signal_not_emitted(view, "shake_requested", "seeding snapshot is calm")
	view.render(
		{
			"players": {0: _fighter(0.0, 0.5, 1, 0, 0)},
			"shots": [],
			"daises": [],
			"phase": LoadoutDuel.Phase.FIGHT,
			"scores": {}
		}
	)
	assert_signal_emitted(view, "shake_requested")
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"error"])


func test_hud_reflects_phase_and_scores() -> void:
	view.render(
		{
			"players": {},
			"shots": [],
			"daises": [],
			"phase": LoadoutDuel.Phase.FIGHT,
			"sub_round": 1,
			"scores": {0: 2}
		}
	)
	assert_string_contains(view._hud.text, "Round 2")
	assert_string_contains(view._hud.text, "FIGHT")
	assert_string_contains(view._hud.text, "Alice 2")


func test_render_tracks_daises_and_shots_for_drawing() -> void:
	view.render(
		{
			"players": {},
			"shots": [[1.0, 2.0, LoadoutDuel.Shot.BOLT]],
			"daises": [[3.0, 0.5, LoadoutDuel.Kind.HAMMER]],
			"phase": LoadoutDuel.Phase.FIGHT,
			"scores": {}
		}
	)
	assert_eq(view.shots.size(), 1)
	assert_eq(view.dais_states.size(), 1)
	assert_eq(int(view.dais_states[0][2]), LoadoutDuel.Kind.HAMMER)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.shots, [])
