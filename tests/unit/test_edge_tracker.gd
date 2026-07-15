extends GutTest
## EdgeTracker (#941): the seeded rising/falling/any-change edge detector the
## view FX layer uses so a mid-match rejoiner's first snapshot never fires a
## phantom shake. The load-bearing property is "first sight never fires".


func test_rose_never_fires_on_first_sight() -> void:
	var t := EdgeTracker.new()
	# A rejoiner whose opening snapshot already shows 3 eliminated: quiet.
	assert_false(t.rose(&"fallen", 3), "first sight seeds, never fires")


func test_rose_fires_only_when_the_value_climbs() -> void:
	var t := EdgeTracker.new()
	t.rose(&"fallen", 0)  # seed
	assert_false(t.rose(&"fallen", 0), "unchanged does not fire")
	assert_true(t.rose(&"fallen", 1), "a climb fires")
	assert_false(t.rose(&"fallen", 1), "holding at the raised value stays quiet")
	assert_false(t.rose(&"fallen", 0), "a drop does not fire rose()")


func test_fell_fires_only_when_the_value_drops() -> void:
	var t := EdgeTracker.new()
	t.fell(&"alive", 6)  # seed
	assert_false(t.fell(&"alive", 6), "unchanged does not fire")
	assert_true(t.fell(&"alive", 5), "a drop fires")
	assert_false(t.fell(&"alive", 7), "a climb does not fire fell()")


func test_fell_orders_bools_for_an_alive_to_dead_drop() -> void:
	var t := EdgeTracker.new()
	assert_false(t.fell(0, true), "seeding an alive player is quiet")
	assert_true(t.fell(0, false), "alive -> dead fires (false < true)")
	assert_false(t.fell(0, false), "staying dead stays quiet")
	assert_false(t.fell(0, true), "a revive does not fire fell()")


func test_changed_fires_on_any_difference() -> void:
	var t := EdgeTracker.new()
	assert_false(t.changed(&"phase", "SHOW"), "first sight seeds")
	assert_false(t.changed(&"phase", "SHOW"), "same value stays quiet")
	assert_true(t.changed(&"phase", "DARK"), "a change fires")
	assert_true(t.changed(&"phase", "SHOW"), "changing back fires too")


func test_keys_are_tracked_independently() -> void:
	var t := EdgeTracker.new()
	t.rose(0, 5)  # seed slot 0
	t.rose(1, 5)  # seed slot 1
	assert_true(t.rose(0, 6), "slot 0 climbs")
	assert_false(t.rose(1, 5), "slot 1 unaffected by slot 0")


func test_peek_reads_without_recording() -> void:
	var t := EdgeTracker.new()
	# The delta-magnitude idiom: read the prior score, compute the gain,
	# THEN record via a subsequent edge call.
	assert_eq(t.peek(0, 12), 12, "unseen key returns the default")
	assert_false(t.rose(0, 12), "peek did not seed, so this first rose() seeds")
	assert_true(t.rose(0, 15), "now a climb fires")
	assert_eq(t.peek(0), 15, "peek reflects the recorded value")


func test_forget_reseeds_a_single_key() -> void:
	var t := EdgeTracker.new()
	t.rose(&"fallen", 3)  # seed at 3
	t.forget(&"fallen")
	assert_false(t.rose(&"fallen", 9), "after forget, the next sight re-seeds (quiet)")
	assert_true(t.rose(&"fallen", 10), "and fires again on the next climb")


func test_clear_reseeds_every_key() -> void:
	var t := EdgeTracker.new()
	t.rose(0, 1)
	t.rose(1, 1)
	t.clear()
	assert_false(t.rose(0, 5), "cleared: slot 0 re-seeds")
	assert_false(t.rose(1, 5), "cleared: slot 1 re-seeds")


## The exact contract the `_fallen_seen := -1` views relied on: seed on the
## first render (whatever the count), fire only on a later climb.
func test_matches_the_fallen_seen_sentinel_semantics() -> void:
	var t := EdgeTracker.new()
	# Render 1: two already down when we join — the old `-1 >= 0` guard was
	# false here, so it seeded silently. Same result.
	assert_false(t.rose(&"fallen", 2))
	# Render 2: still two down — quiet.
	assert_false(t.rose(&"fallen", 2))
	# Render 3: a third goes down — the shake fires.
	assert_true(t.rose(&"fallen", 3))
