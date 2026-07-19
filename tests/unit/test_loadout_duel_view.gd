extends GutTest
## Loadout Duel client view (M14-01): renders replicated arena snapshots on
## the side-scroll base — stage, daises, projectiles, KO chrome, round HUD —
## without simulating anything locally.

const VIEW_SCENE := preload("res://src/minigames/loadout_duel/loadout_duel_view.tscn")

var view: SideScrollView
var _saved_show_names := false


func before_each() -> void:
	_saved_show_names = MinigameView.show_names
	MinigameView.show_names = true  # #580: names off by default; this suite tests the name itself
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(960.0, 540.0)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func after_each() -> void:
	MinigameView.show_names = _saved_show_names


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
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"ko"])


## #1038: a duel hit is an instant KO, so the KO edge is where the shared hit
## reaction fires — the impact spark burst reads even as the rig greys out.
func test_ko_plays_the_shared_hit_reaction() -> void:
	var alive := {
		"players": {0: _fighter(0.0, 0.5, 1, 1, 0)},
		"shots": [],
		"daises": [],
		"phase": LoadoutDuel.Phase.FIGHT,
		"scores": {}
	}
	view.render(alive)
	var before := view._rig_layer.get_child_count()
	view.render(
		{
			"players": {0: _fighter(0.0, 0.5, 1, 0, 0)},
			"shots": [],
			"daises": [],
			"phase": LoadoutDuel.Phase.FIGHT,
			"scores": {}
		}
	)
	assert_true(view.is_hit_playing(0), "a KO fires the shared hit reaction")
	assert_gt(view._rig_layer.get_child_count(), before, "the impact spark burst spawns")


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


## #788: every pickup a dais can hand out carries a readable name and a color,
## so players can tell what each weapon does — not decode a bare color.
func test_every_pickup_has_a_distinct_name_and_color() -> void:
	var seen_names := {}
	for kind: int in LoadoutDuel.DAIS_KINDS:
		var name_text: String = view.kind_label(kind)
		assert_false(name_text.is_empty(), "kind %d has a readable name" % kind)
		assert_false(seen_names.has(name_text), "names are distinct (%s)" % name_text)
		seen_names[name_text] = true
		assert_true(view.KIND_COLORS.has(kind), "kind %d has a color too" % kind)
	assert_eq(view.kind_label(LoadoutDuel.Kind.NONE), "", "empty hands have no label")


## #788: a board of daises plus a held weapon all resolve to a name + color, so
## everything on screen is decodable (an empty pad stays label-less).
func test_rendered_pickups_all_resolve_to_a_name() -> void:
	(
		view
		. render(
			{
				"players": {0: _fighter(0.0, 0.5, 1, 3, LoadoutDuel.Kind.HAMMER)},
				"shots": [],
				"daises":
				[
					[3.0, 0.5, LoadoutDuel.Kind.BLASTER],
					[5.0, 2.6, LoadoutDuel.Kind.SHIELD],
					[-3.0, 0.5, LoadoutDuel.Kind.NONE],
				],
				"phase": LoadoutDuel.Phase.FIGHT,
				"scores": {0: 0}
			}
		)
	)
	assert_eq(view.dais_states.size(), 3, "all daises tracked for drawing")
	for dais: Array in view.dais_states:
		var kind := int(dais[LoadoutDuel.DS_KIND])
		if kind == LoadoutDuel.Kind.NONE:
			assert_eq(view.kind_label(kind), "", "an empty pad shows no name")
		else:
			assert_false(view.kind_label(kind).is_empty(), "a live pad names its weapon")
	assert_string_contains(
		view.kind_label(LoadoutDuel.Kind.HAMMER), "HAMMER", "held weapon reads too"
	)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.shots, [])
