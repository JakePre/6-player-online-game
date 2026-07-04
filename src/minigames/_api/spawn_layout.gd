class_name SpawnLayout
extends RefCounted
## Shared spawn-position helper (M15-05 / ADR-003 F5). Most minigames ring their
## players with `TAU * i / n` at a fixed radius, which packs tight past ~12. This
## distributes any count across concentric rings so dense lobbies (up to 24) keep
## their spacing, while small lobbies still get the single even ring they always
## had. Pure geometry — no scene, no state — so it's trivially testable and safe
## to call from either the sim or a view.

## Players beyond this on a single ring get too tight, so spill to another ring.
const SINGLE_RING_MAX := 8


## `count` evenly-spread positions inside `radius`, in slot order (map slots[i] ->
## result[i]). One player sits at the center; a handful share one ring at
## `radius`; dense counts fan out over concentric rings. Returns empty for
## count <= 0.
static func ring_positions(count: int, radius: float) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if count <= 0:
		return positions
	if count == 1:
		positions.append(Vector2.ZERO)
		return positions
	var rings := ring_count(count)
	var per_ring := _distribute(count, rings)
	for ring in rings:
		var ring_index := ring + 1  # 1 = innermost
		var ring_radius := radius * ring_index / rings
		var on_ring: int = per_ring[ring]
		# Offset every other ring by half a step so neighbours interleave instead
		# of lining up on the same spoke.
		var offset := 0.0 if ring % 2 == 0 else PI / maxi(on_ring, 1)
		for j in on_ring:
			var angle := TAU * j / on_ring + offset
			positions.append(Vector2(cos(angle), sin(angle)) * ring_radius)
	return positions


## How many concentric rings a count needs: one up to SINGLE_RING_MAX, then one
## more per SINGLE_RING_MAX players (9-16 -> 2, 17-24 -> 3).
static func ring_count(count: int) -> int:
	if count <= 1:
		return 1
	return ceili(float(count) / SINGLE_RING_MAX)


## Splits `count` across `rings`, weighting outer rings more (they have the room),
## and parks any rounding drift on the outermost ring. The total always sums to
## `count`, so ring_positions() returns exactly `count` positions.
static func _distribute(count: int, rings: int) -> Array[int]:
	var total_weight := 0
	for ring in rings:
		total_weight += ring + 1
	var per_ring: Array[int] = []
	var assigned := 0
	for ring in rings:
		var share := int(round(float(count) * (ring + 1) / total_weight))
		per_ring.append(share)
		assigned += share
	per_ring[rings - 1] += count - assigned
	return per_ring
