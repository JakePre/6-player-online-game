class_name CountQuick
extends MinigameBase
## Count Quick (M10-08, PHASE2.md $4 #25): a swarm of objects flashes on
## screen, then hides — run to the answer pad with the right count. There is no
## lock-in (#799): you can move between pads the whole answer phase, and the pad
## you stand on when the timer ends is your answer. Best total after six rounds
## wins. Server-side simulation only — the client renders get_snapshot().

enum Phase { FLASH, ANSWER }

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const PAD_RADIUS := 1.3
## Longer than the original 2.2/5.0 (#799): the owner reported (twice) there was
## no time to count the swarm, and too little time to commit an answer.
const FLASH_SEC := 4.0
const ANSWER_SEC := 6.0
const ROUNDS := 6
const SWARM_MIN := 8
const SWARM_MAX := 24
## One point per correct answer at the buzzer. (The old first-correct double was
## a lock-race artifact — with no lock-in there is no race, #799.)
const SCORE_CORRECT := 1
## Answer pads sit on the arena diagonals at this distance.
const PAD_DISTANCE := 6.0

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_SCORE := 2
## The value of the pad the player is currently standing on during ANSWER (their
## live, still-changeable pick), or -1 for none / during FLASH. Was PS_LOCKED
## (a bool) before lock-in was removed (#799).
const PS_ANSWER := 3
const PS_COUNT := 4

const SW_X := 0
const SW_Y := 1

const PD_X := 0
const PD_Y := 1
const PD_VALUE := 2

var positions := {}
var move_dirs := {}
var scores := {}
var phase := Phase.FLASH
var round_number := 0
## Swarm positions (only replicated during FLASH).
var swarm: Array = []
## Four answer pads: {pos: Vector2, value: int}.
var pads: Array = []
var correct_count := 0

var _phase_left := FLASH_SEC


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"count_quick",
				"controls": "Move — WASD / left stick (stand on the number you counted)",
				"name": "Count Quick",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 72.0,
				"rules":
				(
					"Count the swarm before it vanishes, then stand on the right number."
					+ " No lock-in — change your pick until the timer ends. Most right wins!"
				),
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * 2.0
		move_dirs[slots[i]] = Vector2.ZERO
		scores[slots[i]] = 0
	_deal_round()


func _handle_input(slot: int, data: Dictionary) -> void:
	if slot not in slots:
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	if finished:
		return
	# Everyone moves freely the whole time — no pad ever freezes a player, so
	# spawning on a pad no longer auto-commits a wrong answer (#799).
	for slot: int in slots:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.limit_length(ARENA_HALF)
	_phase_left -= delta
	if _phase_left <= 0.0:
		_advance_phase()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			scores[slot],
			_answer_of(slot) if phase == Phase.ANSWER else -1,
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


## The value of the pad the player currently stands on, or -1 if they are not
## on any pad — their live answer, read fresh every tick (no stored lock).
func _answer_of(slot: int) -> int:
	for pad: Dictionary in pads:
		if positions[slot].distance_to(pad.pos) <= PAD_RADIUS + PLAYER_RADIUS:
			return int(pad.value)
	return -1


## Scored once, when the ANSWER phase ends: everyone standing on the correct
## pad at the buzzer takes a point. No first-correct bonus — with no lock-in
## there is no race to reward, only whether you counted right (#799).
func _score_answers() -> void:
	for slot: int in slots:
		if _answer_of(slot) == correct_count:
			scores[slot] += SCORE_CORRECT


func _advance_phase() -> void:
	if phase == Phase.FLASH:
		phase = Phase.ANSWER
		_phase_left = ANSWER_SEC
		return
	_score_answers()
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
