extends GutTest
## Storm Court client view (#936): renders replicated snapshots — the
## shrinking court + #583 telegraph band, state-colored balls, strike
## telegraphs, elimination hiding, and the lives HUD — without simulating
## anything locally.

const VIEW_SCENE: PackedScene = preload("res://src/finale/storm_court_view.tscn")

var view: MinigameView


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


## players entry: [x, y, fx, fy, lives, holding, invuln, hit_seq, catch_seq]
func _snapshot(players: Dictionary, extra := {}) -> Dictionary:
	var snap := {
		"radius": StormCourt.START_RADIUS,
		"shrink_in": StormCourt.SHRINK_STAGE_SEC,
		"players": players,
		"balls": [],
		"strikes": [],
		"eliminated": [],
	}
	snap.merge(extra, true)
	return snap


func test_setup_builds_court_telegraph_and_ball_pool() -> void:
	assert_not_null(view.arena.get_node("Court"))
	var telegraph: MeshInstance3D = view.arena.get_node("ShrinkTelegraph")
	assert_false(telegraph.visible, "no warn at the whistle")
	assert_eq(view._ball_pool.size(), StormCourt.ball_count_for(2))


func test_court_tracks_radius_and_telegraph_warns_before_a_stage() -> void:
	view.render(_snapshot({}, {"radius": 6.0, "shrink_in": 1.0}))
	assert_eq((view._platform_mesh as CylinderMesh).top_radius, 6.0)
	assert_true(
		(view.arena.get_node("ShrinkTelegraph") as MeshInstance3D).visible,
		"inside the warn window the doomed band lights (#583)"
	)
	view.render(_snapshot({}, {"radius": 6.0, "shrink_in": 8.0}))
	assert_false((view.arena.get_node("ShrinkTelegraph") as MeshInstance3D).visible)


func test_eliminated_players_hide_and_survivors_track() -> void:
	view.render(_snapshot({0: [2.0, 1.0, 1.0, 0.0, 2, 0, 0.0, 0, 0]}, {"eliminated": [1]}))
	assert_true(view.rig_for_slot(0).visible)
	assert_almost_eq(view.rig_for_slot(0).position.x, 2.0, 0.001)
	assert_false(view.rig_for_slot(1).visible, "out of the royale = off the court")


func test_hit_and_catch_sequences_cue_once() -> void:
	view.render(_snapshot({0: [0.0, 0.0, 1.0, 0.0, 2, 0, 0.0, 0, 0]}))
	watch_signals(view)
	view.render(_snapshot({0: [0.0, 0.0, 1.0, 0.0, 1, 0, 1.5, 1, 0]}))
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"hit_heavy"], "my hit")
	view.render(_snapshot({0: [0.0, 0.0, 1.0, 0.0, 2, 1, 0.0, 1, 1]}))
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"bell"], "my catch")


func test_balls_render_by_state() -> void:
	(
		view
		. render(
			_snapshot(
				{},
				{
					"balls":
					[
						[1.0, 0.0, StormCourt.BallState.LOOSE, -1],
						[2.0, 0.0, StormCourt.BallState.FLYING, 0],
					]
				}
			)
		)
	)
	assert_true(view._ball_pool[0].visible)
	assert_true(view._ball_pool[1].visible)
	assert_gt(view._ball_pool[1].position.y, view._ball_pool[0].position.y, "flying rides higher")


func test_strikes_show_from_the_pool() -> void:
	view.render(_snapshot({}, {"strikes": [[3.0, 2.0, 0.8]]}))
	assert_true(view._strike_pool[0].visible)
	assert_false(view._strike_pool[1].visible)
	view.render(_snapshot({}))
	assert_false(view._strike_pool[0].visible, "landed strikes clear")
