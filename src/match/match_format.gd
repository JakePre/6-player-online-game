class_name MatchFormat
extends RefCounted
## Pure text formatting for the match chrome (M3-04), split from the scene
## script so ranking/label logic is unit-testable.

const ORDINALS: Array[String] = ["1st", "2nd", "3rd", "4th", "5th", "6th"]

const CATEGORY_NAMES := {
	MinigameMeta.Category.FFA: "Free-for-all",
	MinigameMeta.Category.SKILL: "Skill",
	MinigameMeta.Category.TEAM: "Team",
	MinigameMeta.Category.SABOTAGE: "Sabotage",
}


static func ordinal(rank: int) -> String:
	if rank >= 1 and rank <= ORDINALS.size():
		return ORDINALS[rank - 1]
	return "%dth" % rank


static func category_name(category: int) -> String:
	return CATEGORY_NAMES.get(category, "?")


static func clock(seconds: float) -> String:
	var whole := maxi(ceili(seconds), 0)
	@warning_ignore("integer_division")
	return "%d:%02d" % [whole / 60, whole % 60]


static func player_name(names: Dictionary, slot: int) -> String:
	return names.get(slot, "Player %d" % (slot + 1))


## One line per player from tie-grouped placements: "1st  Alice  +30".
## Tied players share the rank; the next group's rank skips past them,
## matching how Economy awards coins.
static func result_lines(placements: Array, awards: Dictionary, names: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var rank := 1
	for group: Array in placements:
		for slot: int in group:
			lines.append(
				"%s  %s  +%d" % [ordinal(rank), player_name(names, slot), int(awards.get(slot, 0))]
			)
		rank += group.size()
	return lines


## Standings sorted by coins, ties sharing a rank: "1st  Alice  45".
## Ties order by slot so the list is stable frame to frame.
static func standings_lines(totals: Dictionary, names: Dictionary) -> Array[String]:
	var slots: Array = totals.keys()
	slots.sort_custom(
		func(a: int, b: int) -> bool:
			if int(totals[a]) != int(totals[b]):
				return int(totals[a]) > int(totals[b])
			return a < b
	)
	var lines: Array[String] = []
	var rank := 0
	var previous_score := -1
	for i in slots.size():
		var slot: int = slots[i]
		var score := int(totals[slot])
		if score != previous_score:
			rank = i + 1
			previous_score = score
		lines.append("%s  %s  %d" % [ordinal(rank), player_name(names, slot), score])
	return lines


## Series scoreboard lines (M11-02): rows are SeriesTracker.standings()
## entries ({slot, points, coins}), best first. "1st  Alice — 17 pts".
static func series_lines(rows: Array, names: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var rank := 0
	var previous := {"points": -1, "coins": -1}
	for i in rows.size():
		var row: Dictionary = rows[i]
		if row.points != previous.points or row.coins != previous.coins:
			rank = i
		previous = row
		lines.append(
			"%s  %s — %d pts" % [ordinal(rank + 1), player_name(names, int(row.slot)), row.points]
		)
	return lines
