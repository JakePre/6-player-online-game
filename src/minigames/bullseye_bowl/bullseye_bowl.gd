class_name BullseyeBowl
extends MinigameBase
## Bullseye Bowl (M10-07, PHASE2.md $4 #24): every player rolls balls down
## their own lane at a sliding ring target — the ball takes time to arrive,
## so you lead the shot. Limited balls; best total wins.
## Server-side simulation only — the client renders get_snapshot().

const LANE_LENGTH := 12.0
const LANE_SPACING := 3.0
const BALLS := 8
const FLIGHT_SEC := 1.2
const ROLL_COOLDOWN_SEC := 0.4
## Target oscillation across the lane.
const TARGET_AMPLITUDE := 2.2
const TARGET_PERIOD_SEC := 2.6
## Ring radii -> points (checked in order).
const RING_BULLSEYE := 0.45
const RING_MID := 1.0
const RING_OUTER := 1.8
const SCORE_BULLSEYE := 5
const SCORE_MID := 3
const SCORE_OUTER := 1

## get_snapshot() wire shape (#708): named indices for the players positional
## array. Array SHAPE on the wire is unchanged — additive only.
const PS_SCORE := 0
const PS_BALLS_LEFT := 1
const PS_FLIGHT_T := 2
const PS_TARGET_OFFSET := 3
const PS_COUNT := 4

var scores := {}
var balls_left := {}
## In-flight balls: {slot, t (0..1 progress)}. One per player at most.
var flights: Array = []

var _cooldowns := {}
var _phases := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"bullseye_bowl",
				"controls": "Roll — SPACE / pad A (lead the sliding target!)",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				["Roll — ", {"action": &"action_primary"}, " (lead the sliding target!)"],
				"name": "Bullseye Bowl",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 45.0,
				"rules":
				"8 balls, one sliding target each. The ball takes a beat to arrive — lead it.",
			}
		)
	)


func _setup() -> void:
	for slot: int in slots:
		scores[slot] = 0
		balls_left[slot] = BALLS
		_cooldowns[slot] = 0.0
		_phases[slot] = rng.randf_range(0.0, TAU)


func _handle_input(slot: int, data: Dictionary) -> void:
	if slot not in slots or not data.get("roll", false):
		return
	if balls_left[slot] <= 0 or _cooldowns[slot] > 0.0 or _has_flight(slot):
		return
	balls_left[slot] -= 1
	_cooldowns[slot] = ROLL_COOLDOWN_SEC
	flights.append({"slot": slot, "t": 0.0})


func _tick(delta: float) -> void:
	if finished:
		return
	for slot: int in slots:
		_cooldowns[slot] = maxf(_cooldowns[slot] - delta, 0.0)
	var remaining: Array = []
	for flight: Dictionary in flights:
		flight.t += delta / FLIGHT_SEC
		if flight.t < 1.0:
			remaining.append(flight)
			continue
		scores[flight.slot] += _ring_points(absf(target_offset(flight.slot)))
	flights = remaining
	if _all_balls_spent():
		finish(_rank_players())


## Where the slot's target sits right now (offset across the lane).
func target_offset(slot: int) -> float:
	return TARGET_AMPLITUDE * sin(TAU * elapsed / TARGET_PERIOD_SEC + float(_phases[slot]))


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var flight_t := -1.0
		for flight: Dictionary in flights:
			if flight.slot == slot:
				flight_t = flight.t
				break
		players[slot] = [
			scores[slot],
			balls_left[slot],
			snappedf(flight_t, 0.01),
			snappedf(target_offset(slot), 0.01),
		]
	return {"players": players}


## Best total wins; ties share a group (Target Range convention: no pickups).
func _rank_players() -> Array:
	var by_score := {}
	for slot: int in slots:
		var score: int = scores[slot]
		if not by_score.has(score):
			by_score[score] = []
		by_score[score].append(slot)
	var counts := by_score.keys()
	counts.sort()
	counts.reverse()
	var placements: Array = []
	for count: int in counts:
		placements.append(by_score[count])
	return placements


func _ring_points(distance: float) -> int:
	if distance <= RING_BULLSEYE:
		return SCORE_BULLSEYE
	if distance <= RING_MID:
		return SCORE_MID
	if distance <= RING_OUTER:
		return SCORE_OUTER
	return 0


func _has_flight(slot: int) -> bool:
	for flight: Dictionary in flights:
		if flight.slot == slot:
			return true
	return false


func _all_balls_spent() -> bool:
	if not flights.is_empty():
		return false
	for slot: int in slots:
		if balls_left[slot] > 0:
			return false
	return true
