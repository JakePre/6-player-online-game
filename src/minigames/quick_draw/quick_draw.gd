class_name QuickDraw
extends MinigameBase
## Quick Draw (M4-06, SPEC $7 #7): best of 5 reaction-time duels. Each round
## waits a random delay then goes live; the first correct press after the
## signal wins the round. Pressing early is a false start that forfeits the
## round for that player only (per-round elimination, not match elimination).
## Server-side simulation only — the client renders get_snapshot().

enum Phase {
	WAITING,
	LIVE,
	ROUND_OVER,
}

const ROUNDS_TO_PLAY := 5
const WAIT_MIN_SEC := 1.0
const WAIT_MAX_SEC := 3.0
const LIVE_TIMEOUT_SEC := 2.5
const ROUND_GAP_SEC := 1.2

var wins := {}
var phase: Phase = Phase.WAITING
var round_index := 0
var round_elapsed := 0.0
var wait_time := 0.0
var winner_slot := -1

var false_started := {}
var _acted := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"quick_draw",
				"controls": "Press SPACE / pad A the instant it flashes DRAW!",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				["Press ", {"action": &"action_primary"}, " the instant it flashes DRAW!"],
				# Structured spec (#832/#844): a single action row with its note.
				"control_spec":
				[{"verb": "Draw", "input": &"action_primary", "note": "the instant it flashes!"}],
				"name": "Quick Draw",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 60.0,
				"rules":
				"Wait for it... then hit the button first! Jump the gun and you forfeit the round. Best of 5.",
			}
		)
	)


func _setup() -> void:
	for slot: int in slots:
		wins[slot] = 0
	_start_round()


func _handle_input(slot: int, data: Dictionary) -> void:
	if not data.get("press", false) or _acted.get(slot, false):
		return
	_acted[slot] = true
	match phase:
		Phase.WAITING:
			false_started[slot] = true
		Phase.LIVE:
			if winner_slot == -1:
				winner_slot = slot
				_end_round(slot)


func _tick(delta: float) -> void:
	round_elapsed += delta
	match phase:
		Phase.WAITING:
			if round_elapsed >= wait_time:
				phase = Phase.LIVE
				round_elapsed = 0.0
		Phase.LIVE:
			if round_elapsed >= LIVE_TIMEOUT_SEC:
				_end_round(-1)
		Phase.ROUND_OVER:
			if round_elapsed >= ROUND_GAP_SEC:
				_advance_round()


func get_snapshot() -> Dictionary:
	return {
		"phase": phase,
		"round": round_index,
		"rounds_total": ROUNDS_TO_PLAY,
		"wins": wins.duplicate(),
		"false_started": false_started.duplicate(),
		"winner": winner_slot,
	}


func _rank_players() -> Array:
	var by_wins := {}
	for slot: int in slots:
		var count: int = wins.get(slot, 0)
		if not by_wins.has(count):
			by_wins[count] = []
		by_wins[count].append(slot)
	var counts := by_wins.keys()
	counts.sort()
	counts.reverse()
	var placements: Array = []
	for count: int in counts:
		placements.append(by_wins[count])
	return placements


func _end_round(winner: int) -> void:
	if winner != -1:
		wins[winner] = int(wins.get(winner, 0)) + 1
	winner_slot = winner
	phase = Phase.ROUND_OVER
	round_elapsed = 0.0


func _advance_round() -> void:
	round_index += 1
	if round_index >= ROUNDS_TO_PLAY:
		finish(_rank_players())
	else:
		_start_round()


func _start_round() -> void:
	phase = Phase.WAITING
	round_elapsed = 0.0
	wait_time = rng.randf_range(WAIT_MIN_SEC, WAIT_MAX_SEC)
	winner_slot = -1
	_acted.clear()
	false_started.clear()
