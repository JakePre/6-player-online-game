class_name MinigameBase
extends RefCounted
## Server-side base class of the Minigame Contract (plan $4). Minigames are
## pure simulations: the framework calls setup/tick/handle_input, reads
## get_snapshot() for replication, and consumes results when `finished`.
## Minigames never touch RPCs (ADR 001).
##
## Results shape: placements is an array of rank groups (arrays of slots,
## best first, ties grouped); pickup_coins is {slot: int}.

var meta: MinigameMeta
var slots: Array[int] = []
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var finished := false
## Test-harness hook: when > 0, replaces meta.duration_sec for this instance.
var duration_override := 0.0

var _placements: Array = []
var _pickup_coins := {}


func setup(player_slots: Array[int], seed_value: int) -> void:
	slots = player_slots.duplicate()
	rng.seed = seed_value
	_setup()


func tick(delta: float) -> void:
	if finished:
		return
	elapsed += delta
	_tick(delta)
	if elapsed >= effective_duration() and not finished:
		finish(_rank_players())


func effective_duration() -> float:
	return duration_override if duration_override > 0.0 else meta.duration_sec


## `data` comes straight off the wire — validate everything.
func handle_input(slot: int, data: Dictionary) -> void:
	if not finished and slot in slots:
		_handle_input(slot, data)


func get_results() -> Dictionary:
	return {"placements": _placements, "pickup_coins": _pickup_coins}


func get_snapshot() -> Dictionary:
	return {}


func finish(placements: Array) -> void:
	_placements = placements
	finished = true


# --- Overridables ------------------------------------------------------------


func _setup() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


func _handle_input(_slot: int, _data: Dictionary) -> void:
	pass


## Ranking used when time runs out. Default: everyone tied.
func _rank_players() -> Array:
	return [slots.duplicate()]
