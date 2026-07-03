class_name TreasureDivers
extends MinigameBase
## Treasure Divers (M10-04, PHASE2.md $4 #21): dive for sunken coins while
## your air meter drains; surface to breathe or black out. Only divers can
## collect; blacking out forces you up, stunned. Most coins at the bell wins.
## Server-side simulation only — the client renders get_snapshot().

const ARENA_HALF := 9.0
const SURFACE_SPEED := 6.0
## Water drag: diving is slower.
const DIVE_SPEED := 4.5
const PLAYER_RADIUS := 0.45
const COLLECT_RADIUS := 0.8
const AIR_MAX_SEC := 5.0
## Surfacing refills air this many times faster than diving drains it.
const AIR_REFILL_RATE := 2.5
const BLACKOUT_STUN_SEC := 2.5
const COIN_WAVE_SEC := 2.0
const COINS_PER_WAVE := 3
const MAX_ACTIVE_COINS := 12

var positions := {}
var move_dirs := {}
var coins := {}
var diving := {}
## Seconds of air left per slot (0..AIR_MAX_SEC).
var air := {}
## Seconds of blackout stun left per slot (0 = fine).
var stunned := {}
var treasure: Array = []

var _wave_left := 0.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"treasure_divers",
				"controls": "Move — WASD / left stick · Hold SPACE / pad A to dive",
				"name": "Treasure Divers",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 6,
				"duration_sec": 60.0,
				"rules":
				"Treasure sinks to the seabed — dive for it, but surface before your air runs out!",
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * ARENA_HALF * 0.6
		move_dirs[slots[i]] = Vector2.ZERO
		coins[slots[i]] = 0
		diving[slots[i]] = false
		air[slots[i]] = AIR_MAX_SEC
		stunned[slots[i]] = 0.0


func _handle_input(slot: int, data: Dictionary) -> void:
	if slot not in slots:
		return
	if data.has("mx"):
		var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
		move_dirs[slot] = dir.limit_length(1.0)
	if data.has("dive"):
		_set_diving(slot, bool(data.dive))


func _tick(delta: float) -> void:
	if finished:
		return
	for slot: int in slots:
		stunned[slot] = maxf(stunned[slot] - delta, 0.0)
		var speed := DIVE_SPEED if diving[slot] else SURFACE_SPEED
		if stunned[slot] > 0.0:
			speed = 0.0
		var pos: Vector2 = positions[slot] + move_dirs[slot] * speed * delta
		positions[slot] = pos.limit_length(ARENA_HALF)
		_tick_air(slot, delta)
	_collect_treasure()
	_spawn_waves(delta)


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			coins[slot],
			1 if diving[slot] else 0,
			snappedf(air[slot] / AIR_MAX_SEC, 0.01),
			snappedf(stunned[slot], 0.01),
		]
	var treasure_list: Array = []
	for pos: Vector2 in treasure:
		treasure_list.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)])
	return {"players": players, "treasure": treasure_list}


## Most coins wins; ties share a group. Coins double as capped pickup coins
## (SPEC $5), matching the Coin Scramble convention.
func _rank_players() -> Array:
	var by_coins := {}
	for slot: int in slots:
		var count: int = coins[slot]
		if not by_coins.has(count):
			by_coins[count] = []
		by_coins[count].append(slot)
	var counts := by_coins.keys()
	counts.sort()
	counts.reverse()
	var placements: Array = []
	for count: int in counts:
		placements.append(by_coins[count])
	_pickup_coins = coins.duplicate()
	return placements


## A stunned or blacked-out player cannot dive; surfacing is always allowed.
func _set_diving(slot: int, wants_dive: bool) -> void:
	if wants_dive and (stunned[slot] > 0.0 or air[slot] <= 0.0):
		return
	diving[slot] = wants_dive


func _tick_air(slot: int, delta: float) -> void:
	if diving[slot]:
		air[slot] = maxf(air[slot] - delta, 0.0)
		if air[slot] <= 0.0:
			# Blackout: forced to the surface, stunned and gasping.
			diving[slot] = false
			stunned[slot] = BLACKOUT_STUN_SEC
	else:
		air[slot] = minf(air[slot] + delta * AIR_REFILL_RATE, AIR_MAX_SEC)


func _collect_treasure() -> void:
	var remaining: Array = []
	for pos: Vector2 in treasure:
		var taken := false
		for slot: int in slots:
			if not diving[slot] or stunned[slot] > 0.0:
				continue
			if positions[slot].distance_to(pos) <= COLLECT_RADIUS + PLAYER_RADIUS:
				coins[slot] += 1
				taken = true
				break
		if not taken:
			remaining.append(pos)
	treasure = remaining


func _spawn_waves(delta: float) -> void:
	_wave_left -= delta
	if _wave_left > 0.0:
		return
	_wave_left = COIN_WAVE_SEC
	for _i in COINS_PER_WAVE:
		if treasure.size() >= MAX_ACTIVE_COINS:
			return
		treasure.append(
			Vector2(
				rng.randf_range(-ARENA_HALF * 0.9, ARENA_HALF * 0.9),
				rng.randf_range(-ARENA_HALF * 0.9, ARENA_HALF * 0.9)
			)
		)
