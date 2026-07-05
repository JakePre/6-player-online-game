extends GutTest
## Menu backdrop (M16-03): the animated title-screen field. Verifies it
## populates its drift field, advances upward when live, and — the load-bearing
## accessibility check — freezes completely under reduced motion.

var _saved_reduced := false


func before_each() -> void:
	_saved_reduced = ArenaFX.reduced_motion


func after_each() -> void:
	ArenaFX.reduced_motion = _saved_reduced


func _backdrop() -> MenuBackdrop:
	var view := MenuBackdrop.new()
	add_child_autofree(view)
	view.size = Vector2(1280, 720)
	view._populate()
	return view


func test_populates_the_drift_field() -> void:
	ArenaFX.reduced_motion = false
	var view := _backdrop()
	assert_eq(view._discs.size(), MenuBackdrop.DISC_COUNT, "one disc per slot")
	assert_eq(view._sparkles.size(), MenuBackdrop.SPARKLE_COUNT)
	for disc in view._discs:
		assert_between(
			float(disc.r), MenuBackdrop.DISC_MIN_R, MenuBackdrop.DISC_MAX_R, "disc radius in range"
		)


func test_live_field_drifts_upward() -> void:
	ArenaFX.reduced_motion = false
	var view := _backdrop()
	assert_true(view.is_processing(), "a live backdrop animates")
	var before: float = view._discs[0].y
	view._advance(0.1)
	assert_lt(view._discs[0].y, before, "discs drift up over time")


func test_disc_wraps_at_the_top() -> void:
	ArenaFX.reduced_motion = false
	var view := _backdrop()
	view._discs[0].y = -MenuBackdrop.DISC_MAX_R * 3.0
	view._advance(0.016)
	assert_gt(view._discs[0].y, view.size.y, "a disc past the top recycles to the bottom")


func test_reduced_motion_freezes_the_field() -> void:
	ArenaFX.reduced_motion = true
	var view := _backdrop()
	assert_false(view.is_processing(), "reduced motion stops the per-frame drift")
	assert_eq(view._discs.size(), MenuBackdrop.DISC_COUNT, "but the field still renders static")
