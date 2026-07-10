class_name BombCourier
extends MinigameBase
## Bomb Courier (M10-15, PHASE2 §4 #32): a delivery scramble where the
## "saboteur" is a universal mechanic, not a hidden role (net-model rationale
## in issue #252, same as the Poison Feast #174 rework). Packages spawn at a
## central pile with a visible ticking fuse; carry one to the depot before it
## blows for points. A swap-dash foists your near-dead package onto a rival —
## everyone can play saboteur. A defuse zone converts a live package to a
## safe partial score. Highest score wins. Server-side simulation only.

const ARENA_HALF := 10.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const PICKUP_RADIUS := 0.9
## Central spawn pile and the two functional zones.
const PILE_POS := Vector2(0.0, 6.0)
const DEPOT_POS := Vector2(0.0, -7.0)
const DEFUSE_POS := Vector2(-7.0, 2.0)
const ZONE_RADIUS := 1.6
const SPAWN_SEC := 1.5
const MAX_PILE := 4
## Fuse length randomized per package; delivering with more left scores more.
const FUSE_MIN := 4.0
const FUSE_MAX := 7.0
const DELIVER_BASE := 3
const DELIVER_FUSE_BONUS := 2  # points per whole second of fuse remaining
const DEFUSE_POINTS := 1
const DETONATE_PENALTY := 2
const STUN_SEC := 2.0
## Swap-dash: short lunge on a cooldown; overlapping a carrier swaps packages.
const DASH_SPEED := 16.0
const DASH_SEC := 0.18
const DASH_COOLDOWN_SEC := 1.5
const SWAP_RADIUS := 1.2

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_SCORE := 2
const PS_FUSE := 3
const PS_STAGGERED := 4
const PS_COUNT := 5

const PL_ID := 0
const PL_X := 1
const PL_Y := 2
const PL_FUSE := 3
const PL_COUNT := 4

var positions := {}
var move_dirs := {}
var score := {}
## slot -> package id currently carried, or -1.
var carried := {}
var staggers := {}
var dash_timers := {}
var dash_cooldowns := {}
var dash_dirs := {}
## Loose packages on the pile: id -> {pos, fuse}. Carried ones live in
## `_packages` too so the fuse keeps ticking in hand.
var _packages := {}
var _next_id := 0
var _spawn_accum := 0.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"bomb_courier",
				"name": "Bomb Courier",
				"category": MinigameMeta.Category.SABOTAGE,
				"min_players": 3,
				"max_players": 8,
				"duration_sec": 60.0,
				"rules":
				(
					"Rush packages from the pile to the depot before the fuse blows!"
					+ " Dash into a rival to swap packages and dump your dud on them."
					+ " Defuse the hot ones for scraps. Most delivered wins."
				),
				"controls": "Move — WASD / left stick · Swap-dash — SPACE / pad A",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				["Move — WASD / left stick · Swap-dash — ", {"action": &"action_primary"}],
				# Structured spec (#832/#844): the move + action template shape.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Swap-dash", "input": &"action_primary"},
				],
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * 3.0
		move_dirs[slots[i]] = Vector2.ZERO
		score[slots[i]] = 0
		carried[slots[i]] = -1
		staggers[slots[i]] = 0.0
		dash_timers[slots[i]] = 0.0
		dash_cooldowns[slots[i]] = 0.0
		dash_dirs[slots[i]] = Vector2.ZERO
	for _i in MAX_PILE:
		_spawn_package()


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if (
		data.get("dash", false)
		and float(staggers[slot]) <= 0.0
		and float(dash_timers[slot]) <= 0.0
		and float(dash_cooldowns[slot]) <= 0.0
	):
		var aim := dir if dir.length() > 0.1 else Vector2(0.0, -1.0)
		dash_dirs[slot] = aim.normalized()
		dash_timers[slot] = DASH_SEC
		dash_cooldowns[slot] = DASH_COOLDOWN_SEC


func _tick(delta: float) -> void:
	_tick_fuses(delta)
	for slot: int in slots:
		staggers[slot] = maxf(0.0, float(staggers[slot]) - delta)
		dash_cooldowns[slot] = maxf(0.0, float(dash_cooldowns[slot]) - delta)
		var velocity: Vector2 = move_dirs[slot] * MOVE_SPEED
		if float(dash_timers[slot]) > 0.0:
			dash_timers[slot] = maxf(0.0, float(dash_timers[slot]) - delta)
			velocity = dash_dirs[slot] * DASH_SPEED
		elif float(staggers[slot]) > 0.0:
			velocity = Vector2.ZERO
		var pos: Vector2 = positions[slot] + velocity * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	_resolve_dash_swaps()
	_resolve_pickups()
	_resolve_zones()
	_spawn_accum += delta
	if _spawn_accum >= SPAWN_SEC:
		_spawn_accum -= SPAWN_SEC
		_spawn_package()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		var fuse := -1.0
		if int(carried[slot]) != -1:
			fuse = float(_packages[carried[slot]].fuse)
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			score[slot],
			snappedf(fuse, 0.05),
			1 if float(staggers[slot]) > 0.0 else 0,
		]
	var pile: Array = []
	for id: int in _packages:
		if _carrier_of(id) == -1:
			var pkg: Dictionary = _packages[id]
			var pos: Vector2 = pkg.pos
			pile.append(
				[id, snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pkg.fuse, 0.05)]
			)
	return {"players": players, "pile": pile}


func _rank_players() -> Array:
	var by_score := {}
	for slot: int in slots:
		var value: int = score[slot]
		if not by_score.has(value):
			by_score[value] = []
		by_score[value].append(slot)
	var values := by_score.keys()
	values.sort()
	values.reverse()
	var placements: Array = []
	for value: int in values:
		placements.append(by_score[value])
	return placements


func _tick_fuses(delta: float) -> void:
	for id: int in _packages.keys():
		var pkg: Dictionary = _packages[id]
		pkg.fuse = float(pkg.fuse) - delta
		if float(pkg.fuse) <= 0.0:
			_detonate(id)


func _detonate(id: int) -> void:
	var carrier := _carrier_of(id)
	if carrier != -1:
		score[carrier] = int(score[carrier]) - DETONATE_PENALTY
		staggers[carrier] = STUN_SEC
		carried[carrier] = -1
	_packages.erase(id)


## Dashing through a rival swaps carried packages — steal theirs if you are
## empty-handed, otherwise trade (dump your dud on them).
func _resolve_dash_swaps() -> void:
	for slot: int in slots:
		if float(dash_timers[slot]) <= 0.0:
			continue
		for other: int in slots:
			if other == slot or float(staggers[other]) > 0.0:
				continue
			if positions[slot].distance_to(positions[other]) > SWAP_RADIUS:
				continue
			if int(carried[slot]) == -1 and int(carried[other]) == -1:
				continue
			var tmp: int = carried[slot]
			carried[slot] = carried[other]
			carried[other] = tmp
			# One swap per dash, and end the lunge so it can't chain-steal.
			dash_timers[slot] = 0.0
			break


func _resolve_pickups() -> void:
	for slot: int in slots:
		if int(carried[slot]) != -1 or float(staggers[slot]) > 0.0:
			continue
		for id: int in _packages:
			if _carrier_of(id) != -1:
				continue
			if positions[slot].distance_to(_packages[id].pos) <= PICKUP_RADIUS:
				carried[slot] = id
				break


func _resolve_zones() -> void:
	for slot: int in slots:
		var id: int = carried[slot]
		if id == -1:
			continue
		if positions[slot].distance_to(DEPOT_POS) <= ZONE_RADIUS:
			var fuse: float = _packages[id].fuse
			score[slot] = int(score[slot]) + DELIVER_BASE + int(floorf(fuse)) * DELIVER_FUSE_BONUS
			_packages.erase(id)
			carried[slot] = -1
		elif positions[slot].distance_to(DEFUSE_POS) <= ZONE_RADIUS:
			score[slot] = int(score[slot]) + DEFUSE_POINTS
			_packages.erase(id)
			carried[slot] = -1


func _spawn_package() -> void:
	var loose := 0
	for id: int in _packages:
		if _carrier_of(id) == -1:
			loose += 1
	if loose >= MAX_PILE:
		return
	var offset := Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
	_packages[_next_id] = {"pos": PILE_POS + offset, "fuse": rng.randf_range(FUSE_MIN, FUSE_MAX)}
	_next_id += 1


func _carrier_of(id: int) -> int:
	for slot: int in slots:
		if int(carried[slot]) == id:
			return slot
	return -1
