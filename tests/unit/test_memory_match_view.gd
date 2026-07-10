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
func test_reveal_wave_sparkles_on_dark_to_show() -> void:
	view.render(
		{"players": {}, "phase": MemoryMatch.Phase.SHOW, "safe_tiles": [0, 1], "fallen": []}
	)
	var before: int = view.arena.get_child_count()
	view.render({"players": {}, "phase": MemoryMatch.Phase.DARK, "safe_tiles": [], "fallen": []})
	assert_eq(view.arena.get_child_count(), before, "going dark is quiet")
	view.render(
		{"players": {}, "phase": MemoryMatch.Phase.SHOW, "safe_tiles": [3, 8, 12], "fallen": []}
	)
	assert_eq(view.arena.get_child_count(), before + 3, "one sparkle per safe tile on reveal")


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
