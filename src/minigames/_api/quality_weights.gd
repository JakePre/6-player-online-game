class_name QualityWeights
extends RefCounted
## Per-game draft weight (#937): pulls weak-tier games down in the playlist
## draw so players see the good stuff more often while the weak tier gets
## reworked. A checked-in const map — NOT a live GitHub query — so the
## playlist stays deterministic across server versions regardless of issue
## state. Restore an entry to 1.0 (or drop it) in the PR that closes the
## rework/design issue it cites.

## No weight may reach zero — every eligible game must stay reachable.
const FLOOR_WEIGHT := 0.05

const _WEIGHTS := {
	# #932: Payload Race rework in flight (cart_push is the pre-rework game).
	# Restore to 1.0 in the PR that lands Payload Race.
	&"cart_push": 0.25,
}


## Anything not in the map defaults to 1.0 — a full, un-penalized draw weight.
static func weight_of(id: StringName) -> float:
	return maxf(_WEIGHTS.get(id, 1.0), FLOOR_WEIGHT)
