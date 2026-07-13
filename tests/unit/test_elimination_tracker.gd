extends GutTest
## EliminationTracker (#940): the shared elimination + placement bookkeeping the
## sims used to hand-copy. Covers both drivers — two-phase mark/flush and
## immediate eliminate — plus the is_in / in_slots / out_placements derivations.


func test_fresh_tracker_keeps_everyone_in() -> void:
	var elim := EliminationTracker.new()
	var slots := [0, 1, 2]
	assert_eq(elim.in_slots(slots), [0, 1, 2], "nobody out yet -> full roster in slot order")
	assert_true(elim.is_in(1, slots), "slot 1 still in")
	assert_eq(elim.out_placements(), [], "no placements while nobody is out")


func test_mark_is_pending_until_flushed() -> void:
	var elim := EliminationTracker.new()
	var slots := [0, 1, 2]
	elim.mark(1)
	assert_true(elim.is_pending(1), "marked slot is pending")
	assert_false(elim.is_in(1, slots), "a pending slot is not counted in")
	assert_eq(elim.in_slots(slots), [0, 2], "pending slot drops from the live roster immediately")
	assert_eq(elim.order, [], "nothing grouped until flush")
	elim.flush()
	assert_false(elim.is_pending(1), "flush clears the pending buffer")
	assert_eq(elim.order, [[1]], "flushed slot becomes its own tie group")


func test_mark_dedupes_within_a_tick() -> void:
	var elim := EliminationTracker.new()
	elim.mark(2)
	elim.mark(2)
	elim.flush()
	assert_eq(elim.order, [[2]], "the same slot marked twice makes one entry")


func test_same_tick_marks_share_a_tie_group() -> void:
	var elim := EliminationTracker.new()
	elim.mark(0)
	elim.mark(3)
	elim.flush()
	assert_eq(elim.order, [[0, 3]], "two outs in one tick share a group")


func test_flush_with_nothing_pending_is_a_noop() -> void:
	var elim := EliminationTracker.new()
	elim.mark(1)
	elim.flush()
	elim.flush()  # no marks since -> must not append an empty group
	assert_eq(elim.order, [[1]], "an empty flush appends nothing")


func test_out_placements_rank_in_reverse_elimination_order() -> void:
	var elim := EliminationTracker.new()
	var slots := [0, 1, 2, 3]
	# 1 out first, then 0 and 3 together, then 2.
	elim.mark(1)
	elim.flush()
	elim.mark(0)
	elim.mark(3)
	elim.flush()
	elim.mark(2)
	elim.flush()
	assert_eq(elim.in_slots(slots), [], "everyone eliminated -> empty roster")
	# Last out ranks best: 2, then the {0,3} tie, then 1.
	assert_eq(elim.out_placements(), [[2], [0, 3], [1]], "reverse elimination order")


func test_eliminate_appends_a_resolved_group_immediately() -> void:
	var elim := EliminationTracker.new()
	var slots := [0, 1, 2]
	elim.eliminate([2])
	assert_false(elim.is_in(2, slots), "eliminated slot is out")
	assert_eq(elim.in_slots(slots), [0, 1], "roster excludes the eliminated slot")
	elim.eliminate([0, 1])
	assert_eq(elim.out_placements(), [[0, 1], [2]], "later out ranks ahead of earlier")


func test_eliminate_ignores_an_empty_group() -> void:
	var elim := EliminationTracker.new()
	elim.eliminate([])
	assert_eq(elim.order, [], "an empty group is not recorded")


func test_is_in_rejects_a_slot_not_in_the_roster() -> void:
	var elim := EliminationTracker.new()
	assert_false(elim.is_in(9, [0, 1, 2]), "a slot outside the roster is never in")


func test_out_placements_is_an_independent_copy() -> void:
	var elim := EliminationTracker.new()
	elim.eliminate([0])
	var placements := elim.out_placements()
	placements.append([99])
	assert_eq(elim.order, [[0]], "mutating the returned placements must not touch internal state")
