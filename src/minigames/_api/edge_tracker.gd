class_name EdgeTracker
extends RefCounted
## Rising / falling / any-change edge detection for view FX seeding (#941).
##
## Views fire a shake or SFX the moment a replicated value crosses a
## threshold — a fallen count ticks up, a life is lost, a score changes — but
## must stay quiet on a mid-match rejoiner's FIRST snapshot: the value was
## already at that level before they joined, so firing then is a phantom
## shake. Eleven views hand-rolled this with `_x_seen := -1` sentinels or
## `.get(key, current)` defaults, re-deriving the seeding subtlety every time
## (and occasionally getting it wrong).
##
## Every method here is seeded by construction: the first time a `key` is
## seen its value is recorded and the method returns `false`; only a later
## crossing fires. `key` is arbitrary — a `StringName` for a single scalar
## (e.g. `&"fallen"`) or a per-player `slot` int for per-entity tracking.
##
## rose()/fell() compare with `>` / `<` (pass numerics, incl. bools, which
## order false < true — handy for an alive→dead drop). changed() compares
## with `!=` and takes any Variant.

var _last := {}


## True when `value` is strictly greater than the last value seen for `key`.
## First sight of `key` records `value` and returns false (seeded — a
## rejoiner whose opening snapshot already shows the raised value never fires).
func rose(key: Variant, value: Variant) -> bool:
	var fired: bool = _last.has(key) and value > _last[key]
	_last[key] = value
	return fired


## True when `value` is strictly less than the last value seen for `key`.
## Seeded like rose(): first sight records and returns false. With bool
## `value`, false < true means a true→false transition fires (alive→dead).
func fell(key: Variant, value: Variant) -> bool:
	var fired: bool = _last.has(key) and value < _last[key]
	_last[key] = value
	return fired


## True when `value` differs from the last value seen for `key`. Seeded like
## rose(): first sight records and returns false. `value` may be any type.
func changed(key: Variant, value: Variant) -> bool:
	var fired: bool = _last.has(key) and value != _last[key]
	_last[key] = value
	return fired


## The last value recorded for `key`, or `default` if `key` is unseen —
## a read that does NOT record. For the delta-magnitude case (a score
## gauge): `var gained := score - tracker.peek(slot, score)` reads the prior
## value without seeding, leaving a following rose()/changed() to record it.
func peek(key: Variant, default: Variant = null) -> Variant:
	return _last.get(key, default)


## Forget `key` so its next sighting seeds afresh — e.g. a per-round reset so
## the same edge can fire again next round.
func forget(key: Variant) -> void:
	_last.erase(key)


## Forget every key.
func clear() -> void:
	_last.clear()
