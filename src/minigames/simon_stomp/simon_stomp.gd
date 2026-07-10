class_name SimonStomp
extends MinigameBase
## Simon Stomp (M4-05, SPEC $7 #5): a Simon-says memory duel on four colored
## stomp pads. Each round the server flashes a growing sequence (SHOW), then
## every player must reproduce it in order by stomping pads (INPUT). A wrong
## pad eliminates that player for the rest of the game; clearing the sequence
## keeps them in and lengthens the next one. Players are ranked by how many
## rounds they cleared, so ties (e.g. everyone busting on the same round) group
## naturally. Server-side simulation only — the client renders get_snapshot(),
## which hides the sequence except during SHOW so it can't be read off the wire.

enum Phase {
	SHOW,
	INPUT,
	RESULT,
}

const PAD_COUNT := 4
const START_LENGTH := 2
const MAX_ROUNDS := 8
## A beat of anticipation before the first pad flashes each round — without it
## the very first flash lands the instant SHOW starts, before eyes settle on
## the pads, and players miss it (#588).
const SHOW_LEAD_IN_SEC := 0.6
## Per-pad reveal time; the whole SHOW phase scales with sequence length.
const SHOW_PER_PAD_SEC := 0.6
const INPUT_TIMEOUT_SEC := 8.0
const RESULT_SEC := 1.5

var phase: Phase = Phase.SHOW
var round_index := 0
var round_elapsed := 0.0
var sequence: Array[int] = []

var alive := {}
var cleared_count := {}
## Per-round bookkeeping, reset in _start_round.
var progress := {}
var round_cleared := {}
var round_failed := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"simon_stomp",
				"name": "Simon Stomp",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 120.0,
				"rules":
				"Watch the pads flash, then stomp them back in order. One slip and you're out!",
				"controls": "Stomp pads — WASD / left stick (N/E/S/W)",
				# Structured spec (#832/#844): the pad-stomp template shape (matches
				# beat_bounce's — the four directions collapse to the move cluster,
				# avoiding a per-axis row since those have no gamepad button glyph).
				"control_spec":
				[{"verb": "Stomp", "input": InputGlyphs.CLUSTER_MOVE, "note": "N/E/S/W"}],
			}
		)
	)


func _setup() -> void:
	for slot: int in slots:
		alive[slot] = true
		cleared_count[slot] = 0
	_start_round()


func _handle_input(slot: int, data: Dictionary) -> void:
	if phase != Phase.INPUT or not alive.get(slot, false):
		return
	if round_cleared.get(slot, false) or round_failed.get(slot, false):
		return
	var pad := int(data.get("pad", -1))
	if pad < 0 or pad >= PAD_COUNT:
		return
	var index: int = progress.get(slot, 0)
	if pad == sequence[index]:
		index += 1
		progress[slot] = index
		if index >= sequence.size():
			round_cleared[slot] = true
	else:
		round_failed[slot] = true
	if _all_alive_resolved():
		_end_round()


func _tick(delta: float) -> void:
	round_elapsed += delta
	match phase:
		Phase.SHOW:
			if round_elapsed >= _show_duration():
				phase = Phase.INPUT
				round_elapsed = 0.0
		Phase.INPUT:
			if round_elapsed >= INPUT_TIMEOUT_SEC:
				_end_round()
		Phase.RESULT:
			if round_elapsed >= RESULT_SEC:
				_advance_round()


func get_snapshot() -> Dictionary:
	return {
		"phase": phase,
		"round": round_index,
		"rounds_total": MAX_ROUNDS,
		"pad_count": PAD_COUNT,
		# Only revealed while flashing so a client can't read ahead during INPUT.
		"sequence": sequence.duplicate() if phase == Phase.SHOW else ([] as Array[int]),
		"length": sequence.size(),
		"alive": alive.duplicate(),
		"cleared_count": cleared_count.duplicate(),
		"progress": progress.duplicate(),
		"round_cleared": round_cleared.duplicate(),
		"round_failed": round_failed.duplicate(),
	}


func _rank_players() -> Array:
	var by_cleared := {}
	for slot: int in slots:
		var count: int = cleared_count.get(slot, 0)
		if not by_cleared.has(count):
			by_cleared[count] = []
		by_cleared[count].append(slot)
	var counts := by_cleared.keys()
	counts.sort()
	counts.reverse()
	var placements: Array = []
	for count: int in counts:
		placements.append(by_cleared[count])
	return placements


func _show_duration() -> float:
	return SHOW_LEAD_IN_SEC + sequence.size() * SHOW_PER_PAD_SEC


## True once every still-alive HUMAN player has either cleared or failed this
## round, so INPUT can end early instead of waiting out the timeout — a bot
## whose captured sequence desyncs and never presses a pad shouldn't hold up
## the round the other players already finished (#819).
func _all_alive_resolved() -> bool:
	for slot: int in _human_slots():
		if not alive.get(slot, false):
			continue
		if not (round_cleared.get(slot, false) or round_failed.get(slot, false)):
			return false
	return true


func _end_round() -> void:
	for slot: int in slots:
		if not alive.get(slot, false):
			continue
		if round_cleared.get(slot, false):
			cleared_count[slot] = int(cleared_count.get(slot, 0)) + 1
		else:
			# Ran out of time or stepped wrong: eliminated for the game.
			alive[slot] = false
	phase = Phase.RESULT
	round_elapsed = 0.0


func _advance_round() -> void:
	round_index += 1
	if _alive_count() <= 1 or round_index >= MAX_ROUNDS:
		finish(_rank_players())
	else:
		_start_round()


func _start_round() -> void:
	phase = Phase.SHOW
	round_elapsed = 0.0
	var length := START_LENGTH + round_index
	sequence = []
	for _i in length:
		sequence.append(rng.randi_range(0, PAD_COUNT - 1))
	progress.clear()
	round_cleared.clear()
	round_failed.clear()
	for slot: int in slots:
		if alive.get(slot, false):
			progress[slot] = 0


func _alive_count() -> int:
	var count := 0
	for slot: int in slots:
		if alive.get(slot, false):
			count += 1
	return count
