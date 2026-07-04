class_name MinigameScaling
extends RefCounted
## Player-count scaling helpers (M15-04, ADR 003 F4). The minigames were tuned
## for a 6-player baseline; when a larger lobby (up to 24) plays, games call
## these to grow their arena and resource supply so per-player floor area and
## per-capita pacing stay fair. Pure static logic, unit-tested.
##
## Spawn *placement* (where players stand) is a separate concern — see the
## spawn-layout helper (M15-05). This is arena size + economy supply only.

## The player count the current minigames are balanced around.
const BASELINE_PLAYERS := 6


## Growth factor for a lobby of `player_count` relative to `baseline`, never
## below 1.0 — small lobbies keep the tuned values, only larger ones scale up.
static func growth(player_count: int, baseline: int = BASELINE_PLAYERS) -> float:
	return maxf(1.0, float(player_count) / float(maxi(1, baseline)))


## Scales a linear arena dimension (e.g. ARENA_HALF) so per-player floor area
## stays roughly constant: area grows with headcount, so a side length grows
## with its square root. Never shrinks below the baseline size.
static func arena_half(
	base_half: float, player_count: int, baseline: int = BASELINE_PLAYERS
) -> float:
	return base_half * sqrt(growth(player_count, baseline))


## Scales a resource supply (coins/dishes/pellets per wave, active caps) with
## headcount so per-capita availability stays constant. Never below baseline.
static func supply(base_amount: int, player_count: int, baseline: int = BASELINE_PLAYERS) -> int:
	return maxi(base_amount, roundi(float(base_amount) * growth(player_count, baseline)))
