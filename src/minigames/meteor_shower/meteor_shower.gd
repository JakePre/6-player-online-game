class_name MeteorShower
extends MinigameBase
## Meteor Shower (M10-01, PHASE2.md $4 #18): telegraphed meteors rain down on
## a shrinking safe zone; stepping outside the zone or standing under an
## impact knocks you out. Last one standing wins; down order = placement.
## Server-side simulation only — the client renders get_snapshot().

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const ZONE_START_RADIUS := 8.5
const ZONE_MIN_RADIUS := 2.5
## Grace period before the zone starts shrinking, then the shrink itself.
const ZONE_GRACE_SEC := 5.0
const ZONE_SHRINK_SEC := 40.0
const METEOR_TELEGRAPH_SEC := 1.2
const METEOR_RADIUS := 1.6
## Spawn cadence accelerates from START to MIN across the round.
const METEOR_INTERVAL_START := 1.4
const METEOR_INTERVAL_MIN := 0.5

var positions := {}
var move_dirs := {}
## Telegraphed meteors: {pos: Vector2, left: float} — impact when left hits 0.
var meteors: Array = []
## Slots in down order; same-tick knockouts share a tie group.
var down_order: Array = []

var _pending_downs: Array = []
var _spawn_left := METEOR_INTERVAL_START


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"meteor_shower",
				"controls": "Move — WASD / left stick",
				"name": "Meteor Shower",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 6,
				"duration_sec": 60.0,
				"rules":
				"Meteors mark where they'll land — don't be there. Stay inside the shrinking safe zone!",
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * ZONE_START_RADIUS * 0.6
		move_dirs[slots[i]] = Vector2.ZERO


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _is_in(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	if finished:
		return
	for slot: int in _in_slots():
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.limit_length(ARENA_HALF)
	_tick_meteors(delta)
	_spawn_meteors(delta)
	_check_zone()
	_flush_downs()
	_check_end()


func zone_radius() -> float:
	var t := clampf((elapsed - ZONE_GRACE_SEC) / ZONE_SHRINK_SEC, 0.0, 1.0)
	return lerpf(ZONE_START_RADIUS, ZONE_MIN_RADIUS, t)


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in _in_slots():
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
	var meteor_list: Array = []
	for meteor: Dictionary in meteors:
		var pos: Vector2 = meteor.pos
		meteor_list.append(
			[snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(meteor.left, 0.01)]
		)
	return {
		"players": players,
		"zone": [0.0, 0.0, snappedf(zone_radius(), 0.01)],
		"meteors": meteor_list,
		"fallen": down_order,
	}


## Timeout: everyone still standing ties ahead of the fallen.
func _rank_players() -> Array:
	var survivors := _in_slots()
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	return placements + _out_placements()


func _tick_meteors(delta: float) -> void:
	var remaining: Array = []
	for meteor: Dictionary in meteors:
		meteor.left -= delta
		if meteor.left > 0.0:
			remaining.append(meteor)
			continue
		for slot: int in _in_slots():
			if positions[slot].distance_to(meteor.pos) <= METEOR_RADIUS + PLAYER_RADIUS:
				_pending_downs.append(slot)
	meteors = remaining


func _spawn_meteors(delta: float) -> void:
	_spawn_left -= delta
	if _spawn_left > 0.0:
		return
	var t := clampf(elapsed / effective_duration(), 0.0, 1.0)
	_spawn_left = lerpf(METEOR_INTERVAL_START, METEOR_INTERVAL_MIN, t)
	var angle := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(0.0, maxf(zone_radius() - METEOR_RADIUS * 0.5, 0.0))
	meteors.append({"pos": Vector2(cos(angle), sin(angle)) * dist, "left": METEOR_TELEGRAPH_SEC})


func _check_zone() -> void:
	var radius := zone_radius()
	for slot: int in _in_slots():
		if positions[slot].length() > radius + PLAYER_RADIUS:
			_pending_downs.append(slot)


func _flush_downs() -> void:
	if _pending_downs.is_empty():
		return
	var group: Array = []
	for slot: int in _pending_downs:
		if slot not in group:
			group.append(slot)
	down_order.append(group)
	_pending_downs.clear()


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
	for group: Array in down_order:
		if slot in group:
			return false
	return slot not in _pending_downs


func _in_slots() -> Array:
	return slots.filter(_is_in)


func _out_placements() -> Array:
	var placements := down_order.duplicate(true)
	placements.reverse()
	return placements
