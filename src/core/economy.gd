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


## `team_placements` is an array of rank groups ordered best-first, each an
## array of member slots. A group normally holds one team, but TIED teams are
## merged into one group (the sims' tie convention) — every slot in a group
## gets the same award, and ties share the higher award (SPEC §5, #811).
##
## `team_count` is the true number of teams in the game; it picks the award
## table and advances the rank past a merged group by how many teams it
## holds (derivable because team games split evenly — `even_players`). The
## default 0 means "one team per group" (the pre-#811 call shape), which is
## exact whenever nothing tied.
static func award_for_teams(team_placements: Array, team_count: int = 0) -> Dictionary:
	if team_count <= 0:
		team_count = team_placements.size()
	var total_slots := 0
	for group: Array in team_placements:
		total_slots += group.size()
	var slots_per_team := maxi(1, total_slots / maxi(team_count, 1))
	var awards := {}
	var rank := 0
	for group: Array in team_placements:
		var value := team_award(rank, team_count)
		for slot: int in group:
			awards[slot] = value
		rank += maxi(1, group.size() / slots_per_team)
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
## pickup coins. `team_placements` is rank groups best-first (tied teams
## merged, see award_for_teams); `team_count` is the true team count (0 =
## one team per group). Returns {slot: coins}.
static func total_team_round_award(
	team_placements: Array,
	pickup_coins: Dictionary,
	pickup_cap: int = PICKUP_CAP,
	team_count: int = 0
) -> Dictionary:
	var awards := award_for_teams(team_placements, team_count)
	for slot: int in pickup_coins:
		awards[slot] = int(awards.get(slot, 0)) + mini(int(pickup_coins[slot]), pickup_cap)
	return awards
