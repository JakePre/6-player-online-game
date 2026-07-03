extends GutTest
## Quick Draw client view (M8-08): renders replicated snapshots in the shared
## iso-arena without simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/quick_draw/quick_draw_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_setup_lines_up_rigs_with_lamp_and_labels() -> void:
	assert_not_null(view.arena.get_node("SignalLamp"))
	assert_not_null(view.get_node("SignalLabel"))
	assert_not_null(view.get_node("RoundLabel"))
	var alice: CharacterRig = view.rig_for_slot(0)
	var bob: CharacterRig = view.rig_for_slot(1)
	assert_almost_eq(alice.position.x, -1.0, 0.001, "two duelists straddle the center")
	assert_almost_eq(bob.position.x, 1.0, 0.001)


func test_waiting_phase_shows_red_wait() -> void:
	view.render({"phase": QuickDraw.Phase.WAITING, "round": 0, "wins": {0: 0, 1: 0}})
	var label: Label = view.get_node("SignalLabel")
	assert_eq(label.text, "WAIT...")
	assert_eq(view._lamp_material.albedo_color, view.WAITING_COLOR)
	assert_string_contains(view.get_node("RoundLabel").text, "Round 1")


func test_live_phase_shows_green_draw() -> void:
	view.render({"phase": QuickDraw.Phase.LIVE, "round": 2, "wins": {0: 1, 1: 1}})
	var label: Label = view.get_node("SignalLabel")
	assert_eq(label.text, "DRAW!")
	assert_eq(view._lamp_material.albedo_color, view.LIVE_COLOR)


func test_round_over_winner_cheers_and_tallies() -> void:
	view.render(
		{
			"phase": QuickDraw.Phase.ROUND_OVER,
			"round": 1,
			"wins": {0: 2, 1: 0},
			"false_started": {1: true},
			"winner": 0
		}
	)
	assert_eq(view.rig_for_slot(0).current_action(), &"cheer")
	assert_eq(view.rig_for_slot(1).current_action(), &"hit")
	assert_string_contains(view.rig_for_slot(0).display_name, "2")
	assert_string_contains(view.rig_for_slot(1).display_name, "false start")
	assert_string_contains(view.get_node("SignalLabel").text, "Alice wins")


func test_next_round_returns_everyone_to_idle() -> void:
	view.render(
		{
			"phase": QuickDraw.Phase.ROUND_OVER,
			"round": 1,
			"wins": {0: 2, 1: 0},
			"false_started": {},
			"winner": 0
		}
	)
	view.render({"phase": QuickDraw.Phase.WAITING, "round": 2, "wins": {0: 2, 1: 0}})
	assert_eq(view.rig_for_slot(0).current_action(), &"idle")
	assert_eq(view.rig_for_slot(1).current_action(), &"idle")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view._phase, QuickDraw.Phase.WAITING)
	assert_eq(view._winner, -1)
	assert_eq(view.get_node("SignalLabel").text, "WAIT...")
