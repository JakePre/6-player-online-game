class_name TrapCorridor
extends MinigameBase
## Trap Corridor (M4-15, SPEC $7 #16): one trapper seeds a corridor with
## hidden traps, the rest run the gauntlet; roles rotate so everyone traps
## once. Trapper scores per catch, runners score by finish order. Server-side
## simulation only — the client renders get_snapshot(); hidden traps never
## leave the server (the trapper's client remembers its own placements).

enum Phase {
	TRAPPING,
	RUNNING,
}

const CORRIDOR_LEN := 20.0
const CORRIDOR_HALF_WIDTH := 3.0
## Trap grid resolution along the corridor and across it.
const COLS := 10
const ROWS := 5
const TILE_LEN := CORRIDOR_LEN / COLS
const TILE_WIDTH := CORRIDOR_HALF_WIDTH * 2.0 / ROWS

const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.4
const TRAP_PHASE_SEC := 6.0
const RUN_PHASE_SEC := 12.0
const TRAP_BUDGET := 6

const CATCH_POINTS := 3
const FINISH_POINTS: Array[int] = [3, 2, 1]

var phase := Phase.TRAPPING
var phase_left := TRAP_PHASE_SEC
## Index into slots: whose turn it is to trap this sub-round.
var trapper_index := 0
var positions := {}
var move_dirs := {}
var scores := {}
## Hidden trap tiles this sub-round, as col * ROWS + row indices.
var hidden_traps: Array = []
## Traps that went off (revealed to everyone), same indexing.
var revealed_traps: Array = []
## Runners caught or finished this sub-round.
var caught: Array = []
var finished_runners: Array = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"trap_corridor",
				"controls": "Move — WASD / left stick · Trapper: click a tile to arm it",
				"name": "Trap Corridor",
				"category": MinigameMeta.Category.SABOTAGE,
				"min_players": 3,
				"max_players": 6,
				"duration_sec": 150.0,
				"rules":
				"One of you traps the corridor — the rest run it. Roles rotate. Trust no floor tile!",
			}
		)
	)


func _setup() -> void:
	for slot: int in slots:
		scores[slot] = 0
	_start_sub_round()


func trapper() -> int:
	return slots[trapper_index]


func _handle_input(slot: int, data: Dictionary) -> void:
	if phase == Phase.TRAPPING and slot == trapper() and data.has("trap"):
		_place_trap(data.trap)
		return
	if phase == Phase.RUNNING and slot != trapper() and slot not in caught:
		var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
		move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	phase_left -= delta
	if phase == Phase.TRAPPING:
		if phase_left <= 0.0:
			_start_running()
		return
	_move_runners(delta)
	if phase_left <= 0.0 or _sub_round_settled():
		_end_sub_round()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		if slot == trapper() or slot in caught:
			continue
		var pos: Vector2 = positions.get(slot, Vector2.ZERO)
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
	return {
		"phase": phase,
		"phase_left": snappedf(maxf(phase_left, 0.0), 0.1),
		"trapper": trapper(),
		"players": players,
		"revealed": revealed_traps.duplicate(),
		"caught": caught.duplicate(),
		"scores": scores.duplicate(),
		"traps_left": TRAP_BUDGET - hidden_traps.size(),
		"corridor": [CORRIDOR_LEN, CORRIDOR_HALF_WIDTH],
	}


## Cumulative score, ties grouped.
func _rank_players() -> Array:
	var by_score := {}
	for slot: int in slots:
		var total: int = scores[slot]
		if not by_score.has(total):
			by_score[total] = []
		by_score[total].append(slot)
	var totals := by_score.keys()
	totals.sort()
	totals.reverse()
	var placements: Array = []
	for total: int in totals:
		placements.append(by_score[total])
	return placements


func tile_index(pos: Vector2) -> int:
	var col := clampi(int(pos.x / TILE_LEN), 0, COLS - 1)
	var row := clampi(int((pos.y + CORRIDOR_HALF_WIDTH) / TILE_WIDTH), 0, ROWS - 1)
	return col * ROWS + row


func _start_sub_round() -> void:
	phase = Phase.TRAPPING
	phase_left = TRAP_PHASE_SEC
	hidden_traps.clear()
	revealed_traps.clear()
	caught.clear()
	finished_runners.clear()
	move_dirs.clear()
	for i in slots.size():
		var slot: int = slots[i]
		# Runners wait at the start line, spread across the width.
		positions[slot] = Vector2(0.0, -CORRIDOR_HALF_WIDTH + (i + 0.5) * TILE_WIDTH)
		move_dirs[slot] = Vector2.ZERO


func _start_running() -> void:
	phase = Phase.RUNNING
	phase_left = RUN_PHASE_SEC


func _place_trap(target: Variant) -> void:
	if hidden_traps.size() >= TRAP_BUDGET:
		return
	if not (target is Array and target.size() == 2):
		return
	var col := clampi(int(target[0]), 1, COLS - 2)  # Start and finish stay safe.
	var row := clampi(int(target[1]), 0, ROWS - 1)
	var index := col * ROWS + row
	if index not in hidden_traps:
		hidden_traps.append(index)


func _move_runners(delta: float) -> void:
	for slot: int in slots:
		if slot == trapper() or slot in caught or slot in finished_runners:
			continue
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		pos.x = clampf(pos.x, 0.0, CORRIDOR_LEN)
		pos.y = clampf(pos.y, -CORRIDOR_HALF_WIDTH, CORRIDOR_HALF_WIDTH)
		positions[slot] = pos
		var tile := tile_index(pos)
		if tile in hidden_traps:
			hidden_traps.erase(tile)
			revealed_traps.append(tile)
			caught.append(slot)
			scores[trapper()] = int(scores[trapper()]) + CATCH_POINTS
			continue
		if pos.x >= CORRIDOR_LEN:
			finished_runners.append(slot)
			var place := finished_runners.size() - 1
			scores[slot] = (
				int(scores[slot]) + FINISH_POINTS[mini(place, FINISH_POINTS.size() - 1)]
			)


func _sub_round_settled() -> bool:
	return caught.size() + finished_runners.size() >= slots.size() - 1


func _end_sub_round() -> void:
	trapper_index += 1
	if trapper_index >= slots.size():
		finish(_rank_players())
		return
	_start_sub_round()
