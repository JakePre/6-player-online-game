class_name SafeInput
extends RefCounted
## The trust boundary for client match input (#970). `_rpc_match_input` is
## `@rpc("any_peer")`, so any client can send an arbitrary Dictionary; Godot
## validates only the top-level type, not the values. Sims then trust those
## values — `float(data.get("mx", 0.0))`, position math, `snappedf()` into the
## snapshot — so a crafted payload poisons the replicated state for the whole
## room (proven: `"1e999"` → INF → `limit_length` → NaN → shipped to every
## client; NaN never resolves, wedging the round permanently).
##
## sanitize() is the ONE place that hostility is stopped, so all ~46
## `_handle_input`s keep their trusting style safely. Guarantee after sanitize:
## every value is a bool or a **finite** number, and there are at most MAX_KEYS
## of them — nothing else survives (strings, arrays, dictionaries, objects,
## vectors are dropped; the field simply reads as its default in the sim).

## No real input dict carries more than a handful of fields (mx/my + an action
## or two); a larger one is hostile — reject it whole before the O(n) scan.
const MAX_KEYS := 8


## Returns a copy of `data` containing only string-keyed bool / finite-number
## values. Non-finite numbers coerce to 0.0; every other value type is dropped.
static func sanitize(data: Dictionary) -> Dictionary:
	var clean := {}
	if data.size() > MAX_KEYS:
		return clean
	for key: Variant in data:
		if not (key is String or key is StringName):
			continue
		var value: Variant = data[key]
		match typeof(value):
			TYPE_BOOL, TYPE_INT:
				clean[key] = value
			TYPE_FLOAT:
				clean[key] = value if is_finite(value) else 0.0
			_:
				# Strings ("1e999" → INF via the sim's float()), arrays, dicts,
				# objects, vectors — no legitimate input sends these, and each is
				# a poisoning or error vector, so drop the field entirely.
				pass
	return clean
