extends GutTest
## Simon Stomp client view (#261 polish): pad labels, phase chrome, and
## snapshot rendering without local simulation.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/simon_stomp/simon_stomp_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_pads_carry_readable_labels() -> void:
	# #261: every pad names its direction, key, and color.
	for pad in 4:
		var tag: Label3D = view.arena.get_node("PadLabel%d" % pad)
		assert_true(tag.no_depth_test, "labels read through geometry")
		assert_false(tag.text.is_empty())


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_not_null(view.arena.get_node("PadGroup0/Pad0"))


func _ripple_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child.name.begins_with("StompRipple"):
			count += 1
	return count


## M13-16: clearing the round ripples across the pads. Edge-triggered off the
## round_cleared snapshot for the local slot, so it fires once on the rising
## edge and nothing at rest.
func test_clearing_the_round_pops_stomp_ripples() -> void:
	assert_eq(_ripple_count(), 0, "no ripples at rest")
	view.render({"phase": SimonStomp.Phase.INPUT, "round": 0, "round_cleared": {}})
	assert_eq(_ripple_count(), 0, "still nothing until the round is cleared")
	view.render({"phase": SimonStomp.Phase.INPUT, "round": 0, "round_cleared": {0: true}})
	assert_gt(_ripple_count(), 0, "clearing the round sends ripples across the pads")


## The clear pop fires once, not every snapshot while cleared stays true.
func test_clear_pop_is_edge_triggered() -> void:
	view.render({"phase": SimonStomp.Phase.INPUT, "round": 0, "round_cleared": {0: true}})
	var after_first := _ripple_count()
	view.render({"phase": SimonStomp.Phase.INPUT, "round": 0, "round_cleared": {0: true}})
	assert_eq(_ripple_count(), after_first, "a held cleared flag does not re-pop")


## #588: a lead-in beat holds every pad dim before the first flash, so players'
## eyes have landed on the board before the sequence starts.
func test_lead_in_keeps_every_pad_dim_before_the_first_flash() -> void:
	view.render({"phase": SimonStomp.Phase.SHOW, "round": 0, "sequence": [1, 2]})
	view._show_timer = SimonStomp.SHOW_LEAD_IN_SEC - 0.05
	view._update_pads()
	for pad in 4:
		assert_almost_eq(
			view._pad_materials[pad].emission_energy_multiplier,
			view.DIM,
			0.001,
			"pad %d stays dim during the lead-in" % pad
		)


## #588: each flashed pad plays its own distinct note instead of one shared tick.
func test_each_flashed_pad_plays_its_own_distinct_sfx() -> void:
	view.render({"phase": SimonStomp.Phase.SHOW, "round": 0, "sequence": [2, 0]})
	watch_signals(view)
	view._show_timer = SimonStomp.SHOW_LEAD_IN_SEC + 0.01
	view._update_pads()
	assert_signal_emitted_with_parameters(view, "sfx_requested", [view.PAD_SFX[2]])


## #1044: a big numeral counts down through the lead-in — as loud as round 1's
## separate match-level countdown — then hides once the first pad can flash.
func test_countdown_ticks_through_the_lead_in_and_hides_once_pads_start() -> void:
	view.render({"phase": SimonStomp.Phase.SHOW, "round": 0, "sequence": [1, 2]})
	view._show_timer = 0.01
	view._update_countdown()
	assert_true(view._countdown_label.visible, "counts down right at the top of SHOW")
	assert_eq(view._countdown_label.text, "3")
	view._show_timer = SimonStomp.SHOW_LEAD_IN_STEP_SEC + 0.01
	view._update_countdown()
	assert_eq(view._countdown_label.text, "2")
	view._show_timer = SimonStomp.SHOW_LEAD_IN_SEC - 0.01
	view._update_countdown()
	assert_eq(view._countdown_label.text, "1")
	view._show_timer = SimonStomp.SHOW_LEAD_IN_SEC + 0.01
	view._update_countdown()
	assert_false(view._countdown_label.visible, "hides once the first pad flash can start")


## #795: alive players are revealed in a stage row facing the pads, instead
## of loitering invisibly at the arena origin (where the pad diamond sits).
func test_alive_players_stand_in_the_stage_row_and_are_revealed() -> void:
	view.render({"phase": SimonStomp.Phase.INPUT, "round": 0, "alive": {0: true, 1: true}})
	var rig0 := view.rig_for_slot(0)
	var rig1 := view.rig_for_slot(1)
	assert_true(rig0.visible, "stage players are revealed")
	assert_true(rig1.visible)
	assert_almost_eq(rig0.position.z, -view.ROW_Z, 0.001, "the stage sits behind the pads")
	assert_almost_eq(rig0.rotation.y, 0.0, 0.001, "the stage faces the pads/audience")
	assert_ne(rig0.position.x, rig1.position.x, "the row spreads players apart")


## An eliminated player moves to a mirrored row on the far side and is marked
## (out) — not stuck loitering on the pads.
func test_eliminated_players_move_to_the_audience_row() -> void:
	view.render({"phase": SimonStomp.Phase.INPUT, "round": 0, "alive": {0: true, 1: false}})
	var rig1 := view.rig_for_slot(1)
	assert_true(rig1.visible, "eliminated players are still revealed, just relocated")
	assert_almost_eq(rig1.position.z, view.ROW_Z, 0.001, "the audience watches from the far side")
	assert_almost_eq(rig1.rotation.y, PI, 0.001, "the audience faces back toward the stage")
	assert_string_contains(rig1.display_name, "(out)")


## The old behavior froze an eliminated player on the one-shot "hit" pose
## forever; the audience now idles (or cheers) instead.
func test_eliminated_player_is_not_frozen_on_the_bust_pose() -> void:
	(
		view
		. render(
			{
				"phase": SimonStomp.Phase.INPUT,
				"round": 0,
				"alive": {0: false},
				"round_failed": {0: true},
			}
		)
	)
	view.render({"phase": SimonStomp.Phase.INPUT, "round": 1, "alive": {0: false}})
	assert_eq(view.rig_for_slot(0).current_action(), &"idle", "the audience settles, not busted")


## The audience cheers along when a player still in the round clears it.
func test_audience_cheers_when_a_stage_player_clears_the_round() -> void:
	(
		view
		. render(
			{
				"phase": SimonStomp.Phase.INPUT,
				"round": 0,
				"alive": {0: false, 1: true},
				"round_cleared": {1: true},
			}
		)
	)
	assert_eq(view.rig_for_slot(0).current_action(), &"cheer", "the audience cheers a clear too")


## #930: SHOW's own banners live on the never-hidden BannerLayer, so a match
## ending mid-sequence otherwise leaves "Round 2/8 · Length 3" floating over
## the results overlay — the results celebration must clear them.
func test_celebrate_clears_the_round_banner() -> void:
	view.render({"phase": SimonStomp.Phase.SHOW, "round": 1, "rounds_total": 8, "length": 3})
	view._show_timer = 0.01
	view._update_countdown()
	assert_false(view._round_label.text.is_empty(), "the banner shows mid-round")
	assert_true(view._countdown_label.visible, "the countdown shows mid-lead-in")
	view.celebrate([[0]])
	assert_true(view._phase_label.text.is_empty(), "the phase banner clears on finish")
	assert_true(view._round_label.text.is_empty(), "the round banner clears on finish")
	assert_false(view._countdown_label.visible, "the countdown clears on finish too")
