extends GutTest
## Putt Panic client view (M14-08): renders the green, cup, bar and balls from
## replicated snapshots without simulating anything locally.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/putt_panic/putt_panic_view.tscn")
const CUP := Vector2(0.0, 6.5)

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


## players entry: [x, y, strokes, sunk, aim_x, aim_y, at_rest]. The course keys
## (#793) mirror the seeded shape the sim now sends: cup, a two-block gate, and
## the bar with its geometry.
func _snapshot(players: Dictionary, bar_x := 0.0) -> Dictionary:
	return {
		"players": players,
		"cup": [CUP.x, CUP.y],
		"bar": [bar_x, 3.6, 1.6, 0.5],
		"blocks": [[-3.5, 1.0, 1.0, 0.6], [3.5, 1.0, 1.0, 0.6]],
		"shot_clock": PuttPanic.SHOT_CLOCK_SEC,
	}


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"putt_panic"),
		"res://src/minigames/putt_panic/putt_panic_view.tscn"
	)


func test_setup_builds_a_ball_per_player() -> void:
	# Balls are course-independent, built at setup; the cup/bar/blocks are
	# seeded per round (#793) and appear on the first snapshot (below).
	assert_not_null(view.arena.get_node("Ball0"))
	assert_not_null(view.arena.get_node("Ball1"))


## #793: the seeded course arrives with the first snapshot — the bar and the two
## gate blocks are built from it, not from consts.
func test_course_builds_from_the_first_snapshot() -> void:
	assert_null(view.arena.get_node_or_null("Bar"), "no course before a snapshot")
	view.render(_snapshot({0: [0.0, -7.0, 0, 0, 0.0, 1.0, 1]}, 2.0))
	assert_not_null(view.arena.get_node("Bar"), "the bar is built from the snapshot")
	var bar: MeshInstance3D = view.arena.get_node("Bar")
	assert_almost_eq(bar.position.x, 2.0, 0.001, "bar sits where the snapshot says")


func test_balls_and_bar_track_the_snapshot() -> void:
	view.render(_snapshot({0: [2.0, -3.0, 1, 0, 0.0, 1.0, 1]}, 3.5))
	var ball: MeshInstance3D = view.arena.get_node("Ball0")
	assert_almost_eq(ball.position.x, 2.0, 0.001)
	assert_almost_eq(ball.position.z, -3.0, 0.001)
	var bar: MeshInstance3D = view.arena.get_node("Bar")
	assert_almost_eq(bar.position.x, 3.5, 0.001)


func test_strokes_ride_the_nameplate() -> void:
	view.render(_snapshot({0: [0.0, 0.0, 4, 0, 0.0, 1.0, 1]}))
	assert_string_contains(view.rig_for_slot(0).display_name, "4")


func test_sinking_pops_a_burst() -> void:
	view.render(_snapshot({0: [1.0, 5.0, 3, 0, 0.0, 1.0, 0]}))
	var before := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			before += 1
	# Same player, now sunk (flag 1) → a celebration burst at the cup.
	view.render(_snapshot({0: [CUP.x, CUP.y, 3, 1, 0.0, 1.0, 1]}))
	var after := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			after += 1
	assert_gt(after, before, "holing out bursts at the cup")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)


# --- Fire-while-aiming (#1043) ------------------------------------------------


## Before the local player has touched the stick this round, the aim line
## falls back to the replicated direction (e.g. the sim's toward-the-cup
## default) rather than starting at zero-length.
func test_aim_visual_falls_back_to_replicated_aim_before_local_input() -> void:
	view.render(_snapshot({0: [0.0, -7.0, 0, 0, 0.3, 0.9, 1]}))
	view._update_aim_visual(true)
	assert_true(view._aim_line.visible)
	assert_almost_eq(view._local_aim.x, 0.3, 0.001, "seeded from the replicated aim")
	assert_almost_eq(view._local_aim.y, 0.9, 0.001)


## #1043: once the player has moved the stick, the aim line reflects that
## input immediately — it does not wait for the server to echo it back in a
## snapshot. This is the fix for aim feeling like a separate, laggy "commit"
## step before the (fully local) charge meter could be trusted.
func test_aim_visual_uses_local_input_over_a_stale_replicated_aim() -> void:
	view.render(_snapshot({0: [0.0, -7.0, 0, 0, 0.3, 0.9, 1]}))
	view._local_aim = Vector2(-1.0, 0.0)  # the player has since aimed elsewhere
	view._update_aim_visual(true)
	assert_almost_eq(view._aim_line.rotation.y, atan2(-1.0, 0.0), 0.001)


## Aiming and charging happen in the same motion — nothing in the local input
## loop gates the aim send on whether a charge is in progress.
func test_charging_does_not_block_local_aim_tracking() -> void:
	view._charging = true
	view._charge = 0.4
	view._local_aim = Vector2(0.0, 1.0)
	view.render(_snapshot({0: [0.0, -7.0, 0, 0, 0.0, 1.0, 1]}))
	view._local_aim = Vector2(1.0, 0.0)  # re-aim mid-charge
	view._update_aim_visual(true)
	assert_almost_eq(view._aim_line.rotation.y, atan2(1.0, 0.0), 0.001, "aim updates mid-charge")
	assert_almost_eq(view._power_bar.value, 40.0, 0.001, "charge is untouched by re-aiming")
