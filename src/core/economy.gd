class_name Economy
extends RefCounted
## Coin awards (SPEC $5). Pure static logic, unit-tested.

## Placement awards for FFA games, index = placement rank (0 = 1st).
const PLACEMENT_AWARDS: Array[int] = [30, 20, 15, 10, 5, 3]
## Per-round cap on coins collected as in-game pickups.
const PICKUP_CAP := 30
## Team awards: [two teams: winner/loser, three teams: 1st/2nd/3rd]
const TWO_TEAM_AWARDS: Array[int] = [20, 5]
const THREE_TEAM_AWARDS: Array[int] = [25, 15, 5]


## `placements` is an array of rank groups, each an array of slots; slots in
## the same group are tied and share the higher award. Returns {slot: coins}.
static func award_for_placements(placements: Array) -> Dictionary:
	var awards := {}
	var rank := 0
	for group: Array in placements:
		var value: int = PLACEMENT_AWARDS[mini(rank, PLACEMENT_AWARDS.size() - 1)]
		for slot: int in group:
			awards[slot] = value
		rank += group.size()
	return awards


## `team_placements` is an array of teams ordered best-first, each an array of
## member slots. Every member of a team gets that team's award.
static func award_for_teams(team_placements: Array) -> Dictionary:
	var table := TWO_TEAM_AWARDS if team_placements.size() <= 2 else THREE_TEAM_AWARDS
	var awards := {}
	for i in team_placements.size():
		var value: int = table[mini(i, table.size() - 1)]
		for slot: int in team_placements[i]:
			awards[slot] = value
	return awards


## Combine placement awards with capped pickup coins. Returns {slot: coins}.
static func total_round_award(placements: Array, pickup_coins: Dictionary) -> Dictionary:
	var awards := award_for_placements(placements)
	for slot: int in pickup_coins:
		awards[slot] = int(awards.get(slot, 0)) + mini(int(pickup_coins[slot]), PICKUP_CAP)
	return awards


## Team-game counterpart of total_round_award: team awards plus capped
## pickup coins. `team_placements` is teams best-first, each an array of
## member slots. Returns {slot: coins}.
static func total_team_round_award(team_placements: Array, pickup_coins: Dictionary) -> Dictionary:
	var awards := award_for_teams(team_placements)
	for slot: int in pickup_coins:
		awards[slot] = int(awards.get(slot, 0)) + mini(int(pickup_coins[slot]), PICKUP_CAP)
	return awards
