class_name MatchAwards
extends RefCounted
## End-of-match superlatives (#934): the results-screen roast. A pure pass
## that derives up to five punchy awards from data the match ALREADY tracks —
## per-round placements + pickup coins, the final standings, and the finale's
## attributed KOs (#706). No new per-game counters here; those (shoves,
## catches, travel → Bully/Golden Arm/Tourist) ride follow-ups on this frame.
##
## derive() returns an ordered Array of {id, title, icon, slot} — the server
## puts it on the additive match_ended `awards` key, the results screen shows
## a line per award, and StatsStore tallies lifetime counts. Deterministic:
## every tie breaks to the lowest slot so all peers agree.

## Each award: the id (StatsStore key), the display title, and an emoji icon.
const FRONTRUNNER := {"id": &"frontrunner", "title": "Frontrunner", "icon": "🥇"}
const COIN_BARON := {"id": &"coin_baron", "title": "Coin Baron", "icon": "💰"}
const CLUTCH := {"id": &"clutch", "title": "Clutch", "icon": "🔥"}
const ASSASSIN := {"id": &"assassin", "title": "Assassin", "icon": "💀"}
const WOODEN_SPOON := {"id": &"wooden_spoon", "title": "Wooden Spoon", "icon": "🥄"}


## `round_records`: per round, {placements: [[slot,...],...] best-first,
## pickup_coins: {slot: n}, totals_before: {slot: coins}} — captured before the
## round's award landed (for the last-place-comeback read). `standings`: final
## rows best-first, each with a `slot`. `finale_kos`: {slot: attributed KOs}.
static func derive(round_records: Array, standings: Array, finale_kos: Dictionary) -> Array:
	var round_wins := {}
	var coins := {}
	var clutch := {}
	for record: Dictionary in round_records:
		var placements: Array = record.get("placements", [])
		if placements.is_empty():
			continue
		var winners: Array = placements[0]
		var totals_before: Dictionary = record.get("totals_before", {})
		var trailing := _trailing_slots(totals_before)
		for slot: int in winners:
			round_wins[slot] = int(round_wins.get(slot, 0)) + 1
			if slot in trailing:
				clutch[slot] = int(clutch.get(slot, 0)) + 1
		var pickups: Dictionary = record.get("pickup_coins", {})
		for slot: Variant in pickups:
			coins[int(slot)] = int(coins.get(int(slot), 0)) + int(pickups[slot])

	var awards: Array = []
	_append(awards, FRONTRUNNER, _leader(round_wins))
	_append(awards, COIN_BARON, _leader(coins))
	_append(awards, CLUTCH, _leader(clutch))
	_append(awards, ASSASSIN, _leader(finale_kos))
	# The good-natured roast: dead last in the final standings (2+ players).
	if standings.size() >= 2:
		_append(awards, WOODEN_SPOON, int((standings[standings.size() - 1] as Dictionary).slot))
	return awards


## The slot(s) with the lowest coin total in `totals` — the ones a round win
## would be a genuine comeback from. Empty when totals is empty.
static func _trailing_slots(totals: Dictionary) -> Array:
	if totals.is_empty():
		return []
	var low := INF
	for slot: Variant in totals:
		low = minf(low, float(totals[slot]))
	var out: Array = []
	for slot: Variant in totals:
		if is_equal_approx(float(totals[slot]), low):
			out.append(int(slot))
	return out


## The slot with the greatest positive count, ties to the lowest slot; -1 when
## no one has a positive count (so the award simply isn't given).
static func _leader(counts: Dictionary) -> int:
	var best := -1
	var best_count := 0
	for slot: Variant in counts:
		var count := int(counts[slot])
		if count <= 0:
			continue
		if count > best_count or (count == best_count and (best == -1 or int(slot) < best)):
			best_count = count
			best = int(slot)
	return best


static func _append(awards: Array, award: Dictionary, slot: int) -> void:
	if slot < 0:
		return
	awards.append({"id": award.id, "title": award.title, "icon": award.icon, "slot": slot})
