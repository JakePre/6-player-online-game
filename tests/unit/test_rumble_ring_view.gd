extends GutTest
## Rumble Ring client view (M10-17): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/rumble_ring/rumble_ring_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"rumble_ring"),
		"res://src/minigames/rumble_ring/rumble_ring_view.tscn"
	)


func test_render_replaces_state_and_updates_nameplates() -> void:
	(
		view
		. render(
			{
				"players": {0: [1.0, 2.0, 2, 6, 0, 0.0, 1.0, 0.0]},
				"coins": [[0.5, 0.5]],
				"events": [],
			}
		)
	)
	assert_eq(view.players.size(), 1)
	assert_eq(view.coins.size(), 1)
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_string_contains(rig.display_name, "♥2")
	assert_string_contains(rig.display_name, "⚔6")


func test_ko_event_plays_the_ko_action() -> void:
	(
		view
		. render(
			{
				"players": {0: [0.0, 0.0, 3, 0, 0, 0.0, 1.0, 0.0]},
				"coins": [],
				"events": [{"type": "ko", "slot": 0, "by": 1}],
			}
		)
	)
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_eq(rig.current_action(), &"ko")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.coins, [])
