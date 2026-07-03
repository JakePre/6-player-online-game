class_name ShockTag
extends MinigameBase
## Shock Tag (M10-03, PHASE2.md $4 #20): one player is electrified. They move
## faster, and tagging someone drains coins from the victim into their own
## stash — and passes the zap on. Everyone else banks coins for staying
## clean. Most coins at the bell wins.
## Server-side simulation only — the client renders get_snapshot().

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
## The electrified player closes gaps: same stick, more speed.
const ZAPPED_SPEED := 7.2
const PLAYER_RADIUS := 0.45
const TAG_RANGE := PLAYER_RADIUS * 2.2
const DRAIN_COINS := 5
## Coins banked per full second of staying clean.
const CLEAN_COINS_PER_SEC := 1.0
## A fresh victim cannot be re-tagged by anyone for this long, so the zap
## never ping-pongs inside one collision.
const IMMUNITY_SEC := 1.5

var positions := {}
var move_dirs := {}
var coins := {}
## Slot currently holding the zap.
var zapped := -1
var immunity_left := 0.0

var _clean_progress := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"shock_tag",
				"controls": "Move — WASD / left stick",
				"name": "Shock Tag",
				"category": MinigameMeta.Category.FFA,
				"min_players": 3,
				"max_players": 6,
				"duration_sec": 60.0,
				"rules":
				"The electrified player is faster; a tag steals coins and the zap. Stay clean!",
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * ARENA_HALF * 0.6
		move_dirs[slots[i]] = Vector2.ZERO
		coins[slots[i]] = 0
		_clean_progress[slots[i]] = 0.0
	zapped = slots[rng.randi_range(0, slots.size() - 1)]


func _handle_input(slot: int, data: Dictionary) -> void:
	if slot not in slots:
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	if finished:
		return
	immunity_left = maxf(immunity_left - delta, 0.0)
	for slot: int in slots:
		var speed := ZAPPED_SPEED if slot == zapped else MOVE_SPEED
		var pos: Vector2 = positions[slot] + move_dirs[slot] * speed * delta
		positions[slot] = pos.limit_length(ARENA_HALF)
	_bank_clean_coins(delta)
	_resolve_tag()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), coins[slot]]
	return {
		"players": players,
		"zapped": zapped,
		"immunity": snappedf(immunity_left, 0.01),
	}


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


func _bank_clean_coins(delta: float) -> void:
	for slot: int in slots:
		if slot == zapped:
			continue
		_clean_progress[slot] += CLEAN_COINS_PER_SEC * delta
		while _clean_progress[slot] >= 1.0:
			_clean_progress[slot] -= 1.0
			coins[slot] += 1


func _resolve_tag() -> void:
	if immunity_left > 0.0 or zapped == -1:
		return
	for slot: int in slots:
		if slot == zapped:
			continue
		if positions[zapped].distance_to(positions[slot]) > TAG_RANGE:
			continue
		var drained := mini(DRAIN_COINS, int(coins[slot]))
		coins[slot] -= drained
		coins[zapped] += drained
		zapped = slot
		immunity_left = IMMUNITY_SEC
		return
