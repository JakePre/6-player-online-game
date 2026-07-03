class_name SeriesTracker
extends RefCounted
## Best-of-N series (M11-01, PHASE2.md $5): chains full matches into a night.
## Match placements convert to series points — 10/7/5/4/3/2 for 1st..6th,
## tied slots sharing the higher value (SPEC $5 tie semantics) — and the
## grand champion is decided on points, with series ties broken by total
## match coins earned across the series. Pure logic; Room owns an instance.

## Points by placement rank (0 = 1st).
const POINTS: Array[int] = [10, 7, 5, 4, 3, 2]

## Number of matches in the series: 1 = plain single match (tracker idle).
var length := 1
var matches_played := 0
var points := {}
## Total match coins earned per slot across the series (the tiebreak).
var coins := {}


func is_active() -> bool:
	return length > 1


func is_complete() -> bool:
	return is_active() and matches_played >= length


func reset(new_length: int = length) -> void:
	length = new_length
	matches_played = 0
	points = {}
	coins = {}


## A member left the room for good (leave/kick): their series entry goes
## with them, so a newcomer reusing the slot starts clean (M11-03).
func drop_slot(slot: int) -> void:
	points.erase(slot)
	coins.erase(slot)


## Records one finished match from match_ended standings rows
## ({slot, name, score}, best first). Equal scores form a tie group and
## share the higher points value.
func record_match(standings: Array) -> void:
	if not is_active():
		return
	matches_played += 1
	var rank := 0
	var i := 0
	while i < standings.size():
		# Collect the tie group: consecutive rows with the same match score.
		var group: Array = [standings[i]]
		while i + group.size() < standings.size():
			var next: Dictionary = standings[i + group.size()]
			if int(next.score) != int(standings[i].score):
				break
			group.append(next)
		var value: int = POINTS[mini(rank, POINTS.size() - 1)]
		for row: Dictionary in group:
			var slot := int(row.slot)
			points[slot] = int(points.get(slot, 0)) + value
			coins[slot] = int(coins.get(slot, 0)) + int(row.score)
		rank += group.size()
		i += group.size()


## Series standings rows, best first: {slot, points, coins}. Sorted by
## points, then the coin tiebreak; exact ties stay adjacent (equal keys).
func standings() -> Array:
	var rows: Array = []
	for slot: int in points:
		rows.append({"slot": slot, "points": int(points[slot]), "coins": int(coins.get(slot, 0))})
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a.points != b.points:
				return a.points > b.points
			return a.coins > b.coins
	)
	return rows


## The champion slot group once the series is complete (ties only when both
## points and coins are identical).
func champions() -> Array:
	if not is_complete():
		return []
	var rows := standings()
	if rows.is_empty():
		return []
	var best: Dictionary = rows[0]
	var out: Array = []
	for row: Dictionary in rows:
		if row.points == best.points and row.coins == best.coins:
			out.append(int(row.slot))
	return out


## Snapshot for room state / the M11-02 scoreboard.
func to_dict() -> Dictionary:
	return {
		"length": length,
		"matches_played": matches_played,
		"standings": standings(),
		"complete": is_complete(),
	}
