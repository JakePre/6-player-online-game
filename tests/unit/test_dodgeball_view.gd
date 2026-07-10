extends GutTest
## Dodgeball client view (#791): renders replicated snapshots in the shared
## iso-arena — rigs, balls, the team-split court, KO tumbles, and the catch
## flash — without simulating anything locally.

const VIEW_SCENE := preload("res://src/minigames/dodgeball/dodgeball_view.tscn")

var view: MinigameView


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob", 2: "Cara", 3: "Dan"}, 0)


func _player(x: float, y: float, holding := 0, team := -1) -> Array:
	return [x, y, 1.0, 0.0, holding, team]


func _ball(x: float, y: float, state: int, holder := -1) -> Array:
	return [x, y, state, holder]


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"dodgeball"),
		"res://src/minigames/dodgeball/dodgeball_view.tscn"
	)


func test_rig_follows_player_snapshot() -> void:
	view.render({"players": {0: _player(3.0, -2.0)}, "balls": [], "team_mode": false})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_true(rig.visible)
	assert_almost_eq(rig.position.x, 3.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)


func test_center_line_and_tints_only_in_team_mode() -> void:
	view.render({"players": {}, "balls": [], "team_mode": false})
	assert_false(view._center_line.visible, "no split line in FFA")
	view.render({"players": {}, "balls": [], "team_mode": true, "teams": [[0, 1], [2, 3]]})
	assert_true(view._center_line.visible, "the split reads in team mode")
	assert_true(view._side_tints[0].visible)


func test_balls_render_and_pool_hides_surplus() -> void:
	(
		view
		. render(
			{
				"players": {0: _player(0.0, 0.0)},
				"balls":
				[
					_ball(1.0, 2.0, Dodgeball.BallState.LOOSE),
					_ball(-1.0, 0.0, Dodgeball.BallState.FLYING)
				],
				"team_mode": false,
			}
		)
	)
	assert_true(view._ball_pool[0].visible)
	assert_true(view._ball_pool[1].visible)
	view.render(
		{"players": {}, "balls": [_ball(0.0, 0.0, Dodgeball.BallState.LOOSE)], "team_mode": false}
	)
	assert_true(view._ball_pool[0].visible)
	assert_false(view._ball_pool[1].visible, "the surplus ball node hides, not freed")


func test_held_ball_floats_over_its_holder() -> void:
	(
		view
		. render(
			{
				"players": {0: _player(2.0, 0.0, 1)},
				"balls": [_ball(2.0, 0.0, Dodgeball.BallState.HELD, 0)],
				"team_mode": false,
			}
		)
	)
	assert_gt(view._ball_pool[0].position.y, 1.0, "a carried ball rides above the rig")


func test_new_elimination_shakes_and_ko_tumbles() -> void:
	watch_signals(view)
	view.render(
		{
			"players": {0: _player(0.0, 0.0), 1: _player(1.0, 1.0)},
			"balls": [],
			"team_mode": false,
			"fallen": []
		}
	)
	assert_signal_not_emitted(view, "shake_requested", "the seeding snapshot stays calm")
	view.render(
		{"players": {0: _player(0.0, 0.0)}, "balls": [], "team_mode": false, "fallen": [[1]]}
	)
	assert_signal_emitted(view, "shake_requested")


func test_catch_flashes_the_event_banner() -> void:
	# A ball flips FLYING -> HELD with a live holder: that's a catch.
	(
		view
		. render(
			{
				"players": {0: _player(0.0, 0.0), 1: _player(3.0, 0.0)},
				"balls": [_ball(2.0, 0.0, Dodgeball.BallState.FLYING, 0)],
				"team_mode": false,
				"fallen": [],
			}
		)
	)
	assert_false(view._event_label.visible)
	(
		view
		. render(
			{
				"players": {1: _player(3.0, 0.0, 1)},
				"balls": [_ball(3.0, 0.0, Dodgeball.BallState.HELD, 1)],
				"team_mode": false,
				"fallen": [[0]],
			}
		)
	)
	assert_true(view._event_label.visible, "CAUGHT! flashes on the reflect")
	assert_string_contains(view._event_label.text, "CAUGHT")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.ball_states.size(), 0)
