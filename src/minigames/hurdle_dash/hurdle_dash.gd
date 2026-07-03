class_name HurdleDash
extends MinigameBase
## Hurdle Dash (M4-07, SPEC $7 #8): obstacle race to the finish line — time
## your jumps over the hurdles. Finish order = placement. Server-side
## simulation only — the client renders get_snapshot().

const COURSE_LEN := 40.0
const RUN_SPEED := 7.0
const JUMP_AIRTIME_SEC := 0.45
const JUMP_COOLDOWN_SEC := 0.1
const HURDLE_COUNT := 8
## Hurdles land in this window, jittered per round from the seed.
const FIRST_HURDLE := 5.0
const LAST_HURDLE := 36.0
const HURDLE_JITTER := 1.2
const HURDLE_HALF_DEPTH := 0.3
const STUN_SEC := 0.8
const KNOCKBACK := 1.5

## Same hurdle x positions for every lane (fair course).
var hurdles: Array[float] = []
var progress := {}
var running := {}
var air_left := {}
var jump_cooldown := {}
var stun_left := {}
## Slots in finish order; same-tick finishes share a tie group.
var finish_order: Array = []

var _pending_finishes: Array = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"hurdle_dash",
				"name": "Hurdle Dash",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 6,
				"duration_sec": 45.0,
				"rules": "Race to the finish — jump the hurdles or eat dirt. First one home wins!",
			}
		)
	)


func _setup() -> void:
	var span := (LAST_HURDLE - FIRST_HURDLE) / (HURDLE_COUNT - 1)
	for i in HURDLE_COUNT:
		var jitter := rng.randf_range(-HURDLE_JITTER, HURDLE_JITTER)
		hurdles.append(clampf(FIRST_HURDLE + i * span + jitter, FIRST_HURDLE, LAST_HURDLE))
	for slot: int in slots:
		progress[slot] = 0.0
		running[slot] = false
		air_left[slot] = 0.0
		jump_cooldown[slot] = 0.0
		stun_left[slot] = 0.0


func _handle_input(slot: int, data: Dictionary) -> void:
	if _is_done(slot):
		return
	if data.has("jump"):
		if (
			float(stun_left[slot]) <= 0.0
			and float(air_left[slot]) <= 0.0
			and float(jump_cooldown[slot]) <= 0.0
		):
			air_left[slot] = JUMP_AIRTIME_SEC
		return
	running[slot] = float(data.get("mx", 0.0)) > 0.1


func _tick(delta: float) -> void:
	for slot: int in slots:
		if _is_done(slot):
			continue
		_tick_runner(slot, delta)
	if not _pending_finishes.is_empty():
		finish_order.append(_pending_finishes.duplicate())
		_pending_finishes.clear()
	if _all_done():
		finish(_rank_players())


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		players[slot] = [
			snappedf(progress[slot], 0.01),
			1 if float(air_left[slot]) > 0.0 else 0,
			snappedf(stun_left[slot], 0.01),
			_is_done(slot),
		]
	var hurdle_list: Array = []
	for hurdle in hurdles:
		hurdle_list.append(snappedf(hurdle, 0.01))
	return {"players": players, "hurdles": hurdle_list, "course_len": COURSE_LEN}


## Finished runners first (in order, tick ties grouped), then the rest by
## distance covered.
func _rank_players() -> Array:
	var placements := finish_order.duplicate(true)
	var by_distance := {}
	for slot: int in slots:
		if _is_done(slot):
			continue
		var key := snappedf(progress[slot], 0.01)
		if not by_distance.has(key):
			by_distance[key] = []
		by_distance[key].append(slot)
	var distances := by_distance.keys()
	distances.sort()
	distances.reverse()
	for distance: float in distances:
		placements.append(by_distance[distance])
	return placements


func _tick_runner(slot: int, delta: float) -> void:
	jump_cooldown[slot] = maxf(float(jump_cooldown[slot]) - delta, 0.0)
	if float(stun_left[slot]) > 0.0:
		stun_left[slot] = maxf(float(stun_left[slot]) - delta, 0.0)
		return
	var airborne: bool = float(air_left[slot]) > 0.0
	if airborne:
		air_left[slot] = maxf(float(air_left[slot]) - delta, 0.0)
		if float(air_left[slot]) == 0.0:
			jump_cooldown[slot] = JUMP_COOLDOWN_SEC
	if not running[slot]:
		return
	var before: float = progress[slot]
	var after := before + RUN_SPEED * delta
	if not airborne:
		for hurdle: float in hurdles:
			if before < hurdle - HURDLE_HALF_DEPTH and after >= hurdle - HURDLE_HALF_DEPTH:
				stun_left[slot] = STUN_SEC
				progress[slot] = maxf(hurdle - HURDLE_HALF_DEPTH - KNOCKBACK, 0.0)
				return
	progress[slot] = after
	if after >= COURSE_LEN:
		_pending_finishes.append(slot)


func _is_done(slot: int) -> bool:
	if slot in _pending_finishes:
		return true
	for group: Array in finish_order:
		if slot in group:
			return true
	return false


func _all_done() -> bool:
	for slot: int in slots:
		if not _is_done(slot):
			return false
	return true
