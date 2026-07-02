class_name FinaleRanking
extends RefCounted
## Final match ranking (M5-03, SPEC $6): the Gauntlet's elimination order
## decides placement; ties break by leftover coins (after the buy-in shop),
## then by total coins earned in the match. Only exact ties stay grouped.
## Pure static logic; the podium (M3-05) renders what this produces.


## `gauntlet_placements` is the Gauntlet's tie-grouped results (M5-02),
## `coins_left` is FinaleShop's post-shop balance per slot (M5-01), and
## `coins_earned` is each slot's total match coins before the shop. Returns
## placements in the same tie-group shape, with groups split wherever the
## coin tiebreaks can order them.
static func rank(
	gauntlet_placements: Array, coins_left: Dictionary, coins_earned: Dictionary
) -> Array:
	var placements: Array = []
	for group: Array in gauntlet_placements:
		placements += _break_ties(group, coins_left, coins_earned)
	return placements


## Podium-ready rows ordered best-first: {slot: int, placement: int} with
## tied slots sharing a placement number (1st, 1st, 3rd...).
static func standings(
	gauntlet_placements: Array, coins_left: Dictionary, coins_earned: Dictionary
) -> Array:
	var rows: Array = []
	var placement := 1
	for group: Array in rank(gauntlet_placements, coins_left, coins_earned):
		for slot: int in group:
			rows.append({"slot": slot, "placement": placement})
		placement += group.size()
	return rows


static func _break_ties(group: Array, coins_left: Dictionary, coins_earned: Dictionary) -> Array:
	if group.size() <= 1:
		return [group.duplicate()]
	var sorted := group.duplicate()
	sorted.sort_custom(
		func(a: int, b: int) -> bool:
			return _key(a, coins_left, coins_earned) > _key(b, coins_left, coins_earned)
	)
	var groups: Array = []
	for slot: int in sorted:
		if (
			groups.is_empty()
			or _key(groups[-1][0], coins_left, coins_earned) != _key(slot, coins_left, coins_earned)
		):
			groups.append([])
		groups[-1].append(slot)
	return groups


static func _key(slot: int, coins_left: Dictionary, coins_earned: Dictionary) -> Array:
	return [int(coins_left.get(slot, 0)), int(coins_earned.get(slot, 0))]
