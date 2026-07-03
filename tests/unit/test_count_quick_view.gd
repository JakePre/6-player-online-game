extends GutTest
## Count Quick client view (M10-08): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/count_quick/count_quick_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"count_quick"),
		"res://src/minigames/count_quick/count_quick_view.tscn"
	)


func test_swarm_shows_during_flash_and_clears() -> void:
	view.render(
		{
			"players": {},
			"phase": CountQuick.Phase.FLASH,
			"swarm": [[1.0, 2.0], [3.0, -1.0]],
			"pads": []
		}
	)
	assert_true(view.arena.get_node("Swarm0").visible)
	assert_false(view.arena.get_node("Swarm2").visible)
	assert_eq(view.get_node("PhaseLabel").text, view.FLASH_TEXT)
	view.render({"players": {}, "phase": CountQuick.Phase.ANSWER, "swarm": [], "pads": []})
	assert_false(view.arena.get_node("Swarm0").visible, "the swarm vanishes with the flash")
	assert_eq(view.get_node("PhaseLabel").text, view.ANSWER_TEXT)


func test_pads_show_their_values() -> void:
	view.render(
		{
			"players": {},
			"phase": CountQuick.Phase.ANSWER,
			"swarm": [],
			"pads": [[-6.0, -6.0, 14], [6.0, -6.0, 12], [-6.0, 6.0, 16], [6.0, 6.0, 11]]
		}
	)
	var pad: Node3D = view.arena.get_node("Pad0")
	assert_true(pad.visible)
	assert_almost_eq(pad.position.x, -6.0, 0.001)
	assert_eq((pad.get_node("Value") as Label3D).text, "14")


func test_locked_players_show_it_on_the_nameplate() -> void:
	view.render(
		{"players": {0: [0.0, 0.0, 3, 1], 1: [1.0, 1.0, 2, 0]}, "phase": 1, "swarm": [], "pads": []}
	)
	assert_string_contains(view.rig_for_slot(0).display_name, "LOCKED")
	assert_false("LOCKED" in view.rig_for_slot(1).display_name)
	assert_string_contains(view.rig_for_slot(0).display_name, "3")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.swarm.size(), 0)
	assert_eq(view.pads.size(), 0)
