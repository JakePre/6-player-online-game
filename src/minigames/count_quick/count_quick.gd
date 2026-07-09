class_name CountQuick
extends MinigameBase
## Count Quick (M10-08, PHASE2.md $4 #25): a swarm of objects flashes on
## screen, then hides — run to the answer pad with the right count. Locking
## first and right pays double. Best total after six rounds wins.
## Server-side simulation only — the client renders get_snapshot().

enum Phase { FLASH, ANSWER }

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const PAD_RADIUS := 1.3
const FLASH_SEC := 2.2
const ANSWER_SEC := 5.0
const ROUNDS := 6
const SWARM_MIN := 8
const SWARM_MAX := 24
const SCORE_FIRST := 2
const SCORE_CORRECT := 1
## Answer pads sit on the arena diagonals at this distance.
const PAD_DISTANCE := 6.0

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_SCORE := 2
const PS_LOCKED := 3
const PS_COUNT := 4

const SW_X := 0
const SW_Y := 1

const PD_X := 0
const PD_Y := 1
const PD_VALUE := 2

var positions := {}
var move_dirs := {}
var scores := {}
## slot -> pad index locked this round (-1 = still free to choose).
var locked := {}
var phase := Phase.FLASH
var round_number := 0
## Swarm positions (only replicated during FLASH).
var swarm: Array = []
## Four answer pads: {pos: Vector2, value: int}.
var pads: Array = []
var correct_count := 0

var _phase_left := FLASH_SEC
var _first_correct_taken := false


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"count_quick",
				"controls": "Move — WASD / left stick (run onto a pad to lock your answer)",
				"name": "Count Quick",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 60.0,
				"rules":
				"Count the swarm before it vanishes, then run to the right number. First correct pays double!",
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * 2.0
		move_dirs[slots[i]] = Vector2.ZERO
		scores[slots[i]] = 0
		locked[slots[i]] = -1
	_deal_round()


func _handle_input(slot: int, data: Dictionary) -> void:
	if slot not in slots:
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	if finished:
		return
	for slot: int in slots:
		if locked[slot] != -1:
			continue  # a locked answer parks you on your pad
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.limit_length(ARENA_HALF)
	if phase == Phase.ANSWER:
		_resolve_locks()
	_phase_left -= delta
	if _phase_left <= 0.0 or (phase == Phase.ANSWER and _all_locked()):
		_advance_phase()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			scores[slot],
			1 if locked[slot] != -1 else 0,
		]
	var swarm_list: Array = []
	if phase == Phase.FLASH:
		for pos: Vector2 in swarm:
			swarm_list.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)])
	var pad_list: Array = []
	if phase == Phase.ANSWER:
		for pad: Dictionary in pads:
			var pos: Vector2 = pad.pos
			pad_list.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), pad.value])
	return {
		"players": players,
		"phase": phase,
		"swarm": swarm_list,
		"pads": pad_list,
		"round": round_number,
	}


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


## Touching a pad locks it as your answer for the round — no take-backs.
## Correct answers score immediately; the first correct one pays double.
## Same-tick correct locks are a tie group (like Thin Ice falls / Hot Potato
## blasts): everyone in it gets the first-correct double, so slot order never
## decides a photo finish.
func _resolve_locks() -> void:
	var correct_this_tick: Array[int] = []
	for slot: int in slots:
		if locked[slot] != -1:
			continue
		for pad_index in pads.size():
			var pad: Dictionary = pads[pad_index]
			if positions[slot].distance_to(pad.pos) > PAD_RADIUS + PLAYER_RADIUS:
				continue
			locked[slot] = pad_index
			if int(pad.value) == correct_count:
				correct_this_tick.append(slot)
			break
	for slot: int in correct_this_tick:
		scores[slot] += SCORE_CORRECT if _first_correct_taken else SCORE_FIRST
	if not correct_this_tick.is_empty():
		_first_correct_taken = true


func _advance_phase() -> void:
	if phase == Phase.FLASH:
		phase = Phase.ANSWER
		_phase_left = ANSWER_SEC
		return
	round_number += 1
	if round_number >= ROUNDS:
		finish(_rank_players())
		return
	_deal_round()
	phase = Phase.FLASH
	_phase_left = FLASH_SEC


func _deal_round() -> void:
	correct_count = rng.randi_range(SWARM_MIN, SWARM_MAX)
	swarm = []
	for _i in correct_count:
		swarm.append(
			Vector2(
				rng.randf_range(-ARENA_HALF * 0.7, ARENA_HALF * 0.7),
				rng.randf_range(-ARENA_HALF * 0.7, ARENA_HALF * 0.7)
			)
		)
	var values: Array = [correct_count]
	while values.size() < 4:
		var offset := rng.randi_range(1, 3) * (1 if rng.randf() < 0.5 else -1)
		var candidate := maxi(correct_count + offset, 1)
		if candidate not in values:
			values.append(candidate)
	# Pad placement randomizes via seeded pop_at draws below (Array.shuffle()
	# would use the global RNG and break determinism).
	pads = []
	var corners: Array[Vector2] = [
		Vector2(-PAD_DISTANCE, -PAD_DISTANCE),
		Vector2(PAD_DISTANCE, -PAD_DISTANCE),
		Vector2(-PAD_DISTANCE, PAD_DISTANCE),
		Vector2(PAD_DISTANCE, PAD_DISTANCE),
	]
	for i in 4:
		var pick := rng.randi_range(0, values.size() - 1)
		pads.append({"pos": corners[i], "value": values.pop_at(pick)})
	for slot: int in slots:
		locked[slot] = -1
	_first_correct_taken = false


## #819: only the humans need to lock in — a bot that never finds its pad
## (miscounted, or its brain stalls) shouldn't hold the room to the full
## ANSWER_SEC timer.
func _all_locked() -> bool:
	for slot: int in _human_slots():
		if locked[slot] == -1:
			return false
	return true
