class_name EliminationTracker
extends RefCounted
## Shared elimination + placement bookkeeping (#940). Roughly ten sims hand-copied
## the identical quartet — an ordered list of eliminated tie-groups (down / fall /
## ring-out order), an optional buffer of same-tick eliminations flushed as one
## group, and the is_in / in_slots / out_placements trio derived from them. The
## contract lives here once: **same-tick eliminations share a tie group, and
## placements rank in reverse elimination order** (the last one out placed best).
##
## Two-phase games buffer during the tick and flush at the end:
##     _elim.mark(slot)              # somewhere off gets queued
##     _elim.flush()                 # end of tick: this tick's outs become a group
## Immediate games eliminate a resolved group directly:
##     _elim.eliminate([a, b])       # a and b are out now, tied
## Either way, ranking is `placements + _elim.out_placements()` and the live
## roster is `_elim.in_slots(slots)`.

## The eliminated tie-groups, in elimination order (earliest out first).
var order: Array = []
## Slots eliminated this tick, not yet grouped (two-phase games only).
var _pending: Array = []


## Queue a slot for elimination this tick (deduped); flush() groups them.
func mark(slot: int) -> void:
	if slot not in _pending:
		_pending.append(slot)


## True if the slot is queued but not yet flushed into a group.
func is_pending(slot: int) -> bool:
	return slot in _pending


## Group everything marked this tick into one tie-group; a no-op if nothing
## was marked, so it is safe to call every tick.
func flush() -> void:
	if _pending.is_empty():
		return
	order.append(_pending.duplicate())
	_pending.clear()


## Eliminate an already-resolved group at once (immediate games that don't
## buffer). An empty group is ignored.
func eliminate(group: Array) -> void:
	if not group.is_empty():
		order.append(group.duplicate())


## Still standing: a real slot that is neither in an eliminated group nor
## queued for elimination this tick.
func is_in(slot: int, slots: Array) -> bool:
	if slot not in slots:
		return false
	for group: Array in order:
		if slot in group:
			return false
	return slot not in _pending


## The live roster, filtered from `slots` (preserving its order).
func in_slots(slots: Array) -> Array:
	return slots.filter(func(slot: int) -> bool: return is_in(slot, slots))


## Placements for the eliminated — reverse elimination order, so the last group
## out ranks ahead of the first. Append after the survivors' placements.
func out_placements() -> Array:
	var placements := order.duplicate(true)
	placements.reverse()
	return placements
