extends GutTest
## Relay Sprint client view (M4-11): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/relay_sprint/relay_sprint_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"relay_sprint"),
		"res://src/minigames/relay_sprint/relay_sprint_view.tscn"
	)


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"lanes": {0: [[0], 0, 3.0, 0.5, false]},
				"track_len": 24.0,
				"hazards": [[7.0, 1.0]],
			}
		)
	)
	assert_eq(view.lanes.size(), 1)
	assert_eq(view.hazards, [[7.0, 1.0]])
	view.render({"lanes": {}, "track_len": 24.0, "hazards": []})
	assert_eq(view.lanes.size(), 0, "each snapshot fully replaces the last")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.lanes.size(), 0)
	assert_eq(view.hazards, [])


## M13-22: the leg index bumping fires a baton flash; the first snapshot
## seeds silently and a finished lane never flashes.
func test_leg_bump_fires_baton_flash() -> void:
	view.render({"lanes": {0: [[0, 1], 1, 5.0, 0.0, false]}, "hazards": []})
	assert_eq(view._flashes.size(), 0, "first sighting seeds silently")
	view.render({"lanes": {0: [[0, 1], 2, 0.0, 0.0, false]}, "hazards": []})
	assert_eq(view._flashes.size(), 1, "a handoff = one flash")
	assert_eq(int(view._flashes[0].lane), 0)


func test_finishing_does_not_flash() -> void:
	view.render({"lanes": {0: [[0, 1], 1, 23.0, 0.0, false]}, "hazards": []})
	view.render({"lanes": {0: [[0, 1], 2, 0.0, 0.0, true]}, "hazards": []})
	assert_eq(view._flashes.size(), 0, "crossing the finish is not a handoff")


func test_baton_flashes_expire() -> void:
	view.render({"lanes": {0: [[0, 1], 0, 5.0, 0.0, false]}, "hazards": []})
	view.render({"lanes": {0: [[0, 1], 1, 0.0, 0.0, false]}, "hazards": []})
	assert_eq(view._flashes.size(), 1)
	view._process(view.FLASH_DURATION + 0.05)
	assert_eq(view._flashes.size(), 0, "flashes free themselves after their lifetime")


func test_speed_tracks_same_leg_progress_delta() -> void:
	view.render({"lanes": {0: [[0, 1], 0, 2.0, 0.0, false]}, "hazards": []})
	assert_eq(float(view._speeds[0]), 0.0, "first sighting has no delta")
	view.render({"lanes": {0: [[0, 1], 0, 3.2, 0.0, false]}, "hazards": []})
	assert_almost_eq(float(view._speeds[0]), 1.2, 0.001)
	view.render({"lanes": {0: [[0, 1], 1, 0.0, 0.0, false]}, "hazards": []})
	assert_eq(float(view._speeds[0]), 0.0, "a leg change resets the speed baseline")
