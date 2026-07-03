extends GutTest
## Bullseye Bowl client view (M10-07): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/bullseye_bowl/bullseye_bowl_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"bullseye_bowl"),
		"res://src/minigames/bullseye_bowl/bullseye_bowl_view.tscn"
	)


func test_setup_builds_a_lane_target_and_ball_per_player() -> void:
	assert_not_null(view.arena.get_node("Lane0"))
	assert_not_null(view.arena.get_node("Target1"))
	assert_false(view.arena.get_node("Ball0").visible, "no flight yet")


func test_target_slides_and_ball_rolls_with_the_snapshot() -> void:
	view.render({"players": {0: [0, 8, 0.5, 1.5], 1: [0, 8, -1.0, -0.5]}})
	var target: Node3D = view.arena.get_node("Target0")
	var lane_x: float = view._lanes[0].center_x
	assert_almost_eq(target.position.x, lane_x + 1.5, 0.001, "target offset from lane center")
	var ball: MeshInstance3D = view.arena.get_node("Ball0")
	assert_true(ball.visible)
	assert_almost_eq(ball.position.z, 0.0, 0.001, "halfway down the lane at t=0.5")
	assert_false(view.arena.get_node("Ball1").visible, "no flight for the idle player")


func test_score_and_balls_ride_the_nameplate() -> void:
	view.render({"players": {0: [12, 3, -1.0, 0.0]}})
	assert_string_contains(view.rig_for_slot(0).display_name, "12 pts")
	assert_string_contains(view.rig_for_slot(0).display_name, "3 balls")


func test_bullseye_jump_shakes_once() -> void:
	watch_signals(view)
	view.render({"players": {0: [3, 5, -1.0, 0.0]}})
	assert_signal_not_emitted(view, "shake_requested", "seeding snapshot stays calm")
	view.render({"players": {0: [4, 5, -1.0, 0.0]}})
	assert_signal_not_emitted(view, "shake_requested", "an outer-ring point is no fanfare")
	view.render({"players": {0: [9, 4, -1.0, 0.0]}})
	assert_signal_emitted(view, "shake_requested", "a bullseye rattles the screen")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
