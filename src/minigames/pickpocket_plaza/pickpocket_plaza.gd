class_name PickpocketPlaza
extends MinigameBase
## Pickpocket Plaza (M10-14, PHASE2.md $4 #31): a crowd of seeded villagers
## wanders the plaza; the thieves work the crowd, lifting coins. One random
## slot is the GUARD — but the guard has no visible avatar: they secretly
## puppet one of the visually identical crowd bodies. The guard's SLOT is
## public (the roster names them), but WHICH body they inhabit is the secret,
## delivered only to the guard via get_private_snapshot() (#254, the same
## hidden-role hook The Mole uses). The shared snapshot renders every crowd
## body identically and never leaks the guard body until the end reveal.
##
## Thieves score the coins they keep; the guard scores per arrest (counted as
## coins for ranking). Standing near a villager for a beat lifts a coin and
## marks the thief a SUSPECT for a short window; the guard, patrolling in
## disguise, arrests a nearby recent-lifter — stunning them and shaking loose
## their coins. Server-side simulation only.

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
## The crowd (and the guard's disguised body) drift slowly — the guard cannot
## be picked out by speed, only by behaviour.
const VILLAGER_SPEED := 3.0
const PLAYER_RADIUS := 0.45
const CROWD_SIZE := 9
## Continuous proximity to a villager needed to lift one coin.
const PICKPOCKET_RADIUS := 1.0
const LIFT_SEC := 1.2
## After a lift the thief must reposition before the next.
const LIFT_COOLDOWN := 1.5
## A pickpocketed villager is "empty" and unliftable for this long.
const VILLAGER_COOLDOWN := 2.5
## How long after a lift a thief stays arrestable (the guard's window).
const SUSPECT_SEC := 3.0
const ARREST_RADIUS := 1.6
const ARREST_COOLDOWN := 2.5
const STUN_SEC := 3.0
## Coins shaken loose from an arrested thief.
const DROP_COINS := 2
const ARREST_POINTS := 3
## A wandering villager repicks a waypoint once it arrives here.
const WAYPOINT_REACHED := 0.5
## Owner-picked fix (#805): a villager currently in steal range slows way
## down, so a channel a thief actually started can be finished instead of
## losing contact to their wander mid-lift.
const HELD_SPEED_MULT := 0.3
## The arrest commotion: a public flash (it reveals the guard, as an arrest
## always must) that fades over this long.
const ALARM_SEC := 1.0
const DURATION_SEC := 60.0

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const CR_X := 0
const CR_Y := 1

const TH_X := 0
const TH_Y := 1
const TH_STUN := 2
const TH_SUSPECT := 3
const TH_COUNT := 4

var guard := -1
var thieves: Array[int] = []
## thief slot -> Vector2 (the guard has no thief avatar; they are a crowd body)
var positions := {}
var move_dirs := {}
## Crowd body positions, index 0..CROWD_SIZE-1. One of these is the guard.
var crowd: Array[Vector2] = []
var guard_body := -1
var loot := {}
var arrests := 0
## thief slot -> remaining stun seconds (frozen, can't move or lift)
var stun := {}
## thief slot -> the `elapsed` value until which they can be arrested
var suspect_until := {}
var alarm_left := 0.0

var _guard_dir := Vector2.ZERO
var _waypoints: Array[Vector2] = []
var _lift_accum := {}
var _lift_cd := {}
var _body_cd: Array[float] = []
var _arrest_cd := 0.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"pickpocket_plaza",
				"name": "Pickpocket Plaza",
				"category": MinigameMeta.Category.SABOTAGE,
				"min_players": 3,
				"max_players": 6,
				"duration_sec": DURATION_SEC,
				"rules":
				(
					"Work the crowd and lift coins — but one of you is the GUARD,"
					+ " hidden among the villagers. Get caught mid-lift and you're"
					+ " stunned and robbed. Guard: patrol in disguise and arrest the thieves!"
				),
				"controls": "Move — WASD / left stick · Arrest (guard) — SPACE / pad A",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				[
					"Move — WASD / left stick · Arrest (guard) — ",
					{"action": &"action_primary"},
				],
				# Structured spec (#832/#844): move + role-qualified action.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Arrest (guard)", "input": &"action_primary"},
				],
			}
		)
	)


func _setup() -> void:
	guard = slots[rng.randi_range(0, slots.size() - 1)]
	for slot: int in slots:
		if slot == guard:
			continue
		thieves.append(slot)
	for i in thieves.size():
		var angle := TAU * i / maxi(thieves.size(), 1)
		var slot: int = thieves[i]
		positions[slot] = Vector2(cos(angle), sin(angle)) * ARENA_HALF * 0.7
		move_dirs[slot] = Vector2.ZERO
		loot[slot] = 0
		stun[slot] = 0.0
		suspect_until[slot] = -1.0
		_lift_accum[slot] = 0.0
		_lift_cd[slot] = 0.0
	guard_body = rng.randi_range(0, CROWD_SIZE - 1)
	for _i in CROWD_SIZE:
		crowd.append(_random_point())
		_waypoints.append(_random_point())
		_body_cd.append(0.0)


## The one place the guard's disguise exists outside the server until the end
## reveal (#254). Thieves learn nothing; the guard learns which body is theirs.
func get_private_snapshot(slot: int) -> Dictionary:
	if slot == guard and not finished:
		return {"role": "guard", "body": guard_body}
	return {}


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0))).limit_length(1.0)
	if slot == guard:
		_guard_dir = dir
		if data.get("act", false):
			_try_arrest()
		return
	if float(stun[slot]) > 0.0:
		return
	move_dirs[slot] = dir


func _try_arrest() -> void:
	if _arrest_cd > 0.0:
		return
	_arrest_cd = ARREST_COOLDOWN
	var body: Vector2 = crowd[guard_body]
	var target := -1
	var best := ARREST_RADIUS
	for slot: int in thieves:
		if float(stun[slot]) > 0.0 or float(suspect_until[slot]) < elapsed:
			continue
		var d: float = positions[slot].distance_to(body)
		if d <= best:
			best = d
			target = slot
	if target == -1:
		return
	stun[target] = STUN_SEC
	suspect_until[target] = -1.0
	move_dirs[target] = Vector2.ZERO
	loot[target] = maxi(0, int(loot[target]) - DROP_COINS)
	arrests += 1
	alarm_left = ALARM_SEC


func _tick(delta: float) -> void:
	_arrest_cd = maxf(_arrest_cd - delta, 0.0)
	alarm_left = maxf(alarm_left - delta, 0.0)
	for i in CROWD_SIZE:
		_body_cd[i] = maxf(_body_cd[i] - delta, 0.0)
	for slot: int in thieves:
		stun[slot] = maxf(float(stun[slot]) - delta, 0.0)
		_lift_cd[slot] = maxf(float(_lift_cd[slot]) - delta, 0.0)
	_move_thieves(delta)
	_move_crowd(delta, _bodies_in_contact())
	_pickpocket(delta)


func _move_thieves(delta: float) -> void:
	for slot: int in thieves:
		if float(stun[slot]) > 0.0:
			continue
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = _clamped(pos)


## Villager bodies (including the guard's disguise, which must behave
## identically or its speed alone would out them) within steal range of any
## unstunned thief right now.
func _bodies_in_contact() -> Array[bool]:
	var held: Array[bool] = []
	held.resize(CROWD_SIZE)
	held.fill(false)
	for slot: int in thieves:
		if float(stun[slot]) > 0.0:
			continue
		for i in CROWD_SIZE:
			if positions[slot].distance_to(crowd[i]) <= PICKPOCKET_RADIUS:
				held[i] = true
	return held


func _move_crowd(delta: float, held: Array[bool]) -> void:
	for i in CROWD_SIZE:
		var speed := VILLAGER_SPEED * (HELD_SPEED_MULT if held[i] else 1.0)
		if i == guard_body:
			crowd[i] = _clamped(crowd[i] + _guard_dir * speed * delta)
			continue
		var to_target: Vector2 = _waypoints[i] - crowd[i]
		if to_target.length() <= WAYPOINT_REACHED:
			_waypoints[i] = _random_point()
			to_target = _waypoints[i] - crowd[i]
		var step := to_target.normalized() * speed * delta
		if step.length() >= to_target.length():
			crowd[i] = _waypoints[i]
		else:
			crowd[i] = _clamped(crowd[i] + step)


func _pickpocket(delta: float) -> void:
	for slot: int in thieves:
		if float(stun[slot]) > 0.0 or float(_lift_cd[slot]) > 0.0:
			_lift_accum[slot] = 0.0
			continue
		var body := _liftable_body(positions[slot])
		if body == -1:
			_lift_accum[slot] = 0.0
			continue
		_lift_accum[slot] = float(_lift_accum[slot]) + delta
		if float(_lift_accum[slot]) >= LIFT_SEC:
			_lift_accum[slot] = 0.0
			_lift_cd[slot] = LIFT_COOLDOWN
			_body_cd[body] = VILLAGER_COOLDOWN
			loot[slot] = int(loot[slot]) + 1
			suspect_until[slot] = elapsed + SUSPECT_SEC


## The nearest villager close enough to lift from and not on empty cooldown.
func _liftable_body(from: Vector2) -> int:
	var found := -1
	var best := PICKPOCKET_RADIUS
	for i in CROWD_SIZE:
		if _body_cd[i] > 0.0:
			continue
		var d := from.distance_to(crowd[i])
		if d <= best:
			best = d
			found = i
	return found


func get_snapshot() -> Dictionary:
	var crowd_list: Array = []
	for body in crowd:
		# Every body — the guard's included — is written identically.
		crowd_list.append([snappedf(body.x, 0.01), snappedf(body.y, 0.01)])
	var thief_list := {}
	for slot: int in thieves:
		var pos: Vector2 = positions[slot]
		thief_list[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			1 if float(stun[slot]) > 0.0 else 0,
			1 if float(suspect_until[slot]) >= elapsed else 0,
		]
	var snapshot := {
		"crowd": crowd_list,
		"thieves": thief_list,
		"guard": guard,
		"scores": _scores(),
		"alarm": alarm_left > 0.0,
		"time_left": snappedf(maxf(effective_duration() - elapsed, 0.0), 0.1),
	}
	if finished:
		# The job is over — the disguise may go public now, not before.
		snapshot["reveal"] = {"guard": guard, "body": guard_body}
	return snapshot


func _scores() -> Dictionary:
	var out := {}
	for slot: int in slots:
		out[slot] = _points(slot)
	return out


func _points(slot: int) -> int:
	if slot == guard:
		return arrests * ARREST_POINTS
	return int(loot.get(slot, 0))


## Coins decide placement, ties grouped (SPEC $5 FFA tables); the guard's
## arrest points count as coins.
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
	_pickup_coins = _scores()
	return placements


func _random_point() -> Vector2:
	return Vector2(
		rng.randf_range(-ARENA_HALF, ARENA_HALF), rng.randf_range(-ARENA_HALF, ARENA_HALF)
	)


func _clamped(pos: Vector2) -> Vector2:
	return pos.clamp(Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF))
