extends GutTest
## Screen transition (M16-02): the cover-and-reveal fade between app-shell
## screens. The load-bearing checks are that it covers before revealing (so no
## old-screen flash) and that reduced motion skips it entirely.

var _saved_reduced := false
var _transition: ScreenTransition


func before_each() -> void:
	_saved_reduced = ArenaFX.reduced_motion
	_transition = ScreenTransition.new()
	add_child_autofree(_transition)


func after_each() -> void:
	ArenaFX.reduced_motion = _saved_reduced


func test_starts_hidden_and_click_through() -> void:
	assert_false(_transition.visible, "at rest the cover is hidden")
	assert_eq(_transition.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and click-through")


func test_reveal_covers_then_blocks_input() -> void:
	ArenaFX.reduced_motion = false
	_transition.reveal()
	assert_true(_transition.visible, "the cover snaps up to hide the swap")
	assert_almost_eq(_transition.modulate.a, 1.0, 0.001, "fully opaque before revealing")
	assert_eq(_transition.mouse_filter, Control.MOUSE_FILTER_STOP, "blocks input mid-reveal")


func test_reveal_fades_out_and_settles() -> void:
	ArenaFX.reduced_motion = false
	_transition.reveal()
	# Let the DUR_MED fade run to completion.
	await get_tree().create_timer(PartyTheme.DUR_MED + 0.1).timeout
	assert_false(_transition.visible, "the cover hides once it has faded out")
	assert_eq(_transition.mouse_filter, Control.MOUSE_FILTER_IGNORE, "click-through again")


func test_reduced_motion_skips_the_transition() -> void:
	ArenaFX.reduced_motion = true
	_transition.reveal()
	assert_false(_transition.visible, "reduced motion never shows the cover")
	assert_eq(_transition.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and never blocks input")


## A second navigation mid-fade re-covers cleanly rather than stacking tweens.
func test_reentrant_reveal_recovers() -> void:
	ArenaFX.reduced_motion = false
	_transition.reveal()
	await get_tree().process_frame
	_transition.reveal()
	assert_true(_transition.visible, "the second reveal re-covers")
	assert_almost_eq(_transition.modulate.a, 1.0, 0.001, "back to fully opaque")
