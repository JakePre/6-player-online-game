extends GutTest
## Memory Match client view (M10-05): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/memory_match/memory_match_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"memory_match"),
		"res://src/minigames/memory_match/memory_match_view.tscn"
	)


func test_grid_replaces_the_default_floor() -> void:
	assert_not_null(view.arena.get_node("Pit"))
	assert_not_null(view.arena.get_node("Tile_0_0"))
	assert_null(view.arena.get_node_or_null("Floor"), "default kit floor replaced by the grid")


## #1144 GFX: the pit reads as a contained arena — an edge border and a
## continuous rising mist, not just an empty void.
func test_pit_has_a_border_and_mist() -> void:
	assert_not_null(view.arena.get_node("PitBorder"))
	assert_not_null(view.arena.get_node("PitMist"))


## #1144 GFX: a safe tile carries a star icon while lit; it hides the instant
## the tile reads dark again.
func test_safe_tile_shows_an_icon_only_while_lit() -> void:
	view.render(
		{"players": {}, "phase": MemoryMatch.Phase.SHOW, "safe_tiles": [0, 7], "fallen": []}
	)
	var lit_icon: Node3D = view.arena.get_node("Tile_0_0/Icon")
	var unlit_icon: Node3D = view.arena.get_node("Tile_1_0/Icon")
	assert_true(lit_icon.visible, "a lit safe tile shows its icon")
	assert_false(unlit_icon.visible, "a dark tile shows no icon")
	view.render({"players": {}, "phase": MemoryMatch.Phase.DARK, "safe_tiles": [], "fallen": []})
	assert_false(lit_icon.visible, "the icon hides once the tile goes dark")


func test_safe_tiles_light_up_only_while_showing() -> void:
	view.render(
		{"players": {}, "phase": MemoryMatch.Phase.SHOW, "safe_tiles": [0, 7], "fallen": []}
	)
	var lit: MeshInstance3D = view.arena.get_node("Tile_0_0")
	var unlit: MeshInstance3D = view.arena.get_node("Tile_1_0")
	assert_eq(lit.material_override, view._safe_material)
	assert_eq(unlit.material_override, view._dark_material)
	assert_string_contains(view.get_node("BannerLayer/PhaseLabel").text, view.SHOW_TEXT)
	view.render({"players": {}, "phase": MemoryMatch.Phase.DARK, "safe_tiles": [], "fallen": []})
	assert_eq(lit.material_override, view._dark_material, "everything uniform in the dark")
	assert_string_contains(view.get_node("BannerLayer/PhaseLabel").text, view.DARK_TEXT)


func test_failed_check_collapses_and_shakes() -> void:
	watch_signals(view)
	view.render(
		{
			"players": {0: [0.0, 0.0], 1: [1.0, 1.0]},
			"phase": MemoryMatch.Phase.SHOW,
			"safe_tiles": [0],
			"fallen": []
		}
	)
	assert_signal_not_emitted(view, "shake_requested")
	view.render(
		{
			"players": {0: [0.0, 0.0]},
			"phase": MemoryMatch.Phase.SHOW,
			"safe_tiles": [0],
			"fallen": [[1]]
		}
	)
	assert_signal_emitted(view, "shake_requested")
	assert_eq(view.rig_for_slot(1).current_action(), &"ko")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.safe_tiles.size(), 0)
	assert_eq(view.phase, MemoryMatch.Phase.SHOW)


## M13-12: the pattern landing sparkles over every safe tile; drops splash.
## #1144: SHOW -> DARK is no longer quiet either — a blackout puff fires once
## per tile that WAS safe (the wire blanks safe_tiles to [] once dark, #586
## no peeking, so the puff must use the last-known safe set, not the current
## empty one).
func test_reveal_wave_sparkles_on_dark_to_show() -> void:
	view.render(
		{"players": {}, "phase": MemoryMatch.Phase.SHOW, "safe_tiles": [0, 1], "fallen": []}
	)
	var before: int = view.arena.get_child_count()
	view.render({"players": {}, "phase": MemoryMatch.Phase.DARK, "safe_tiles": [], "fallen": []})
	assert_eq(view.arena.get_child_count(), before + 2, "one blackout puff per tile going dark")
	var after_dark: int = view.arena.get_child_count()
	view.render(
		{"players": {}, "phase": MemoryMatch.Phase.SHOW, "safe_tiles": [3, 8, 12], "fallen": []}
	)
	assert_eq(view.arena.get_child_count(), after_dark + 3, "one sparkle per safe tile on reveal")


func test_drop_splashes_into_the_pit() -> void:
	view.render(
		{"players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "phase": 0, "safe_tiles": [0], "fallen": []}
	)
	var before: int = view.arena.get_child_count()
	view.render({"players": {0: [0.0, 0.0]}, "phase": 0, "safe_tiles": [0], "fallen": [[1]]})
	assert_eq(view.arena.get_child_count(), before + 1, "splash where they dropped")


## #586 clarity: the SHOW banner names the objective, the round, and how many
## safe tiles to remember (the count is safe to show here — the tiles are lit).
func test_show_banner_carries_round_and_safe_count() -> void:
	view.render(
		{
			"players": {},
			"phase": MemoryMatch.Phase.SHOW,
			"safe_tiles": [0, 7, 14],
			"fallen": [],
			"round": 2
		}
	)
	var text: String = view.get_node("BannerLayer/PhaseLabel").text
	assert_string_contains(text, "Round 3", "1-based round for players")
	assert_string_contains(text, "3 safe", "how many tiles to remember")
	assert_string_contains(text, "GREEN", "names the green safe tiles, not a 'pattern'")


## The count is not shown in the dark — that would be a memory-peek.
func test_dark_banner_omits_the_safe_count() -> void:
	view.render(
		{"players": {}, "phase": MemoryMatch.Phase.DARK, "safe_tiles": [], "fallen": [], "round": 0}
	)
	assert_string_contains(view.get_node("BannerLayer/PhaseLabel").text, view.DARK_TEXT)
	assert_false(
		view.get_node("BannerLayer/PhaseLabel").text.contains("safe)"), "no count while dark"
	)


## The safe tiles pulse during SHOW so they read as the focal "go here".
func test_safe_tiles_pulse_during_show() -> void:
	view.render({"players": {}, "phase": MemoryMatch.Phase.SHOW, "safe_tiles": [0], "fallen": []})
	view._process(0.0)
	var glow: float = view._safe_material.emission_energy_multiplier
	assert_between(glow, view.SAFE_GLOW_MIN, view.SAFE_GLOW_MAX, "pulse stays in range")


func _p(x: float, y: float, act_seq: int, cd: float) -> Array:
	return [x, y, act_seq, cd]


## #784: the shove swing plays once when the sim's act_seq ticks, and a cooldown
## ring appears while the player is cooling.
func test_shove_swing_plays_once_and_shows_a_cooldown_ring() -> void:
	view.render(
		{"players": {0: _p(0.0, 0.0, 0, 0.0)}, "phase": MemoryMatch.Phase.DARK, "fallen": []}
	)
	view.render(
		{"players": {0: _p(0.0, 0.0, 1, 1.5)}, "phase": MemoryMatch.Phase.DARK, "fallen": []}
	)
	assert_eq(
		view.rig_for_slot(0).current_action(), &"attack", "the swing fires on the act_seq tick"
	)
	var ring: MeshInstance3D = view.rig_for_slot(0).get_node_or_null("CooldownRing")
	assert_not_null(ring, "a cooldown ring appears while cooling")
	assert_true(ring.visible)
	view.render(
		{"players": {0: _p(0.0, 0.0, 1, 0.0)}, "phase": MemoryMatch.Phase.DARK, "fallen": []}
	)
	assert_false(ring.visible, "the ring hides once the shove is ready again")


## #784: a downed player's tile cracks and both the tile and the rig sink into
## the pit, rather than the rig just greying in place.
func test_failed_tile_cracks_and_the_loser_falls() -> void:
	view.render(
		{"players": {0: _p(0.0, 0.0, 0, 0.0)}, "phase": MemoryMatch.Phase.DARK, "fallen": []}
	)
	var rig: CharacterRig = view.rig_for_slot(0)
	var tile_y_before: float = view._tile_nodes[view.tile_index_at(rig.position)].position.y
	view.render({"players": {}, "phase": MemoryMatch.Phase.DARK, "fallen": [[0]]})
	var tile: MeshInstance3D = view._tile_nodes[view.tile_index_at(rig.position)]
	assert_eq(tile.material_override, view._cracked_material, "the failed tile cracks")
	var rig_y_before: float = rig.position.y
	view._process(0.2)
	assert_lt(rig.position.y, rig_y_before, "the loser sinks into the pit")
	assert_lt(tile.position.y, tile_y_before, "the tile drops away")


## #784: when the next round shows, the pit fills back in for the survivors.
func test_tiles_reform_when_the_next_round_shows() -> void:
	view.render(
		{"players": {0: _p(0.0, 0.0, 0, 0.0)}, "phase": MemoryMatch.Phase.DARK, "fallen": []}
	)
	var tile: MeshInstance3D = view._tile_nodes[view.tile_index_at(view.rig_for_slot(0).position)]
	view.render({"players": {}, "phase": MemoryMatch.Phase.DARK, "fallen": [[0]]})
	view._process(0.5)  # let it start dropping
	assert_lt(tile.position.y, view.TILE_HOME_Y, "tile has dropped")
	view.render(
		{"players": {}, "phase": MemoryMatch.Phase.SHOW, "safe_tiles": [1], "fallen": [[0]]}
	)
	assert_almost_eq(tile.position.y, view.TILE_HOME_Y, 0.001, "the floor reforms next round")
