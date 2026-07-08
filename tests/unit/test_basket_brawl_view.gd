extends GutTest
## Basket Brawl client view (M10-09): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/basket_brawl/basket_brawl_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob", 2: "Carol", 3: "Dave"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"basket_brawl"),
		"res://src/minigames/basket_brawl/basket_brawl_view.tscn"
	)


func test_setup_builds_arena_ball_and_hoops() -> void:
	assert_not_null(view.arena)
	assert_not_null(view.rig_for_slot(0))
	assert_not_null(view.arena.get_node("Ball"))
	assert_not_null(view.arena.get_node("Hoop0"))
	assert_not_null(view.arena.get_node("Hoop1"))


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"players": {0: [1.0, 2.0, 1]},
				"ball": [1.0, 2.0, 0],
				"scores": [1, 0],
				"teams": [[0, 1], [2, 3]],
				"hoops": [[-8.0, 0.0], [8.0, 0.0]],
			}
		)
	)
	assert_eq(view.players.size(), 1)
	assert_eq(view.ball, [1.0, 2.0, 0])
	assert_eq(view.scores, [1, 0])
	view.render({"players": {}, "ball": [0.0, 0.0, -1], "scores": [1, 1], "teams": []})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_ball_rides_carrier_and_sits_on_floor_loose() -> void:
	view.render({"players": {}, "ball": [3.0, -2.0, 0], "scores": [0, 0], "teams": []})
	var ball: MeshInstance3D = view.arena.get_node("Ball")
	assert_almost_eq(ball.position.x, 3.0, 0.001)
	assert_almost_eq(ball.position.y, view.CARRY_HEIGHT, 0.001, "held ball rides high")
	view.render({"players": {}, "ball": [3.0, -2.0, -1], "scores": [0, 0], "teams": []})
	assert_almost_eq(ball.position.y, view.BALL_RADIUS, 0.001, "loose ball sits on the floor")


func test_rig_follows_player_snapshot() -> void:
	view.render({"players": {0: [4.0, -2.0, 0]}, "ball": [0.0, 0.0, -1], "scores": [0, 0]})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 4.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)


func test_dunk_bursts_at_the_attacked_hoop() -> void:
	var base := {
		"players": {},
		"ball": [0.0, 0.0, -1],
		"teams": [[0, 1], [2, 3]],
		"hoops": [[-8.0, 0.0], [8.0, 0.0]],
	}
	var first := base.duplicate()
	first["scores"] = [0, 0]
	view.render(first)
	var before: int = view.arena.get_child_count()
	var second := base.duplicate()
	second["scores"] = [1, 0]
	view.render(second)
	assert_eq(view.arena.get_child_count(), before + 1, "a dunk = one burst")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.scores, [0, 0])


## Signature cues (#728): a dunk is heard from your own team's perspective —
## `bell` (docs/AUDIO_GUIDE.md's own worked example) for your team scoring,
## `error` for the opposing team (slot 0 is my_slot, team 0, per before_each).
func test_own_team_dunk_plays_bell_enemy_dunk_plays_error() -> void:
	var base := {
		"players": {},
		"ball": [0.0, 0.0, -1],
		"teams": [[0, 1], [2, 3]],
		"hoops": [[-8.0, 0.0], [8.0, 0.0]],
	}
	watch_signals(view)
	var seed := base.duplicate()
	seed["scores"] = [0, 0]
	view.render(seed)
	var own_score := base.duplicate()
	own_score["scores"] = [1, 0]
	view.render(own_score)
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"bell"], "my team scored")
	var enemy_score := base.duplicate()
	enemy_score["scores"] = [1, 1]
	view.render(enemy_score)
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"error"], "the enemy scored")


## A shove popping the ball loose is heard by whoever lost it.
func test_fumble_plays_bump_for_the_player_who_lost_the_ball() -> void:
	watch_signals(view)
	view.render({"players": {}, "ball": [0.0, 0.0, 0], "scores": [0, 0], "teams": [[0, 1], [2, 3]]})
	view.render(
		{"players": {}, "ball": [0.0, 0.0, -1], "scores": [0, 0], "teams": [[0, 1], [2, 3]]}
	)
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"bump"], "my ball popped loose")
