class_name HotPotato
extends MinigameBase
## Hot Potato (M4-02, SPEC $7 #3): one bomb, one carrier. Tag another player
## to pass it; when the fuse blows the carrier is eliminated. Three blasts
## (or a lone survivor) end the round early. Less total holding ranks higher.
## Server-side simulation only — the client renders get_snapshot().

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
## Carrier moves 10% faster so tagging a fleeing player is possible.
const CARRIER_SPEED_MULT := 1.1
const TRANSFER_RANGE := PLAYER_RADIUS * 2.0
## No-tag-backs (#809): the player who just passed the bomb can't receive it
## right back for this long, so they get a real chance to run — but the new
## carrier can still tag anyone *else* immediately, unlike the old blanket
## cooldown that froze every transfer.
const NO_TAG_BACK_SEC := 1.0
## Brief full freeze right after a fuse blast reassigns the bomb, so the
## fresh (randomly picked) carrier isn't instantly re-tagged before they can
## even move.
const RESPAWN_GRACE_SEC := 0.75
const FUSE_MIN_SEC := 8.0
const FUSE_MAX_SEC := 14.0
const MAX_BLASTS := 3
## Hold times are compared snapped to this step so ties are meaningful.
const HOLD_SNAP := 0.1

## get_snapshot() wire shape (#708): named indices for the players positional
## array. Array SHAPE on the wire is unchanged — additive only.
const PS_X := 0
const PS_Y := 1
const PS_COUNT := 2

var positions := {}
var move_dirs := {}
## Seconds each slot has carried the bomb, accumulated per tick.
var hold_time := {}
var carrier := -1
var fuse := 0.0
var blasts := 0
## Slots in the order they were eliminated (one per blast).
var eliminated: Array[int] = []

## No-tag-back state: `_tag_back_slot` cannot receive the bomb back while
## `_tag_back_left` counts down.
var _tag_back_slot := -1
var _tag_back_left := 0.0
var _respawn_grace_left := 0.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"hot_potato",
				"controls": "Move — WASD / left stick",
				# Structured spec (#832/#844): the bare-movement template shape.
				"control_spec": [{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE}],
				"name": "Hot Potato",
				"category": MinigameMeta.Category.FFA,
				"min_players": 3,
				"max_players": 8,
				"duration_sec": 75.0,
				"rules": "Tag someone to pass the bomb — when the fuse blows, the carrier is out!",
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * ARENA_HALF * 0.6
		move_dirs[slots[i]] = Vector2.ZERO
		hold_time[slots[i]] = 0.0
	carrier = slots[rng.randi_range(0, slots.size() - 1)]
	fuse = rng.randf_range(FUSE_MIN_SEC, FUSE_MAX_SEC)


func _handle_input(slot: int, data: Dictionary) -> void:
	if not is_alive(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	_tag_back_left = maxf(_tag_back_left - delta, 0.0)
	_respawn_grace_left = maxf(_respawn_grace_left - delta, 0.0)
	for slot: int in alive_slots():
		var speed := MOVE_SPEED * (CARRIER_SPEED_MULT if slot == carrier else 1.0)
		var pos: Vector2 = positions[slot] + move_dirs[slot] * speed * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)
	_resolve_transfer()
	hold_time[carrier] += delta
	fuse -= delta
	if fuse <= 0.0:
		_explode()


func is_alive(slot: int) -> bool:
	return slot in slots and slot not in eliminated


func alive_slots() -> Array:
	return slots.filter(is_alive)


func get_snapshot() -> Dictionary:
	var players := {}
	var holds := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
		holds[slot] = snappedf(hold_time[slot], HOLD_SNAP)
	return {
		"players": players,
		"carrier": carrier,
		"fuse": snappedf(maxf(fuse, 0.0), 0.1),
		"alive": alive_slots(),
		"holds": holds,
	}


## Survivors rank above the eliminated, ordered by ascending snapped hold
## time (less held = better, ties grouped). Eliminated players follow in
## reverse elimination order (later blast = better).
func _rank_players() -> Array:
	var by_hold := {}
	for slot: int in alive_slots():
		var held := snappedf(hold_time[slot], HOLD_SNAP)
		if not by_hold.has(held):
			by_hold[held] = []
		by_hold[held].append(slot)
	var holds := by_hold.keys()
	holds.sort()
	var placements: Array = []
	for held: float in holds:
		placements.append(by_hold[held])
	for i in range(eliminated.size() - 1, -1, -1):
		placements.append([eliminated[i]])
	return placements


func _resolve_transfer() -> void:
	if _respawn_grace_left > 0.0:
		return
	for slot: int in alive_slots():
		if slot == carrier:
			continue
		if slot == _tag_back_slot and _tag_back_left > 0.0:
			continue
		if positions[carrier].distance_to(positions[slot]) <= TRANSFER_RANGE:
			_tag_back_slot = carrier
			_tag_back_left = NO_TAG_BACK_SEC
			carrier = slot
			return


## Fuse ran out: the carrier is eliminated. The bomb respawns on a random
## survivor with a fresh fuse unless the blast cap is hit or one player
## remains — then the round ends immediately.
func _explode() -> void:
	eliminated.append(carrier)
	blasts += 1
	var survivors := alive_slots()
	if blasts < MAX_BLASTS and survivors.size() > 1:
		carrier = survivors[rng.randi_range(0, survivors.size() - 1)]
		fuse = rng.randf_range(FUSE_MIN_SEC, FUSE_MAX_SEC)
		_respawn_grace_left = RESPAWN_GRACE_SEC
		_tag_back_slot = -1
	else:
		finish(_rank_players())
