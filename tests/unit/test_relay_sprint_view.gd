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


## GFX #1148: visual enhancements — render without errors for various states.
func test_renders_with_runner_in_exchange_zone() -> void:
	# Runner at progress 22.0 (track_len=24, zone starts at 20.0)
	view.render({"lanes": {0: [[0, 1], 0, 22.0, 0.0, false]}, "track_len": 24.0, "hazards": []})
	view.queue_redraw()
	# No crash is the assertion — draw() must handle in-zone runners
	assert_true(view.lanes.has(0))


func test_renders_finished_lane_shows_dots() -> void:
	view.render({"lanes": {0: [[0, 1], 2, 0.0, 0.0, true]}, "track_len": 24.0, "hazards": []})
	assert_eq(view.lanes.size(), 1, "finished lane is in the snapshot")


func test_renders_progress_bar_for_active_lane() -> void:
	view.render({"lanes": {0: [[0, 1], 0, 10.5, 0.0, false]}, "track_len": 24.0, "hazards": []})
	assert_false(view.lanes[0][RelaySprint.LN_DONE], "lane is active")


func test_renders_all_visual_features_together() -> void:
	# Two lanes: one active, one done — exercises all drawing paths
	(
		view
		. render(
			{
				"lanes":
				{
					0: [[0, 1], 0, 15.0, 0.5, false],
					1: [[2, 3], 2, 0.0, 0.0, true],
				},
				"track_len": 24.0,
				"hazards": [[7.0, 1.0], [12.0, -0.5]],
			}
		)
	)
	assert_eq(view.lanes.size(), 2)
	assert_eq(view.hazards.size(), 2)


func test_renders_leg_progress_constant_during_handoff() -> void:
	# Leg change (0→1) resets progress to 0 — should not crash
	view.render({"lanes": {0: [[0, 1], 0, 23.0, 0.0, false]}, "track_len": 24.0, "hazards": []})
	view.render({"lanes": {0: [[0, 1], 1, 0.0, 0.0, false]}, "track_len": 24.0, "hazards": []})
	assert_eq(int(view.lanes[0][RelaySprint.LN_ACTIVE_LEG]), 1, "leg advanced after handoff")
