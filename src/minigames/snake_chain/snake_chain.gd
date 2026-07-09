class_name SnakeChain
extends MinigameBase
## Snake Chain (M10-11, PHASE2.md $4 #28): every player steers a growing
## conga chain — eat pellets to grow, and never drive your head into a body,
## anyone's, including your own. Crashing scatters half your pellets back
## onto the floor and respawns you small. Teams at even counts >= 4 sum
## their pellets (friendly bodies still block — discipline matters); FFA
## otherwise (#178). Server-side simulation only.
##
## Scales to 12 (ADR 003): the arena grows with the sqrt of the head count so
## dense chains keep room to weave instead of gridlocking, and the pellet
## supply grows linearly so a bigger lobby doesn't starve. Snake bodies keep
## their physical size; at <=6 players everything equals the base consts.

## Base 6-player arena/supply; arena_half_for()/max_pellets_for() scale them.
const ARENA_HALF := 9.0
const MOVE_SPEED := 5.5
const HEAD_RADIUS := 0.4
const SEGMENT_RADIUS := 0.35
## Trail sampling: one body point every this many seconds of travel.
const SAMPLE_SEC := 0.15
const BASE_SEGMENTS := 3
## Head ignores its own newest segments so tight turns aren't suicide.
const SELF_GRACE_SEGMENTS := 4
const PELLET_RADIUS := 0.6
const PELLET_WAVE_SEC := 1.2
const MAX_ACTIVE_PELLETS := 10
## Crash spill can push the floor this far over the steady-state cap.
const SPILL_HEADROOM := 6
const CRASH_INVULN_SEC := 2.0
const TEAM_THRESHOLD := 4
## No 180s (#796): a direction this close to dead opposite of the current
## heading is ignored instead of snapping the head straight back into its own
## neck. An about-face still works, it just has to be eased through a real
## turn (two 90-ish taps) like any other sharp turn, instead of a free
## instant reversal.
const REVERSAL_DOT_MAX := -0.9

## get_snapshot() wire shape (#708): named indices for the players positional
## array. Array SHAPE on the wire is unchanged — additive only.
const PS_X := 0
const PS_Y := 1
const PS_COUNT_EATEN := 2
const PS_INVULN := 3
const PS_COUNT := 4

const TR_X := 0
const TR_Y := 1

var positions := {}
var headings := {}
## slot -> Array of Vector2 body points, newest first.
var trails := {}
var pellets_eaten := {}
var invuln_left := {}
var pellets: Array[Vector2] = []
## Two teams of slots at even counts >= 4; empty in FFA.
var teams: Array = []
## Per-instance arena/supply (base at <=6 players, scaled up to 12).
var arena_half := ARENA_HALF
var max_pellets := MAX_ACTIVE_PELLETS

var _sample_accum := {}
var _pellet_accum := 0.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"snake_chain",
				"controls": "Steer — WASD / left stick",
				"name": "Snake Chain",
				"category": MinigameMeta.Category.TEAM,
				"min_players": 2,
				"max_players": 12,
				"duration_sec": 60.0,
				"rules": "Eat to grow the conga — crash into ANY body and you spill your pellets!",
			}
		)
	)


## Arena half-extent for `count` players: grows with the sqrt of the head count
## (MinigameScaling) so per-player floor area stays constant and dense chains
## keep room to weave. Never below the tuned 6-player base.
static func arena_half_for(count: int) -> float:
	return MinigameScaling.arena_half(ARENA_HALF, count)


## Steady-state pellet count for `count` players: grows linearly so food
## per-capita stays constant and a bigger lobby doesn't starve.
static func max_pellets_for(count: int) -> int:
	return MinigameScaling.supply(MAX_ACTIVE_PELLETS, count)


func _setup() -> void:
	arena_half = arena_half_for(slots.size())
	max_pellets = max_pellets_for(slots.size())
	team_mode = slots.size() >= TEAM_THRESHOLD and slots.size() % 2 == 0
	if team_mode:
		var shuffled := slots.duplicate()
		for i in range(shuffled.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap: int = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = swap
		teams = [shuffled.slice(0, shuffled.size() / 2), shuffled.slice(shuffled.size() / 2)]
	for i in slots.size():
		var slot: int = slots[i]
		var angle := TAU * i / slots.size()
		positions[slot] = Vector2(cos(angle), sin(angle)) * arena_half * 0.6
		headings[slot] = Vector2(-cos(angle), -sin(angle))
		trails[slot] = []
		pellets_eaten[slot] = 0
		invuln_left[slot] = 0.0
		_sample_accum[slot] = 0.0
	_spawn_pellets()


## Steering only — the chain never stops moving; input turns the head.
func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	if dir.length() <= 0.2:
		return
	var new_heading := dir.normalized()
	if new_heading.dot(headings[slot]) <= REVERSAL_DOT_MAX:
		return
	headings[slot] = new_heading


func _tick(delta: float) -> void:
	for slot: int in slots:
		invuln_left[slot] = maxf(float(invuln_left[slot]) - delta, 0.0)
		var pos: Vector2 = positions[slot] + (headings[slot] as Vector2) * MOVE_SPEED * delta
		# Walls turn you, they don't kill you: clamp and slide.
		positions[slot] = pos.clamp(
			Vector2(-arena_half, -arena_half), Vector2(arena_half, arena_half)
		)
		_sample_accum[slot] = float(_sample_accum[slot]) + delta
		if float(_sample_accum[slot]) >= SAMPLE_SEC:
			_sample_accum[slot] = 0.0
			var trail: Array = trails[slot]
			trail.push_front(positions[slot])
			while trail.size() > _max_segments(slot):
				trail.pop_back()
	_eat_pellets()
	_check_crashes()
	_pellet_accum += delta
	if _pellet_accum >= PELLET_WAVE_SEC:
		_pellet_accum = 0.0
		_spawn_pellets()


func get_snapshot() -> Dictionary:
	var players := {}
	var trail_lists := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			int(pellets_eaten[slot]),
			snappedf(invuln_left[slot], 0.01),
		]
		var points: Array = []
		for point: Vector2 in trails[slot]:
			points.append([snappedf(point.x, 0.01), snappedf(point.y, 0.01)])
		trail_lists[slot] = points
	var pellet_list: Array = []
	for pellet in pellets:
		pellet_list.append([snappedf(pellet.x, 0.01), snappedf(pellet.y, 0.01)])
	return {
		"players": players,
		"trails": trail_lists,
		"pellets": pellet_list,
		"teams": teams.duplicate(true),
	}


## FFA: per-player pellets (ties grouped). Teams: summed pellets, best team
## first, dead heat = full tie. Pellets double as capped pickup coins.
func _rank_players() -> Array:
	_pickup_coins = pellets_eaten.duplicate()
	if team_mode:
		var a := 0
		var b := 0
		for slot: int in teams[0]:
			a += int(pellets_eaten[slot])
		for slot: int in teams[1]:
			b += int(pellets_eaten[slot])
		if a == b:
			return [slots.duplicate()]
		var order := [teams[0], teams[1]] if a > b else [teams[1], teams[0]]
		return [order[0].duplicate(), order[1].duplicate()]
	var by_count := {}
	for slot: int in slots:
		var count: int = pellets_eaten[slot]
		if not by_count.has(count):
			by_count[count] = []
		by_count[count].append(slot)
	var counts := by_count.keys()
	counts.sort()
	counts.reverse()
	var placements: Array = []
	for count: int in counts:
		placements.append(by_count[count])
	return placements


func _max_segments(slot: int) -> int:
	return BASE_SEGMENTS + int(pellets_eaten[slot])


func _eat_pellets() -> void:
	for i in range(pellets.size() - 1, -1, -1):
		for slot: int in slots:
			if positions[slot].distance_to(pellets[i]) <= PELLET_RADIUS:
				pellets_eaten[slot] = int(pellets_eaten[slot]) + 1
				pellets.remove_at(i)
				break


func _check_crashes() -> void:
	for slot: int in slots:
		if float(invuln_left[slot]) > 0.0:
			continue
		if _head_hits_a_body(slot):
			_crash(slot)


func _head_hits_a_body(slot: int) -> bool:
	var head: Vector2 = positions[slot]
	for other: int in slots:
		var trail: Array = trails[other]
		var start := SELF_GRACE_SEGMENTS if other == slot else 0
		for i in range(start, trail.size()):
			if head.distance_to(trail[i]) <= HEAD_RADIUS + SEGMENT_RADIUS:
				return true
	return false


## Half the pellets spill back onto the floor near the wreck; the chain
## shrinks to match and the player restarts from the nearest edge.
func _crash(slot: int) -> void:
	var spilled := int(pellets_eaten[slot]) / 2
	pellets_eaten[slot] = int(pellets_eaten[slot]) - spilled
	for _i in spilled:
		if pellets.size() >= max_pellets + SPILL_HEADROOM:
			break
		var offset := Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
		pellets.append(
			((positions[slot] as Vector2) + offset).clamp(
				Vector2(-arena_half, -arena_half), Vector2(arena_half, arena_half)
			)
		)
	var pos: Vector2 = positions[slot]
	var edge := Vector2(signf(pos.x) if absf(pos.x) > absf(pos.y) else 0.0, 0.0)
	if edge == Vector2.ZERO:
		edge = Vector2(0.0, signf(pos.y) if pos.y != 0.0 else 1.0)
	positions[slot] = edge * arena_half * 0.9
	headings[slot] = -edge
	trails[slot] = []
	invuln_left[slot] = CRASH_INVULN_SEC


func _spawn_pellets() -> void:
	while pellets.size() < max_pellets:
		pellets.append(
			Vector2(
				rng.randf_range(-arena_half + 1.0, arena_half - 1.0),
				rng.randf_range(-arena_half + 1.0, arena_half - 1.0)
			)
		)
