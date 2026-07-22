extends GutTest
## Basket Brawl client view (M10-09): renders replicated snapshots in the
## shared iso-arena without simulating anything locally. Ball array is
## [x, y, holder, shot] (#803 added the shot-in-flight flag).

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


## #803: a real basketball + a raised hoop assembly per side (the tint disc
## reads which basket a team defends; the model is the actual hoop).
func test_setup_builds_arena_ball_and_hoops() -> void:
	assert_not_null(view.arena)
	assert_not_null(view.rig_for_slot(0))
	assert_not_null(view.arena.get_node("Ball"))
	assert_not_null(view.arena.get_node("Hoop0"))
	assert_not_null(view.arena.get_node("Hoop1"))
	assert_not_null(view.arena.get_node("HoopModel0"), "the raised hoop model (#803)")
	assert_not_null(view.arena.get_node("HoopModel1"))


## #1123 GFX: court-side benches down both sidelines and a floating 3D
## scoreboard above center court frame the arena as a gym.
func test_gfx_adds_benches_and_a_scoreboard() -> void:
	assert_not_null(view.arena.get_node("BenchN0"), "a bench on the near sideline")
	assert_not_null(view.arena.get_node("BenchP0"), "and one on the far sideline")
	var board: Node3D = view.arena.get_node("Scoreboard")
	assert_not_null(board, "the 3D scoreboard slab")
	assert_gt(board.position.y, 3.0, "floats above the court")
	var label: Label3D = view.arena.get_node("ScoreboardLabel")
	assert_not_null(label, "with a billboarded score label")
	assert_eq(label.billboard, BaseMaterial3D.BILLBOARD_ENABLED, "always faces the camera")


## #1123: the 3D scoreboard label mirrors the live score alongside the HUD.
func test_scoreboard_label_tracks_the_score() -> void:
	view.render({"players": {}, "ball": [0.0, 0.0, -1, 0], "scores": [3, 5], "teams": []})
	assert_eq((view.arena.get_node("ScoreboardLabel") as Label3D).text, "3 : 5")


## #929: the wood-court texture over the floor, plus painted lines so the
## court reads as a real basketball court rather than a plain tint.
func test_court_surface_wears_the_wood_texture() -> void:
	var surface: MeshInstance3D = view.arena.get_node("CourtSurface")
	var material := (surface.mesh as PlaneMesh).material as StandardMaterial3D
	assert_eq(material.albedo_texture, view.COURT_TEXTURE)


## #929: the basketball model reads small next to a full-size rig — scaled up.
func test_ball_is_scaled_up() -> void:
	assert_eq(view._ball_node.scale, Vector3.ONE * view.BALL_SCALE)


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"players": {0: [1.0, 2.0, 1]},
				"ball": [1.0, 2.0, 0, 0],
				"scores": [1, 0],
				"teams": [[0, 1], [2, 3]],
				"hoops": [[-8.0, 0.0], [8.0, 0.0]],
			}
		)
	)
	assert_eq(view.players.size(), 1)
	assert_eq(view.ball, [1.0, 2.0, 0, 0])
	assert_eq(view.scores, [1, 0])
	view.render({"players": {}, "ball": [0.0, 0.0, -1, 0], "scores": [1, 1], "teams": []})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_ball_dribbles_beside_carrier_and_sits_on_floor_loose() -> void:
	# #1037: a held ball DRIBBLES — bouncing between the floor and hand height
	# beside the carrier — rather than gluing overhead.
	view.render({"players": {}, "ball": [3.0, -2.0, 0, 0], "scores": [0, 0], "teams": []})
	var ball: Node3D = view.arena.get_node("Ball")
	# With no team data the dribble hand falls back to +x attack -> the side
	# offset lands on the arena z axis.
	assert_almost_ne(ball.position.z, -2.0, 0.01, "the dribble sits beside the carrier, not inside")
	assert_between(
		ball.position.y, view.BALL_RADIUS - 0.001, view.DRIBBLE_HEIGHT + 0.001, "dribble band"
	)
	view.render({"players": {}, "ball": [3.0, -2.0, -1, 0], "scores": [0, 0], "teams": []})
	assert_almost_eq(ball.position.y, view.BALL_RADIUS, 0.001, "loose ball sits on the floor")


## #1037: while the carrier charges a shot, the ball comes up to the set
## position overhead — the wind-up is readable across the court.
func test_charging_carrier_raises_the_ball_overhead() -> void:
	(
		view
		. render(
			{
				"players": {0: [3.0, -2.0, 1, 0.5]},
				"ball": [3.0, -2.0, 0, 0],
				"scores": [0, 0],
				"teams": [],
			}
		)
	)
	var ball: Node3D = view.arena.get_node("Ball")
	assert_almost_eq(ball.position.y, view.CARRY_HEIGHT, 0.001, "charging = ball raised to shoot")
	assert_almost_eq(ball.position.x, 3.0, 0.001, "raised ball rides the carrier, no side offset")


## #1037: both rims open toward the court. The .glb rim faces -z at rest, so
## facing is (-sin y, -cos y): the -x hoop needs y = -PI/2, the +x hoop +PI/2.
func test_hoops_face_the_court() -> void:
	var left: Node3D = view.arena.get_node("HoopModel0")
	var right: Node3D = view.arena.get_node("HoopModel1")
	assert_almost_eq(-sin(left.rotation.y), 1.0, 0.001, "the -x hoop opens toward +x (center)")
	assert_almost_eq(-sin(right.rotation.y), -1.0, 0.001, "the +x hoop opens toward -x (center)")


## #1037: the local player's charge drives the meter — hidden idle, visible
## and orange early, green inside the perfect-release window.
func test_charge_meter_mirrors_local_charge_and_greens_in_the_window() -> void:
	var bar: ProgressBar = view.get_node("ChargeBar")
	view.render({"players": {0: [0.0, 0.0, 1, 0.0]}, "ball": [0.0, 0.0, 0, 0], "scores": [0, 0]})
	assert_false(bar.visible, "no charge -> no meter")
	view.render({"players": {0: [0.0, 0.0, 1, 0.3]}, "ball": [0.0, 0.0, 0, 0], "scores": [0, 0]})
	assert_true(bar.visible, "charging -> meter shows")
	assert_almost_eq(bar.value, 30.0, 0.001)
	assert_eq(bar.modulate, view.METER_CHARGE_COLOR, "early charge reads orange")
	view.render({"players": {0: [0.0, 0.0, 1, 0.8]}, "ball": [0.0, 0.0, 0, 0], "scores": [0, 0]})
	assert_eq(bar.modulate, view.METER_SWEET_COLOR, "inside the window reads green")


## #1037: releasing from inside the sweet window (charge -> 0 with a shot in
## the air) flashes PERFECT!; a fumble that zeroes the charge does not.
func test_perfect_release_flashes_and_fumble_does_not() -> void:
	# The label lives on the shared overlay CanvasLayer — reach it directly.
	var label: Label = view._perfect_label
	view.render({"players": {0: [0.0, 0.0, 1, 0.8]}, "ball": [0.0, 0.0, 0, 0], "scores": [0, 0]})
	view.render({"players": {0: [0.0, 0.0, 0, 0.0]}, "ball": [0.0, 0.0, -1, 1], "scores": [0, 0]})
	assert_true(label.visible, "sweet-window release with the shot flying -> PERFECT!")
	label.visible = false
	view.render({"players": {0: [0.0, 0.0, 1, 0.8]}, "ball": [0.5, 0.0, 0, 0], "scores": [0, 0]})
	view.render({"players": {0: [0.0, 0.0, 0, 0.0]}, "ball": [0.5, 0.0, -1, 0], "scores": [0, 0]})
	assert_false(label.visible, "a fumble zeroes the charge with no shot -> no flash")


## #803: a shot in flight arcs above the floor — the ball climbs toward the
## raised rim rather than sliding along the ground like a loose ball.
func test_shot_in_flight_arcs_above_the_floor() -> void:
	view.render({"players": {}, "ball": [-6.0, 0.0, -1, 1], "scores": [0, 0], "teams": []})
	view.render({"players": {}, "ball": [2.0, 0.0, -1, 1], "scores": [0, 0], "teams": []})
	var ball: Node3D = view.arena.get_node("Ball")
	assert_gt(ball.position.y, view.BALL_RADIUS + 0.5, "the shot is airborne, not on the floor")


## #803: a shot that ends in flight with no score rebounded — it clangs (an
## extra FX child) rather than silently vanishing.
func test_missed_shot_clangs_at_the_rim() -> void:
	view.render({"players": {}, "ball": [4.0, 0.0, -1, 1], "scores": [0, 0], "teams": []})
	var before: int = view.arena.get_child_count()
	view.render({"players": {}, "ball": [7.5, 0.5, -1, 0], "scores": [0, 0], "teams": []})
	assert_eq(view.arena.get_child_count(), before + 1, "the rim clang bursts")


func test_rig_follows_player_snapshot() -> void:
	view.render({"players": {0: [4.0, -2.0, 0]}, "ball": [0.0, 0.0, -1, 0], "scores": [0, 0]})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 4.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)


func test_dunk_bursts_at_the_attacked_hoop() -> void:
	var base := {
		"players": {},
		"ball": [0.0, 0.0, -1, 0],
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
	# A dunk fires the burst plus the #1123 confetti sparkle.
	assert_eq(view.arena.get_child_count(), before + 2, "a dunk = burst + confetti")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.scores, [0, 0])


## Signature cues (#728): a score is heard from your own team's perspective —
## `bell` for your team, `error` for the opposing team (slot 0 is my_slot, team 0).
func test_own_team_dunk_plays_bell_enemy_dunk_plays_error() -> void:
	var base := {
		"players": {},
		"ball": [0.0, 0.0, -1, 0],
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


## A shove popping the ball loose is heard by whoever lost it (not a shot).
func test_fumble_plays_bump_for_the_player_who_lost_the_ball() -> void:
	watch_signals(view)
	view.render(
		{"players": {}, "ball": [0.0, 0.0, 0, 0], "scores": [0, 0], "teams": [[0, 1], [2, 3]]}
	)
	view.render(
		{"players": {}, "ball": [0.0, 0.0, -1, 0], "scores": [0, 0], "teams": [[0, 1], [2, 3]]}
	)
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"bump"], "my ball popped loose")
