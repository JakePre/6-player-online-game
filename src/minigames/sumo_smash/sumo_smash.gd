class_name SumoSmash
extends MinigameBase
## Sumo Smash (M4-04, SPEC $7 #5): shove players off a circular platform;
## dash has a cooldown. Ring-out order = placement. Server-side simulation
## only — the client renders get_snapshot().

const PLATFORM_RADIUS := 8.0
const MOVE_SPEED := 5.0
const PLAYER_RADIUS := 0.5
const SHOVE_SPEED := 4.0
const DASH_SPEED := 14.0
const DASH_SEC := 0.25
const DASH_COOLDOWN_SEC := 2.0
const DASH_SHOVE_MULT := 3.0
const KNOCK_DECAY := 6.0

var positions := {}
var move_dirs := {}
## Knockback/dash velocity per slot, decaying toward zero.
var knocks := {}
var dash_left := {}
var cooldown_left := {}
## Slots in ring-out order; same-tick ring-outs share a tie group.
var ringout_order: Array = []

var _pending_outs: Array = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"sumo_smash",
				"controls": "Move — WASD / left stick · Dash — SPACE / pad A",
				"name": "Sumo Smash",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				# 8 by design (ADR 003): the platform stays this one tiny disc on
				# purpose — bigger would turn the shove-brawl into random pinball.
				"max_players": 8,
				"duration_sec": 60.0,
				"rules": "Shove everyone off the platform! Dash to hit harder — it has a cooldown.",
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * PLATFORM_RADIUS * 0.6
		move_dirs[slots[i]] = Vector2.ZERO
		knocks[slots[i]] = Vector2.ZERO
		dash_left[slots[i]] = 0.0
		cooldown_left[slots[i]] = 0.0


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _is_in(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if data.get("dash", false) and float(cooldown_left[slot]) <= 0.0:
		var heading: Vector2 = move_dirs[slot]
		if heading.length() < 0.01:
			return
		cooldown_left[slot] = DASH_COOLDOWN_SEC
		dash_left[slot] = DASH_SEC
		knocks[slot] = heading.normalized() * DASH_SPEED


func _tick(delta: float) -> void:
	# Alive-set cache (cleanup #467): computed once, shared by every helper
	# below that runs before this tick's own ring-outs are finalized.
	# _check_end() still calls _in_slots() fresh — it must see the roster
	# *after* _flush_ringouts() applies this tick's eliminations.
	var alive := _in_slots()
	for slot: int in alive:
		cooldown_left[slot] = maxf(float(cooldown_left[slot]) - delta, 0.0)
		dash_left[slot] = maxf(float(dash_left[slot]) - delta, 0.0)
		var knock: Vector2 = knocks[slot]
		positions[slot] += (move_dirs[slot] * MOVE_SPEED + knock) * delta
		knocks[slot] = knock.move_toward(Vector2.ZERO, KNOCK_DECAY * delta)
	_resolve_shoves(alive)
	_check_ringouts(alive)
	_flush_ringouts()
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		if not _is_in(slot):
			continue
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			snappedf(cooldown_left[slot], 0.01),
			1 if dash_left[slot] > 0.0 else 0,
		]
	return {"radius": PLATFORM_RADIUS, "players": players, "out": ringout_order}


## Timeout: everyone still on the platform ties ahead of the rung-out.
func _rank_players() -> Array:
	var survivors := _in_slots()
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	return placements + _out_placements()


func _resolve_shoves(active: Array) -> void:
	for i in active.size():
		for j in range(i + 1, active.size()):
			var a: int = active[i]
			var b: int = active[j]
			var apart: Vector2 = positions[b] - positions[a]
			if apart.length() > PLAYER_RADIUS * 2.0:
				continue
			var axis := apart.normalized() if apart.length() > 0.001 else Vector2.RIGHT
			knocks[a] -= axis * _shove_strength(b)
			knocks[b] += axis * _shove_strength(a)


func _shove_strength(shover: int) -> float:
	return SHOVE_SPEED * (DASH_SHOVE_MULT if float(dash_left[shover]) > 0.0 else 1.0)


func _check_ringouts(alive: Array) -> void:
	for slot: int in alive:
		if positions[slot].length() > PLATFORM_RADIUS:
			_pending_outs.append(slot)


func _flush_ringouts() -> void:
	if not _pending_outs.is_empty():
		ringout_order.append(_pending_outs.duplicate())
		_pending_outs.clear()


func _check_end() -> void:
	if finished:
		return
	var survivors := _in_slots()
	if survivors.size() > 1:
		return
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	finish(placements + _out_placements())


func _is_in(slot: int) -> bool:
	if slot not in slots:
		return false
	for group: Array in ringout_order:
		if slot in group:
			return false
	return slot not in _pending_outs


func _in_slots() -> Array:
	return slots.filter(_is_in)


func _out_placements() -> Array:
	var placements := ringout_order.duplicate(true)
	placements.reverse()
	return placements
