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
## Grace period after the bomb changes hands so it cannot ping-pong.
const TRANSFER_COOLDOWN_SEC := 0.75
const FUSE_MIN_SEC := 8.0
const FUSE_MAX_SEC := 14.0
const MAX_BLASTS := 3
## Hold times are compared snapped to this step so ties are meaningful.
const HOLD_SNAP := 0.1

var positions := {}
var move_dirs := {}
## Seconds each slot has carried the bomb, accumulated per tick.
var hold_time := {}
var carrier := -1
var fuse := 0.0
var transfer_cooldown := 0.0
var blasts := 0
## Slots in the order they were eliminated (one per blast).
var eliminated: Array[int] = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"hot_potato",
				"controls": "Move — WASD / left stick",
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
	transfer_cooldown = 0.0


func _handle_input(slot: int, data: Dictionary) -> void:
	if not is_alive(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	transfer_cooldown = maxf(transfer_cooldown - delta, 0.0)
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
	if transfer_cooldown > 0.0:
		return
	for slot: int in alive_slots():
		if slot == carrier:
			continue
		if positions[carrier].distance_to(positions[slot]) <= TRANSFER_RANGE:
			carrier = slot
			transfer_cooldown = TRANSFER_COOLDOWN_SEC
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
		transfer_cooldown = TRANSFER_COOLDOWN_SEC
	else:
		finish(_rank_players())
