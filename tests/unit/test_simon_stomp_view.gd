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
	assert_not_null(view.arena.get_node("Pad0"))


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
