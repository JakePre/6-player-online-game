class_name FishFrenzy
extends MinigameBase
## Fish Frenzy (#183, owner-requested): three lanes of incoming fish on a
## steady 600 ms cadence. Be standing in the right lane when a fish crosses
## the catch line to grab it; streaks pay bonus coins, misses reset them.
## Everyone fishes the same seeded school, so it is pure rhythm skill.
## Server-side simulation only — the client renders get_snapshot().

const LANES := 3
## Seconds between fish arrivals at the catch line (the owner's 600 ms).
const CADENCE_SEC := 0.6
## The cadence tightens to this by the end of the round.
const CADENCE_MIN_SEC := 0.42
const RAMP_SEC := 40.0
## How long a fish is catchable at the line before it escapes.
const CATCH_WINDOW_SEC := 0.3
## Fish travel time from spawn to the catch line (for the view's runway).
const SWIM_SEC := 1.8
const STREAK_EVERY := 5
const STREAK_BONUS := 1

var lane := {}
var caught := {}
var streak := {}
## Incoming fish, each {lane: int, arrives_at: float, caught_by: int (-1)}.
var fish: Array[Dictionary] = []

var _next_spawn_at := 0.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"fish_frenzy",
				"controls": "Switch lane — W/S / stick up-down",
				"name": "Fish Frenzy",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 6,
				"duration_sec": 60.0,
				"rules":
				"Fish arrive on the beat — be in their lane at the line! Streaks pay extra.",
			}
		)
	)


func _setup() -> void:
	for slot: int in slots:
		lane[slot] = 1
		caught[slot] = 0
		streak[slot] = 0
	_next_spawn_at = SWIM_SEC


func cadence() -> float:
	return lerpf(CADENCE_SEC, CADENCE_MIN_SEC, clampf(elapsed / RAMP_SEC, 0.0, 1.0))


## Lane switches snap to a lane index the client computed from a press.
func _handle_input(slot: int, data: Dictionary) -> void:
	if data.has("lane"):
		lane[slot] = clampi(int(data.lane), 0, LANES - 1)


func _tick(_delta: float) -> void:
	if elapsed >= _next_spawn_at - SWIM_SEC:
		_next_spawn_at += cadence()
		fish.append(
			{"lane": rng.randi_range(0, LANES - 1), "arrives_at": _next_spawn_at, "caught_by": -1}
		)
	for i in range(fish.size() - 1, -1, -1):
		var arrival: float = fish[i].arrives_at
		if elapsed < arrival:
			continue
		if elapsed <= arrival + CATCH_WINDOW_SEC:
			_try_catch(i)
			if int(fish[i].caught_by) >= 0:
				fish.remove_at(i)
			continue
		# Escaped: everyone in its lane whiffed — their streaks die.
		for slot: int in slots:
			if int(lane[slot]) == int(fish[i].lane):
				streak[slot] = 0
		fish.remove_at(i)


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		players[slot] = [int(lane[slot]), int(caught[slot]), int(streak[slot])]
	var fish_list: Array = []
	for entry in fish:
		fish_list.append([int(entry.lane), snappedf(float(entry.arrives_at) - elapsed, 0.01)])
	return {"players": players, "fish": fish_list, "swim_sec": SWIM_SEC}


## Most fish wins, ties grouped; catches double as capped pickup coins.
func _rank_players() -> Array:
	var by_count := {}
	for slot: int in slots:
		var count: int = caught[slot]
		if not by_count.has(count):
			by_count[count] = []
		by_count[count].append(slot)
	var counts := by_count.keys()
	counts.sort()
	counts.reverse()
	var placements: Array = []
	for count: int in counts:
		placements.append(by_count[count])
	_pickup_coins = caught.duplicate()
	return placements


## First player standing in the fish's lane catches it — everyone had the
## same beat to be there.
func _try_catch(index: int) -> void:
	var fish_lane: int = fish[index].lane
	for slot: int in slots:
		if int(lane[slot]) != fish_lane:
			continue
		fish[index].caught_by = slot
		caught[slot] = int(caught[slot]) + 1
		streak[slot] = int(streak[slot]) + 1
		if int(streak[slot]) % STREAK_EVERY == 0:
			caught[slot] = int(caught[slot]) + STREAK_BONUS
		return
