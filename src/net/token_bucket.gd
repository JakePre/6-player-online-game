class_name TokenBucket
extends RefCounted
## Per-key token-bucket rate limiter, extracted from NetManager (#770) where the
## emote (#592) and gameplay-input (#707) limiters were two byte-identical
## copies of this math. A burst of `burst` tokens spends instantly, then one
## token refills every `refill_ms`, so the sustained cap is 1000/refill_ms per
## second — a quick burst reads as snappy, sustained spam still caps out.
##
## Stateless by design: the caller owns the per-key `state` dict
## ({key: {tokens: float, last_ms: int}}) so NetManager keeps a single place to
## clear a peer's buckets on disconnect, and `now_ms` is passed in so the math
## is unit-testable without live transport or real delays.


## True if `key` may act at `now_ms`, consuming a token from `state` if so.
## A key not yet in `state` starts with a full burst.
static func consume(
	state: Dictionary, key: int, now_ms: int, burst: float, refill_ms: float
) -> bool:
	var entry: Dictionary = state.get(key, {"tokens": burst, "last_ms": now_ms})
	var elapsed := now_ms - int(entry.last_ms)
	var tokens: float = minf(burst, float(entry.tokens) + elapsed / refill_ms)
	if tokens < 1.0:
		state[key] = {"tokens": tokens, "last_ms": now_ms}
		return false
	state[key] = {"tokens": tokens - 1.0, "last_ms": now_ms}
	return true
