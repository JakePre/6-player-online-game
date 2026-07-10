class_name TheMole
extends MinigameBase
## The Mole (M10-13, PHASE2.md $4 #30): a co-op fuel run with a traitor.
## The crew hauls fuel cells to the central machine; one seeded player is
## secretly the mole (told via the #254 private-snapshot hook — the shared
## snapshot stays anonymous until the reveal) whose action near the machine
## drains progress on a cooldown. The machine sparks, but the tell has no
## name on it: everyone nearby is a suspect. After the objective resolves,
## the crew votes; points flow from the outcome, the vote, and whether the
## mole escaped it. Server-side simulation only.

enum Phase {
	WORK,
	VOTE,
	REVEAL,
}

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const MACHINE_POS := Vector2.ZERO
const MACHINE_RADIUS := 1.6
const CELL_PICKUP_RADIUS := 0.8
const CELL_TARGET := 10
const MAX_LOOSE_CELLS := 5
const CELL_WAVE_SEC := 2.0
const SABOTAGE_COOLDOWN_SEC := 6.0
## The unattributed tell: the machine sparks for this long after sabotage.
const SPARK_SEC := 1.2
const WORK_SEC := 60.0
const VOTE_SEC := 12.0
const REVEAL_SEC := 4.0
## Scoring: crew scores on success, the mole on failure, correct voters get
## a bonus, and an uncaught mole (under a strict crew majority) gets one.
const CREW_SUCCESS_POINTS := 3
const MOLE_FAIL_POINTS := 5
const CORRECT_VOTE_POINTS := 2
const MOLE_UNCAUGHT_POINTS := 3

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_CARRYING := 2
const PS_COUNT := 3

const CL_X := 0
const CL_Y := 1
const CL_COUNT := 2

var phase := Phase.WORK
var phase_elapsed := 0.0
var mole := -1
var progress := 0
var success := false
var positions := {}
var move_dirs := {}
var carrying := {}
var cells: Array[Vector2] = []
## slot -> voted slot, recorded only during VOTE; self-votes are ignored.
var votes := {}
var caught := false

var _sabotage_cooldown := 0.0
var _spark_left := 0.0
var _wave_accum := 0.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"the_mole",
				"name": "The Mole",
				"category": MinigameMeta.Category.SABOTAGE,
				"min_players": 4,
				"max_players": 8,
				"duration_sec": 80.0,
				"rules":
				(
					"Fuel the machine together — but one of you is the MOLE,"
					+ " secretly draining it. Finish the job, then VOTE the"
					+ " traitor out!"
				),
				"controls":
				"Move — WASD / left stick · Sabotage (mole) / cycle vote — SPACE / pad A",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				[
					"Move — WASD / left stick · Sabotage (mole) / cycle vote — ",
					{"action": &"action_primary"},
				],
				# Structured spec (#832/#844): move + role-qualified action, keeping
				# the vote-cycle verb (#801: still the one-button cycle mechanic).
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Sabotage (mole) / cycle vote", "input": &"action_primary"},
				],
			}
		)
	)


func _setup() -> void:
	mole = slots[rng.randi_range(0, slots.size() - 1)]
	for i in slots.size():
		var angle := TAU * i / slots.size()
		var slot: int = slots[i]
		positions[slot] = Vector2(cos(angle), sin(angle)) * ARENA_HALF * 0.6
		move_dirs[slot] = Vector2.ZERO
		carrying[slot] = false
	for _i in MAX_LOOSE_CELLS:
		_spawn_cell()


## The one place the role exists outside the server until the reveal (#254).
func get_private_snapshot(slot: int) -> Dictionary:
	if slot == mole and phase != Phase.REVEAL:
		return {"role": "mole"}
	return {}


func _handle_input(slot: int, data: Dictionary) -> void:
	if phase == Phase.VOTE:
		if data.has("vote"):
			var target := int(data.vote)
			if target in slots and target != slot:
				votes[slot] = target
		return
	if phase != Phase.WORK:
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if data.get("act", false) and slot == mole:
		_try_sabotage()


func _try_sabotage() -> void:
	if _sabotage_cooldown > 0.0 or progress <= 0:
		return
	if positions[mole].distance_to(MACHINE_POS) > MACHINE_RADIUS:
		return
	_sabotage_cooldown = SABOTAGE_COOLDOWN_SEC
	_spark_left = SPARK_SEC
	progress -= 1


func _tick(delta: float) -> void:
	phase_elapsed += delta
	match phase:
		Phase.WORK:
			_tick_work(delta)
		Phase.VOTE:
			if phase_elapsed >= VOTE_SEC or _all_humans_voted():
				_tally_and_reveal()
		Phase.REVEAL:
			if phase_elapsed >= REVEAL_SEC:
				finish(_rank_players())


func _tick_work(delta: float) -> void:
	_sabotage_cooldown = maxf(_sabotage_cooldown - delta, 0.0)
	_spark_left = maxf(_spark_left - delta, 0.0)
	for slot: int in slots:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	_pickups()
	_deliveries()
	_wave_accum += delta
	if _wave_accum >= CELL_WAVE_SEC:
		_wave_accum -= CELL_WAVE_SEC
		_spawn_cell()
	if progress >= CELL_TARGET:
		success = true
		_start_vote()
	elif phase_elapsed >= WORK_SEC:
		success = false
		_start_vote()


func _start_vote() -> void:
	phase = Phase.VOTE
	phase_elapsed = 0.0
	votes.clear()
	for slot: int in slots:
		move_dirs[slot] = Vector2.ZERO


## #819: only the humans need to vote — a bot's vote counts toward the tally
## if cast, but the room shouldn't sit out the full VOTE_SEC waiting on one
## that never does.
func _all_humans_voted() -> bool:
	for slot: int in _human_slots():
		if not votes.has(slot):
			return false
	return true


func _tally_and_reveal() -> void:
	var against_mole := 0
	var crew_count := 0
	for slot: int in slots:
		if slot == mole:
			continue
		crew_count += 1
		if int(votes.get(slot, -1)) == mole:
			against_mole += 1
	caught = against_mole * 2 > crew_count
	phase = Phase.REVEAL
	phase_elapsed = 0.0


func _pickups() -> void:
	for i in range(cells.size() - 1, -1, -1):
		for slot: int in slots:
			if carrying[slot]:
				continue
			if positions[slot].distance_to(cells[i]) <= CELL_PICKUP_RADIUS:
				carrying[slot] = true
				cells.remove_at(i)
				break


func _deliveries() -> void:
	for slot: int in slots:
		if not carrying[slot]:
			continue
		if positions[slot].distance_to(MACHINE_POS) <= MACHINE_RADIUS:
			carrying[slot] = false
			progress += 1


func _spawn_cell() -> void:
	if cells.size() >= MAX_LOOSE_CELLS:
		return
	# Cells land in a ring away from the machine so hauls take real time.
	var angle := rng.randf_range(0.0, TAU)
	var radius := rng.randf_range(ARENA_HALF * 0.45, ARENA_HALF * 0.9)
	cells.append(Vector2(cos(angle), sin(angle)) * radius)


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), 1 if carrying[slot] else 0]
	var cell_list: Array = []
	for cell in cells:
		cell_list.append([snappedf(cell.x, 0.01), snappedf(cell.y, 0.01)])
	var limit := WORK_SEC
	if phase == Phase.VOTE:
		limit = VOTE_SEC
	elif phase == Phase.REVEAL:
		limit = REVEAL_SEC
	var snapshot := {
		"phase": phase,
		"phase_left": snappedf(maxf(limit - phase_elapsed, 0.0), 0.1),
		"progress": progress,
		"target": CELL_TARGET,
		"sparked": _spark_left > 0.0,
		"players": players,
		"cells": cell_list,
		"votes_in": votes.size(),
	}
	if phase == Phase.VOTE:
		# WHO has voted (participation only — never who they voted for, which
		# would bandwagon). The accusation graph waits for `reveal.votes` (#801).
		snapshot["voted"] = votes.keys()
	if phase == Phase.REVEAL:
		# The outcome is locked — the identity may go public now, not before.
		snapshot["reveal"] = {
			"mole": mole, "caught": caught, "success": success, "votes": votes.duplicate()
		}
	return snapshot


func _points(slot: int) -> int:
	var total := 0
	if slot == mole:
		if not success:
			total += MOLE_FAIL_POINTS
		if not caught:
			total += MOLE_UNCAUGHT_POINTS
		return total
	if success:
		total += CREW_SUCCESS_POINTS
	if int(votes.get(slot, -1)) == mole:
		total += CORRECT_VOTE_POINTS
	return total


## Points decide placement, ties grouped (SPEC $5 FFA tables).
func _rank_players() -> Array:
	var by_points := {}
	for slot: int in slots:
		var total := _points(slot)
		if not by_points.has(total):
			by_points[total] = []
		by_points[total].append(slot)
	var totals := by_points.keys()
	totals.sort()
	totals.reverse()
	var placements: Array = []
	for total: int in totals:
		placements.append(by_points[total])
	return placements
