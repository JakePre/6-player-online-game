class_name Economy
extends RefCounted
## Coin awards (SPEC $5). Pure static logic, unit-tested.

## Placement awards for FFA games, index = placement rank (0 = 1st). These are
## the SPEC $5 locked values for the top places; `placement_award()` tapers
## past the table for larger fields (up to 24, ADR 003).
const PLACEMENT_AWARDS: Array[int] = [30, 20, 15, 10, 5, 3]
## Floor a placement can taper to past the listed table — everyone still banks
## a little (design pillar: "everyone stays in it").
const PLACEMENT_FLOOR := 1
## Per-round cap on coins collected as in-game pickups.
const PICKUP_CAP := 30
## Team awards: [two teams: winner/loser, three teams: 1st/2nd/3rd]
const TWO_TEAM_AWARDS: Array[int] = [20, 5]
const THREE_TEAM_AWARDS: Array[int] = [25, 15, 5]


## Coins for finishing at `rank` (0 = 1st) in an FFA game. Uses the SPEC $5
## table for the listed places, then tapers by 1 coin per place to a 1-coin
## floor so a large field (up to 24) still ranks fairly and never pays a worse
## placement more than a better one.
static func placement_award(rank: int) -> int:
	if rank < PLACEMENT_AWARDS.size():
		return PLACEMENT_AWARDS[rank]
	var last_listed: int = PLACEMENT_AWARDS[PLACEMENT_AWARDS.size() - 1]
	var steps_past := rank - (PLACEMENT_AWARDS.size() - 1)
	return maxi(PLACEMENT_FLOOR, last_listed - steps_past)


## Coins for a team finishing at `place` (0 = best) out of `team_count` teams.
## Keeps the SPEC $5 two-/three-team tables exactly; for 4+ teams (large
## lobbies, ADR 003) it tapers linearly from the three-team top (25) to the
## loser floor (5).
static func team_award(place: int, team_count: int) -> int:
	if team_count <= 2:
		return TWO_TEAM_AWARDS[mini(place, TWO_TEAM_AWARDS.size() - 1)]
	if team_count == 3:
		return THREE_TEAM_AWARDS[mini(place, THREE_TEAM_AWARDS.size() - 1)]
	var top: int = THREE_TEAM_AWARDS[0]
	var team_floor: int = TWO_TEAM_AWARDS[TWO_TEAM_AWARDS.size() - 1]
	if place >= team_count - 1:
		return team_floor
	var t := float(place) / float(team_count - 1)
	return int(round(lerpf(float(top), float(team_floor), t)))


## `placements` is an array of rank groups, each an array of slots; slots in
## the same group are tied and share the higher award. Returns {slot: coins}.
static func award_for_placements(placements: Array) -> Dictionary:
	var awards := {}
	var rank := 0
	for group: Array in placements:
		var value := placement_award(rank)
		for slot: int in group:
			awards[slot] = value
		rank += group.size()
	return awards


## `team_placements` is an array of teams ordered best-first, each an array of
## member slots. Every member of a team gets that team's award.
static func award_for_teams(team_placements: Array) -> Dictionary:
	var awards := {}
	for i in team_placements.size():
		var value := team_award(i, team_placements.size())
		for slot: int in team_placements[i]:
			awards[slot] = value
	return awards


## Combine placement awards with capped pickup coins. Returns {slot: coins}.
## `pickup_cap` lets mutators scale the cap (M9-04, Golden Round).
static func total_round_award(
	placements: Array, pickup_coins: Dictionary, pickup_cap: int = PICKUP_CAP
) -> Dictionary:
	var awards := award_for_placements(placements)
	for slot: int in pickup_coins:
		awards[slot] = int(awards.get(slot, 0)) + mini(int(pickup_coins[slot]), pickup_cap)
	return awards


## Team-game counterpart of total_round_award: team awards plus capped
## pickup coins. `team_placements` is teams best-first, each an array of
## member slots. Returns {slot: coins}.
static func total_team_round_award(
	team_placements: Array, pickup_coins: Dictionary, pickup_cap: int = PICKUP_CAP
) -> Dictionary:
	var awards := award_for_teams(team_placements)
	for slot: int in pickup_coins:
		awards[slot] = int(awards.get(slot, 0)) + mini(int(pickup_coins[slot]), pickup_cap)
	return awards
