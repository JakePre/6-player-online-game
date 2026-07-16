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
## every number is **finite**, there are at most MAX_KEYS top-level fields, and
## the only non-scalar values that survive are two bounded, consumer-validated
## shapes (below) — everything else (top-level strings, objects, vectors, the
## deeper nesting) is dropped and the field reads as its default in the sim.
##
## Two intents legitimately carry non-scalar values and were silently broken by
## the original scalars-only rule (#1030/#1042 — the whole finale shop, trap
## placement, and grudge/sabotage targeting stopped working):
##   * positional/index ARRAYS — trap's [col, row], the finale's grudge/sabotage
##     [x, y]. Element-sanitized to finite numbers, they are exactly as safe as
##     the scalar fields, and every consumer still structurally validates them.
##   * the finale shop's nested {action, item} DICT (`shop` key only). Its
##     strings are safe HERE — the one place a string value survives — because
##     its consumer only ever matches them against FinaleShop.ITEMS / a fixed
##     action set and NEVER float()-coerces them, so the "1e999 → INF" vector
##     that bans strings at top level cannot apply.

## No real input dict carries more than a handful of fields (mx/my + an action
## or two); a larger one is hostile — reject it whole before the O(n) scan.
const MAX_KEYS := 8
## The one nested-dict intent (#1030): the finale buy-in shop.
const SHOP_KEY := &"shop"
## The shop dict carries at most {action, item}; longer is hostile.
const SHOP_MAX_KEYS := 4
## Shop item/action ids are short (< 15 chars); a longer string can match no
## real id and is dropped, closing a giant-string memory vector.
const SHOP_STRING_MAX_LEN := 64
## Positional/index arrays are tiny ([col,row], [x,y]); cap the element scan.
const ARRAY_MAX_LEN := 8


## Returns a copy of `data` with only string-keyed values that survive the trust
## rules: finite scalars (non-finite coerce to 0.0), bounded numeric arrays, and
## the finale shop's nested string dict. Everything else is dropped.
static func sanitize(data: Dictionary) -> Dictionary:
	var clean := {}
	if data.size() > MAX_KEYS:
		return clean
	for key: Variant in data:
		if not (key is String or key is StringName):
			continue
		var value: Variant = data[key]
		if StringName(key) == SHOP_KEY:
			var shop := _sanitize_shop(value)
			if not shop.is_empty():
				clean[key] = shop
			continue
		match typeof(value):
			TYPE_BOOL, TYPE_INT:
				clean[key] = value
			TYPE_FLOAT:
				clean[key] = value if is_finite(value) else 0.0
			TYPE_ARRAY:
				var arr := _sanitize_number_array(value)
				if arr != null:
					clean[key] = arr
			_:
				# Top-level strings ("1e999" → INF via the sim's float()),
				# objects, vectors — no legitimate input sends these, and each is
				# a poisoning or error vector, so drop the field entirely.
				pass
	return clean


## A bounded numeric array (trap [col,row], grudge/sabotage [x,y]): every element
## kept as a bool/int or finite float (non-finite → 0.0). Returns null — so the
## key is dropped — when the array is empty, over-long, or holds ANY non-number
## element (a string there would still be float()-coerced into INF downstream).
static func _sanitize_number_array(value: Array) -> Variant:
	if value.is_empty() or value.size() > ARRAY_MAX_LEN:
		return null
	var clean_arr := []
	for element: Variant in value:
		match typeof(element):
			TYPE_BOOL, TYPE_INT:
				clean_arr.append(element)
			TYPE_FLOAT:
				clean_arr.append(element if is_finite(element) else 0.0)
			_:
				return null
	return clean_arr


## The finale shop intent (#1030): a small {action, item} dict whose string
## values pass (unlike top level) because the consumer only compares them against
## a fixed set and never float()-coerces them. Numbers are still finite-checked;
## deeper nesting, objects, and over-long strings are dropped.
static func _sanitize_shop(value: Variant) -> Dictionary:
	var clean := {}
	if typeof(value) != TYPE_DICTIONARY:
		return clean
	var dict: Dictionary = value
	if dict.size() > SHOP_MAX_KEYS:
		return clean
	for key: Variant in dict:
		if not (key is String or key is StringName):
			continue
		var v: Variant = dict[key]
		match typeof(v):
			TYPE_STRING, TYPE_STRING_NAME:
				if String(v).length() <= SHOP_STRING_MAX_LEN:
					clean[key] = v
			TYPE_BOOL, TYPE_INT:
				clean[key] = v
			TYPE_FLOAT:
				clean[key] = v if is_finite(v) else 0.0
			_:
				pass
	return clean
